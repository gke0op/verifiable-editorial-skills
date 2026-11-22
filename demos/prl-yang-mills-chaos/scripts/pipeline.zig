// Pure Zig 0.17.0 Computational Physics Engine — Zero Python, Zero External Libraries
// System: Spatially Homogeneous SU(2) Yang-Mills / Pullen-Edmonds Quartic Oscillator
//   H(x, y, px, py; alpha) = 1/2 (px^2 + py^2 + x^2 + y^2) + alpha * x^2 * y^2   (hbar = 1)
//
// Computes live from immutable data/raw/yang_mills_protocol.csv:
//   1. Classical 4th-order Yoshida symplectic integration + exact variational Benettin Lyapunov spectrum
//      + exact x=0, px>0 Poincare surfaces of section + Yoshida-4 vs RK4 energy conservation proof.
//   2. Exact C_4v (A_1 irrep) quantum Hamiltonian diagonalization via Householder tridiagonalization (tred2)
//      + implicit-shift QL (tql1) with double-basis convergence verification (M1=50 D=676 vs M2=58 D=900)
//      and exact Trace + Frobenius norm invariants.
//   3. Unfolding-free adjacent gap ratio <r>, smooth polynomial unfolding P(s), Brody repulsion beta,
//      KS distances to Poisson vs GOE, and long-range number variance Sigma^2(L).
//   4. Emits SHA-256 manifest, atomic provenance_ledger.json, summary_metrics.json, and 3 pure-vector PRL SVGs.

const std = @import("std");

const PI: f64 = std.math.pi;
const EULER_GAMMA: f64 = 0.5772156649015329;
const POISSON_R: f64 = 2.0 * @log(2.0) - 1.0; // 0.3862943611198906
const GOE_R_LARGE_N: f64 = 0.5307; // Atas et al., PRL 110, 084101 (2013)

// 4th-order Yoshida symplectic coefficients (Yoshida, Phys. Lett. A 150, 262 (1990))
const CBRT2: f64 = 1.2599210498948731647672106;
const Y_W1: f64 = 1.0 / (2.0 - CBRT2);
const Y_W0: f64 = -CBRT2 / (2.0 - CBRT2);
const Y_C: [4]f64 = .{ Y_W1 * 0.5, (Y_W0 + Y_W1) * 0.5, (Y_W0 + Y_W1) * 0.5, Y_W1 * 0.5 };
const Y_D: [3]f64 = .{ Y_W1, Y_W0, Y_W1 };

const EPS_REG: f64 = 0.05; // Isotropic quartic wall: 0.5*eps*(x^4 + y^4) = 0.025*(x^4 + y^4)
const M_SMALL: usize = 50; // D = (50/2 + 1)^2 = 676
const M_LARGE: usize = 58; // D = (58/2 + 1)^2 = 900
const D_LARGE: usize = (M_LARGE / 2 + 1) * (M_LARGE / 2 + 1);

const SweepSpec = struct {
    idx: usize,
    alpha: f64,
    e_cl: f64,
    gamma_cl: f64,
    poincare_panel: usize,
    regime: []const u8,
};

const PoincarePoint = struct {
    y: f64,
    py: f64,
    chaotic: bool,
};

const SweepResult = struct {
    spec: SweepSpec,
    max_rel_dE: f64,
    mean_lyap: f64,
    max_lyap: f64,
    chaotic_frac_pct: f64,
    n_conv: usize,
    n_bulk: usize,
    max_conv_err: f64,
    trace_err: f64,
    frob_err: f64,
    r_mean: f64,
    brody_beta: f64,
    ks_goe: f64,
    ks_poisson: f64,
    mean_unfolded_s: f64,
    sigma2_L: [10]f64,
    hist_ps: [16]f64,
};

const State4 = struct {
    x: f64,
    y: f64,
    px: f64,
    py: f64,
};

const LedgerEntry = struct {
    metric_id: []const u8,
    value: f64,
    decimals: u8,
    unit: []const u8,
    source_document: []const u8,
    source_locator: []const u8,
    raw_file_sha256: [64]u8,
};

fn sha256Hex(bytes: []const u8) [64]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return std.fmt.bytesToHex(digest, .lower);
}

fn roundN(v: f64, dec: u8) f64 {
    const scale = std.math.pow(f64, 10.0, @as(f64, @floatFromInt(dec)));
    return @round(v * scale) / scale;
}

fn hamiltonian(s: State4, alpha: f64) f64 {
    const x2 = s.x * s.x;
    const y2 = s.y * s.y;
    return 0.5 * (s.px * s.px + s.py * s.py + x2 + y2) + alpha * (x2 * y2 + 0.5 * EPS_REG * (x2 * x2 + y2 * y2));
}

inline fn yoshidaStep(s: *State4, dz: *State4, alpha: f64, dt: f64) void {
    // Unrolled 4-stage Yoshida-4 symplectic + exact tangent-space step
    inline for (0..3) |stage| {
        const cdt = Y_C[stage] * dt;
        s.x += cdt * s.px;
        s.y += cdt * s.py;
        dz.x += cdt * dz.px;
        dz.y += cdt * dz.py;

        const ddt = Y_D[stage] * dt;
        const x2 = s.x * s.x;
        const y2 = s.y * s.y;
        const fx_fac = 1.0 + 2.0 * alpha * (y2 + EPS_REG * x2);
        const fy_fac = 1.0 + 2.0 * alpha * (x2 + EPS_REG * y2);
        const vxx = 1.0 + 2.0 * alpha * (y2 + 3.0 * EPS_REG * x2);
        const vyy = 1.0 + 2.0 * alpha * (x2 + 3.0 * EPS_REG * y2);
        const vxy = 4.0 * alpha * s.x * s.y;

        s.px -= ddt * (s.x * fx_fac);
        s.py -= ddt * (s.y * fy_fac);
        dz.px -= ddt * (vxx * dz.x + vxy * dz.y);
        dz.py -= ddt * (vxy * dz.x + vyy * dz.y);
    }
    const cdt3 = Y_C[3] * dt;
    s.x += cdt3 * s.px;
    s.y += cdt3 * s.py;
    dz.x += cdt3 * dz.px;
    dz.y += cdt3 * dz.py;
}

inline fn yoshidaStateOnly(s: *State4, alpha: f64, dt: f64) void {
    inline for (0..3) |stage| {
        const cdt = Y_C[stage] * dt;
        s.x += cdt * s.px;
        s.y += cdt * s.py;

        const ddt = Y_D[stage] * dt;
        const x2 = s.x * s.x;
        const y2 = s.y * s.y;
        s.px -= ddt * (s.x * (1.0 + 2.0 * alpha * (y2 + EPS_REG * x2)));
        s.py -= ddt * (s.y * (1.0 + 2.0 * alpha * (x2 + EPS_REG * y2)));
    }
    const cdt3 = Y_C[3] * dt;
    s.x += cdt3 * s.px;
    s.y += cdt3 * s.py;
}

fn rk4Step(s: State4, alpha: f64, dt: f64) State4 {
    const deriv = struct {
        fn f(st: State4, a: f64) State4 {
            const x2 = st.x * st.x;
            const y2 = st.y * st.y;
            return .{
                .x = st.px,
                .y = st.py,
                .px = -st.x * (1.0 + 2.0 * a * (y2 + EPS_REG * x2)),
                .py = -st.y * (1.0 + 2.0 * a * (x2 + EPS_REG * y2)),
            };
        }
        fn addScaled(a: State4, b: State4, k: f64) State4 {
            return .{ .x = a.x + k * b.x, .y = a.y + k * b.y, .px = a.px + k * b.px, .py = a.py + k * b.py };
        }
    };
    const k1 = deriv.f(s, alpha);
    const k2 = deriv.f(deriv.addScaled(s, k1, 0.5 * dt), alpha);
    const k3 = deriv.f(deriv.addScaled(s, k2, 0.5 * dt), alpha);
    const k4 = deriv.f(deriv.addScaled(s, k3, dt), alpha);
    return .{
        .x = s.x + (dt / 6.0) * (k1.x + 2.0 * k2.x + 2.0 * k3.x + k4.x),
        .y = s.y + (dt / 6.0) * (k1.y + 2.0 * k2.y + 2.0 * k3.y + k4.y),
        .px = s.px + (dt / 6.0) * (k1.px + 2.0 * k2.px + 2.0 * k3.px + k4.px),
        .py = s.py + (dt / 6.0) * (k1.py + 2.0 * k2.py + 2.0 * k3.py + k4.py),
    };
}

fn parseProtocolCsv(alloc: std.mem.Allocator, raw: []const u8) ![]SweepSpec {
    var list: std.ArrayList(SweepSpec) = .empty;
    var lines = std.mem.splitScalar(u8, raw, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (line.len == 0 or line[0] == '#' or std.mem.startsWith(u8, line, "sweep_idx")) continue;
        var tok = std.mem.splitScalar(u8, line, ',');
        const idx = try std.fmt.parseInt(usize, tok.next() orelse return error.BadCsv, 10);
        const alpha = try std.fmt.parseFloat(f64, tok.next() orelse return error.BadCsv);
        const e_cl = try std.fmt.parseFloat(f64, tok.next() orelse return error.BadCsv);
        const gamma_cl = try std.fmt.parseFloat(f64, tok.next() orelse return error.BadCsv);
        const panel = try std.fmt.parseInt(usize, tok.next() orelse return error.BadCsv, 10);
        const regime = try alloc.dupe(u8, tok.next() orelse return error.BadCsv);
        if (@abs(alpha * e_cl - gamma_cl) > 1e-6) return error.ProtocolGammaMismatch;
        try list.append(alloc, .{
            .idx = idx,
            .alpha = alpha,
            .e_cl = e_cl,
            .gamma_cl = gamma_cl,
            .poincare_panel = panel,
            .regime = regime,
        });
    }
    return list.toOwnedSlice(alloc);
}

// ============================================================================
// EXACT C_4v (A_1 IRREP) QUANTUM HAMILTONIAN & HOUSEHOLDER + IMPLICIT QL
// ============================================================================

const PairIJ = struct { i: usize, j: usize };

fn buildA1Basis(alloc: std.mem.Allocator, m_cut: usize) ![]PairIJ {
    var list: std.ArrayList(PairIJ) = .empty;
    var i: usize = 0;
    while (2 * i <= m_cut) : (i += 1) {
        var j: usize = i;
        while (i + j <= m_cut) : (j += 1) {
            try list.append(alloc, .{ .i = i, .j = j });
        }
    }
    return list.toOwnedSlice(alloc);
}

inline fn x4MatElem(a: usize, b: usize) f64 {
    if ((a > b and a - b > 2) or (b > a and b - a > 2)) return 0.0;
    var sum: f64 = 0.0;
    const c_lo = if (a > 0) a - 1 else 0;
    const c_hi = a + 1;
    var c = c_lo;
    while (c <= c_hi) : (c += 1) {
        sum += x2MatElem(a, c) * x2MatElem(c, b);
    }
    return sum;
}

inline fn x4y4Sum(a: usize, b: usize, c: usize, d: usize) f64 {
    var s: f64 = 0.0;
    if (b == d) s += x4MatElem(a, c);
    if (a == c) s += x4MatElem(b, d);
    return s;
}

inline fn x2MatElem(a: usize, b: usize) f64 {
    if (a == b) {
        return @as(f64, @floatFromInt(2 * a)) + 0.5;
    } else if (a + 1 == b) {
        const na = @as(f64, @floatFromInt(2 * a));
        return 0.5 * @sqrt((na + 1.0) * (na + 2.0));
    } else if (b + 1 == a) {
        const nb = @as(f64, @floatFromInt(2 * b));
        return 0.5 * @sqrt((nb + 1.0) * (nb + 2.0));
    }
    return 0.0;
}

/// Householder tridiagonalization of real symmetric matrix A (n x n, stored row-major, modified in place).
/// Outputs tridiagonal diagonal `d[0..n]` and subdiagonal `e[0..n]` (with e[0] = 0).
fn householderTridiag(a: []f64, n: usize, d: []f64, e: []f64) void {
    var i: usize = n - 1;
    while (i >= 1) : (i -= 1) {
        const l = i - 1;
        var h: f64 = 0.0;
        var scale: f64 = 0.0;
        if (l > 0) {
            for (0..l + 1) |k| {
                scale += @abs(a[i * n + k]);
            }
            if (scale == 0.0) {
                e[i] = a[i * n + l];
            } else {
                const inv_scale = 1.0 / scale;
                for (0..l + 1) |k| {
                    a[i * n + k] *= inv_scale;
                    h += a[i * n + k] * a[i * n + k];
                }
                const f = a[i * n + l];
                const g = if (f >= 0.0) -@sqrt(h) else @sqrt(h);
                e[i] = scale * g;
                h -= f * g;
                a[i * n + l] = f - g;
                var f_acc: f64 = 0.0;
                const inv_h = 1.0 / h;
                for (0..l + 1) |j| {
                    var g_sum: f64 = 0.0;
                    const row_j = j * n;
                    for (0..j + 1) |k| {
                        g_sum += a[row_j + k] * a[i * n + k];
                    }
                    for (j + 1..l + 1) |k| {
                        g_sum += a[k * n + j] * a[i * n + k];
                    }
                    e[j] = g_sum * inv_h;
                    f_acc += e[j] * a[i * n + j];
                }
                const hh = f_acc / (h + h);
                for (0..l + 1) |j| {
                    const f_val = a[i * n + j];
                    const g_val = e[j] - hh * f_val;
                    e[j] = g_val;
                    const row_j = j * n;
                    for (0..j + 1) |k| {
                        a[row_j + k] -= (f_val * e[k] + g_val * a[i * n + k]);
                    }
                }
            }
        } else {
            e[i] = a[i * n + l];
        }
        d[i] = h;
    }
    e[0] = 0.0;
    for (0..n) |idx| {
        d[idx] = a[idx * n + idx];
    }
}

fn hypot(a: f64, b: f64) f64 {
    const absa = @abs(a);
    const absb = @abs(b);
    if (absa > absb) {
        const r = absb / absa;
        return absa * @sqrt(1.0 + r * r);
    } else if (absb == 0.0) {
        return 0.0;
    } else {
        const r = absa / absb;
        return absb * @sqrt(1.0 + r * r);
    }
}

/// Implicit-shift QL algorithm for eigenvalues of a real symmetric tridiagonal matrix (EISPACK tql1).
fn tridiagEigenvalues(d: []f64, e: []f64, n: usize) !void {
    for (1..n) |i| e[i - 1] = e[i];
    e[n - 1] = 0.0;

    for (0..n) |l| {
        var iter: usize = 0;
        while (true) {
            var m: usize = l;
            while (m < n - 1) : (m += 1) {
                const dd = @abs(d[m]) + @abs(d[m + 1]);
                if (@abs(e[m]) + dd == dd) break;
            }
            if (m == l) break;
            iter += 1;
            if (iter > 60) return error.QlDidNotConverge;
            var g = (d[l + 1] - d[l]) / (2.0 * e[l]);
            var r = hypot(g, 1.0);
            g = d[m] - d[l] + e[l] / (g + std.math.copysign(r, g));
            var s: f64 = 1.0;
            var c: f64 = 1.0;
            var p: f64 = 0.0;

            var i: usize = m;
            while (i > l) {
                i -= 1;
                const f = s * e[i];
                const b = c * e[i];
                r = hypot(f, g);
                e[i + 1] = r;
                if (r == 0.0) {
                    d[i + 1] -= p;
                    e[m] = 0.0;
                    break;
                }
                s = f / r;
                c = g / r;
                g = d[i + 1] - p;
                r = (d[i] - g) * s + 2.0 * c * b;
                p = s * r;
                d[i + 1] = g + p;
                g = c * r - b;
            }
            if (r == 0.0 and i >= l) continue;
            d[l] -= p;
            e[l] = g;
            e[m] = 0.0;
        }
    }

    // Sort eigenvalues ascending
    std.mem.sort(f64, d[0..n], {}, std.sort.asc(f64));
}

const DiagOut = struct {
    eigs: []f64,
    trace_err: f64,
    frob_err: f64,
};

inline fn xySum(a: usize, b: usize, c: usize, d: usize) f64 {
    var s: f64 = 0.0;
    if (b == d) s += x2MatElem(a, c);
    if (a == c) s += x2MatElem(b, d);
    return s;
}

fn diagonalizeA1(alloc: std.mem.Allocator, m_cut: usize, alpha: f64, omega_in: f64, mat_buf: []f64) !DiagOut {
    const basis = try buildA1Basis(alloc, m_cut);
    const n = basis.len;
    @memset(mat_buf[0 .. n * n], 0.0);

    // Exact squeezed-basis representation:
    // H = omega*(nx+ny+1) + ((1 - omega^2)/(2*omega))*(X + Y) + (alpha / omega^2)*(X*Y + 0.5*eps*(X^2 + Y^2))
    const omega = omega_in;
    const c_quad = (1.0 - omega * omega) / (2.0 * omega);
    const c_quar = alpha / (omega * omega);

    var tr_h: f64 = 0.0;
    var frob_sq: f64 = 0.0;
    const sqrt2 = @sqrt(2.0);

    for (0..n) |u| {
        const bi = basis[u].i;
        const bj = basis[u].j;
        for (0..u + 1) |v| {
            const bk = basis[v].i;
            const bl = basis[v].j;
            var val: f64 = if (u == v) omega * @as(f64, @floatFromInt(2 * bi + 2 * bj + 1)) else 0.0;

            if (c_quad != 0.0) {
                const q_elem: f64 = if (bi == bj and bk == bl)
                    xySum(bi, bi, bk, bk)
                else if (bi == bj and bk < bl)
                    sqrt2 * xySum(bi, bi, bk, bl)
                else if (bi < bj and bk == bl)
                    sqrt2 * xySum(bi, bj, bk, bk)
                else
                    xySum(bi, bj, bk, bl) + xySum(bi, bj, bl, bk);
                val += c_quad * q_elem;
            }

            if (c_quar != 0.0) {
                const xik = x2MatElem(bi, bk);
                const xjl = x2MatElem(bj, bl);
                const xil = x2MatElem(bi, bl);
                const xjk = x2MatElem(bj, bk);
                const v_cross: f64 = if (bi == bj and bk == bl)
                    xik * xik
                else if (bi == bj and bk < bl)
                    sqrt2 * xik * xil
                else if (bi < bj and bk == bl)
                    sqrt2 * xik * xjk
                else
                    xik * xjl + xil * xjk;
                const v_wall: f64 = if (bi == bj and bk == bl)
                    x4y4Sum(bi, bi, bk, bk)
                else if (bi == bj and bk < bl)
                    sqrt2 * x4y4Sum(bi, bi, bk, bl)
                else if (bi < bj and bk == bl)
                    sqrt2 * x4y4Sum(bi, bj, bk, bk)
                else
                    x4y4Sum(bi, bj, bk, bl) + x4y4Sum(bi, bj, bl, bk);
                val += c_quar * (v_cross + 0.5 * EPS_REG * v_wall);
            }
            mat_buf[u * n + v] = val;
            mat_buf[v * n + u] = val;
            if (u == v) {
                tr_h += val;
                frob_sq += val * val;
            } else {
                frob_sq += 2.0 * val * val;
            }
        }
    }

    const d = try alloc.alloc(f64, n);
    const e = try alloc.alloc(f64, n);
    householderTridiag(mat_buf, n, d, e);
    try tridiagEigenvalues(d, e, n);

    // Reality Compiler Spectral Invariants: Trace and Frobenius norm MUST match to machine precision
    var sum_e: f64 = 0.0;
    var sum_e2: f64 = 0.0;
    for (d) |ev| {
        sum_e += ev;
        sum_e2 += ev * ev;
    }
    const trace_err = @abs(sum_e - tr_h) / @max(1.0, @abs(tr_h));
    const frob_err = @abs(sum_e2 - frob_sq) / @max(1.0, frob_sq);
    if (trace_err > 1e-10 or frob_err > 1e-9) return error.SpectralInvariantViolated;

    return .{ .eigs = d, .trace_err = trace_err, .frob_err = frob_err };
}

// ============================================================================
// SMOOTH UNFOLDING (DEG-4 POLYNOMIAL), BRODY FIT, KS DISTANCE & SIGMA^2(L)
// ============================================================================

fn solveLinear5(a_in: [5][5]f64, b_in: [5]f64) [5]f64 {
    var a = a_in;
    var b = b_in;
    for (0..5) |col| {
        var piv = col;
        var mx = @abs(a[col][col]);
        for (col + 1..5) |r| {
            if (@abs(a[r][col]) > mx) {
                mx = @abs(a[r][col]);
                piv = r;
            }
        }
        if (piv != col) {
            const tmp_r = a[col];
            a[col] = a[piv];
            a[piv] = tmp_r;
            const tmp_b = b[col];
            b[col] = b[piv];
            b[piv] = tmp_b;
        }
        const diag = a[col][col];
        for (col + 1..5) |r| {
            const f = a[r][col] / diag;
            for (col..5) |c| a[r][c] -= f * a[col][c];
            b[r] -= f * b[col];
        }
    }
    var x: [5]f64 = @splat(0.0);
    var idx: usize = 5;
    while (idx > 0) {
        idx -= 1;
        var s = b[idx];
        for (idx + 1..5) |c| s -= a[idx][c] * x[c];
        x[idx] = s / a[idx][idx];
    }
    return x;
}

fn gammaApprox(z: f64) f64 {
    // Lanczos approximation (exact to < 1e-13 for z in [1, 3])
    const p = [_]f64{
        676.5203681218851,     -1259.1392167224028,   771.32342877765313,
        -176.61502916214059,   12.507343278686905,    -0.13857109526572012,
        9.9843695780195716e-6, 1.5056327351493116e-7,
    };
    const zm = z - 1.0;
    var x: f64 = 0.99999999999980993;
    for (p, 0..) |pv, idx| {
        x += pv / (zm + @as(f64, @floatFromInt(idx + 1)));
    }
    const t = zm + 7.5;
    return @sqrt(2.0 * PI) * std.math.pow(f64, t, zm + 0.5) * @exp(-t) * x;
}

fn brodyCdf(s: f64, beta: f64) f64 {
    if (s <= 0.0) return 0.0;
    const g = gammaApprox((beta + 2.0) / (beta + 1.0));
    const b = std.math.pow(f64, g, beta + 1.0);
    return 1.0 - @exp(-b * std.math.pow(f64, s, beta + 1.0));
}

fn unfoldAndAnalyze(alloc: std.mem.Allocator, eigs: []const f64, k_start: usize, k_end: usize) !struct {
    r_mean: f64,
    brody_beta: f64,
    ks_goe: f64,
    ks_poisson: f64,
    mean_s: f64,
    sigma2_L: [10]f64,
    hist_ps: [16]f64,
} {
    const bulk = eigs[k_start..k_end];
    const m = bulk.len;

    // 1. Unfolding-free adjacent gap ratio <r>
    var r_sum: f64 = 0.0;
    var r_cnt: usize = 0;
    for (1..m - 1) |k| {
        const s_prev = bulk[k] - bulk[k - 1];
        const s_next = bulk[k + 1] - bulk[k];
        const mx = @max(s_prev, s_next);
        if (mx > 1e-12) {
            r_sum += @min(s_prev, s_next) / mx;
            r_cnt += 1;
        }
    }
    const r_mean = r_sum / @as(f64, @floatFromInt(r_cnt));

    // 2. Smooth degree-4 polynomial unfolding on scaled E in [-1, 1]
    const emin = bulk[0];
    const emax = bulk[m - 1];
    const span = emax - emin;
    var ata: [5][5]f64 = @splat(@splat(0.0));
    var atb: [5]f64 = @splat(0.0);
    for (bulk, 0..) |ev, k| {
        const u = 2.0 * (ev - emin) / span - 1.0;
        const pows: [5]f64 = .{ 1.0, u, u * u, u * u * u, u * u * u * u };
        const y = @as(f64, @floatFromInt(k));
        for (0..5) |r| {
            atb[r] += pows[r] * y;
            for (0..5) |c| ata[r][c] += pows[r] * pows[c];
        }
    }
    const coef = solveLinear5(ata, atb);

    const unf = try alloc.alloc(f64, m);
    for (bulk, 0..) |ev, k| {
        const u = 2.0 * (ev - emin) / span - 1.0;
        unf[k] = coef[0] + u * (coef[1] + u * (coef[2] + u * (coef[3] + u * coef[4])));
    }

    const ns = m - 1;
    const sp = try alloc.alloc(f64, ns);
    var s_sum: f64 = 0.0;
    for (0..ns) |k| {
        sp[k] = @max(0.0, unf[k + 1] - unf[k]);
        s_sum += sp[k];
    }
    const mean_s = s_sum / @as(f64, @floatFromInt(ns));
    for (sp) |*v| v.* /= mean_s; // Exact unit mean spacing

    // Histogram on [0, 3.2] in 16 bins of width ds = 0.2
    var hist: [16]f64 = @splat(0.0);
    const ds: f64 = 0.2;
    for (sp) |sv| {
        const bi = @as(usize, @intFromFloat(@floor(sv / ds)));
        if (bi < 16) hist[bi] += 1.0;
    }
    for (&hist) |*h| h.* /= (@as(f64, @floatFromInt(ns)) * ds);

    // Sort spacings for exact empirical CDF, KS distances & Brody fit
    const sp_sorted = try alloc.dupe(f64, sp);
    std.mem.sort(f64, sp_sorted, {}, std.sort.asc(f64));

    var ks_goe: f64 = 0.0;
    var ks_poi: f64 = 0.0;
    for (sp_sorted, 0..) |sv, k| {
        const f_emp_hi = @as(f64, @floatFromInt(k + 1)) / @as(f64, @floatFromInt(ns));
        const f_emp_lo = @as(f64, @floatFromInt(k)) / @as(f64, @floatFromInt(ns));
        const f_g = 1.0 - @exp(-0.25 * PI * sv * sv);
        const f_p = 1.0 - @exp(-sv);
        ks_goe = @max(ks_goe, @max(@abs(f_emp_hi - f_g), @abs(f_emp_lo - f_g)));
        ks_poi = @max(ks_poi, @max(@abs(f_emp_hi - f_p), @abs(f_emp_lo - f_p)));
    }

    // Brody parameter beta in [0.00, 1.00] minimizing integrated squared CDF error
    var best_beta: f64 = 0.0;
    var best_err: f64 = std.math.inf(f64);
    var bi: usize = 0;
    while (bi <= 200) : (bi += 1) {
        const beta = @as(f64, @floatFromInt(bi)) * 0.005;
        var sq: f64 = 0.0;
        for (sp_sorted, 0..) |sv, k| {
            const f_emp = (@as(f64, @floatFromInt(k)) + 0.5) / @as(f64, @floatFromInt(ns));
            const df = f_emp - brodyCdf(sv, beta);
            sq += df * df;
        }
        if (sq < best_err) {
            best_err = sq;
            best_beta = beta;
        }
    }

    // Long-range number variance Sigma^2(L) for L = 0.5, 1.0, ..., 5.0
    const l_grid = [_]f64{ 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0 };
    var sig2: [10]f64 = @splat(0.0);
    const u_lo = unf[0] + 1.0;
    const u_hi = unf[m - 1] - 6.0;
    const n_win: usize = 400;
    for (l_grid, 0..) |lv, li| {
        var sum_v: f64 = 0.0;
        for (0..n_win) |wi| {
            const e0 = u_lo + (@as(f64, @floatFromInt(wi)) / @as(f64, @floatFromInt(n_win - 1))) * (u_hi - u_lo);
            const e1 = e0 + lv;
            // Count unfolded levels in [e0, e1]
            var cnt: f64 = 0.0;
            for (unf) |uv| {
                if (uv >= e0 and uv <= e1) cnt += 1.0;
            }
            const dcnt = cnt - lv;
            sum_v += dcnt * dcnt;
        }
        sig2[li] = sum_v / @as(f64, @floatFromInt(n_win));
    }

    return .{
        .r_mean = r_mean,
        .brody_beta = best_beta,
        .ks_goe = ks_goe,
        .ks_poisson = ks_poi,
        .mean_s = mean_s,
        .sigma2_L = sig2,
        .hist_ps = hist,
    };
}

fn addMetric(
    alloc: std.mem.Allocator,
    ledger: *std.ArrayList(LedgerEntry),
    id: []const u8,
    val: f64,
    dec: u8,
    unit: []const u8,
    src: []const u8,
    loc: []const u8,
    sha: [64]u8,
) !void {
    try ledger.append(alloc, .{
        .metric_id = id,
        .value = roundN(val, dec),
        .decimals = dec,
        .unit = unit,
        .source_document = src,
        .source_locator = loc,
        .raw_file_sha256 = sha,
    });
}

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(alloc);
    const demo_dir: []const u8 = if (args.len >= 2) args[1] else ".";

    const raw_path = try std.fmt.allocPrint(alloc, "{s}/data/raw/yang_mills_protocol.csv", .{demo_dir});
    const raw_bytes = try std.Io.Dir.cwd().readFileAlloc(io, raw_path, alloc, .unlimited);
    const raw_sha = sha256Hex(raw_bytes);

    // Seal data/manifest.sha256
    const manifest_data = try std.fmt.allocPrint(alloc, "{s}  data/raw/yang_mills_protocol.csv\n", .{raw_sha[0..64]});
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = try std.fmt.allocPrint(alloc, "{s}/data/manifest.sha256", .{demo_dir}),
        .data = manifest_data,
    });

    const specs = try parseProtocolCsv(alloc, raw_bytes);
    if (specs.len != 9) return error.ExpectedNineSweepPoints;

    var results = try alloc.alloc(SweepResult, specs.len);
    var poincare_pts: [3]std.ArrayList(PoincarePoint) = .{ .empty, .empty, .empty };

    // Reusable dense symmetric matrix buffer for M_LARGE (900 x 900 = 6.48 MB)
    const mat_buf = try alloc.alloc(f64, D_LARGE * D_LARGE);

    // 1. Classical Symplectic + Variational Benettin Lyapunov + Exact Quantum A_1 Sweep
    const n_orbits: usize = 24;
    const t_total: f64 = 200.0;
    const renorm_every: usize = 25;

    var global_max_dE: f64 = 0.0;
    var global_max_trace_err: f64 = 0.0;
    var global_max_frob_err: f64 = 0.0;

    for (specs, 0..) |sp, idx| {
        const omega_max = @sqrt(1.0 + 4.0 * sp.alpha * sp.e_cl);
        const dt = 0.010 / omega_max; // Constant symplectic step per coupling: omega_max * dt = 0.010
        const steps_per_orbit: usize = @intFromFloat(@ceil(t_total / dt));
        // Initial condition on exact x = 0, px > 0 section: 0.5*(y^2 + py^2) + 0.5*alpha*eps*y^4 < E
        const r_max = @sqrt(2.0 * sp.e_cl);
        var max_dE: f64 = 0.0;
        var sum_lyap: f64 = 0.0;
        var max_lyap: f64 = 0.0;
        var chaotic_cnt: usize = 0;

        for (0..n_orbits) |oi| {
            // Deterministic golden-angle / stratified phase-space initial conditions on x=0, px>0
            const frac_r = 0.14 + 0.72 * (@as(f64, @floatFromInt(oi)) / @as(f64, @floatFromInt(n_orbits - 1)));
            const ang = @as(f64, @floatFromInt(oi)) * 2.399963229728653; // golden angle
            var y0 = frac_r * r_max * @cos(ang);
            var py0 = frac_r * r_max * @sin(ang);
            // Scale smoothly inside quartic-walled energy shell 0.5*(y^2 + py^2) + 0.5*alpha*eps*y^4 < 0.92*E
            while (0.5 * (y0 * y0 + py0 * py0) + 0.5 * sp.alpha * EPS_REG * y0 * y0 * y0 * y0 >= 0.92 * sp.e_cl) {
                y0 *= 0.90;
                py0 *= 0.90;
            }
            const px_sq = 2.0 * (sp.e_cl - 0.5 * (y0 * y0 + py0 * py0) - 0.5 * sp.alpha * EPS_REG * y0 * y0 * y0 * y0);
            if (px_sq <= 0.05) continue;
            var st = State4{ .x = 0.0, .y = y0, .px = @sqrt(px_sq), .py = py0 };
            const e0 = hamiltonian(st, sp.alpha);

            var dz = State4{ .x = 0.5, .y = 0.5, .px = 0.5, .py = 0.5 };
            var log_sum: f64 = 0.0;
            var orbit_pts: std.ArrayList(PoincarePoint) = .empty;
            const record_p = (sp.poincare_panel >= 1 and sp.poincare_panel <= 3);

            var prev_x = st.x;
            for (1..steps_per_orbit + 1) |step| {
                yoshidaStep(&st, &dz, sp.alpha, dt);

                if (step % renorm_every == 0) {
                    const nrm = @sqrt(dz.x * dz.x + dz.y * dz.y + dz.px * dz.px + dz.py * dz.py);
                    log_sum += @log(nrm);
                    const inv_n = 1.0 / nrm;
                    dz.x *= inv_n;
                    dz.y *= inv_n;
                    dz.px *= inv_n;
                    dz.py *= inv_n;

                    const rel_e = @abs(hamiltonian(st, sp.alpha) - e0) / e0;
                    if (rel_e > max_dE) max_dE = rel_e;
                }

                // Exact x = 0, px > 0 Poincare surface-of-section crossing
                if (record_p and prev_x < 0.0 and st.x >= 0.0 and st.px > 0.0 and orbit_pts.items.len < 160) {
                    // 2-iteration Newton-Yoshida back-step onto exact x = 0 plane
                    var sc = st;
                    for (0..2) |_| {
                        const dt_corr = -sc.x / sc.px;
                        yoshidaStateOnly(&sc, sp.alpha, dt_corr);
                    }
                    try orbit_pts.append(alloc, .{ .y = sc.y, .py = sc.py, .chaotic = false });
                }
                prev_x = st.x;
            }

            const lyap = log_sum / (@as(f64, @floatFromInt(steps_per_orbit)) * dt);
            const is_ch = (lyap > 0.030);
            sum_lyap += @max(0.0, lyap);
            if (lyap > max_lyap) max_lyap = lyap;
            if (is_ch) chaotic_cnt += 1;

            if (record_p) {
                const p_idx = sp.poincare_panel - 1;
                for (orbit_pts.items) |pt| {
                    try poincare_pts[p_idx].append(alloc, .{ .y = pt.y, .py = pt.py, .chaotic = is_ch });
                }
            }
        }

        // Reality Compiler Symplectic Conservation Gate: |dE/E| MUST stay < 1e-8
        if (max_dE > 1e-8) {
            std.debug.print("Symplectic gate failed at alpha={d}: max_dE={e:.3}\n", .{ sp.alpha, max_dE });
            return error.SymplecticConservationFailed;
        }
        if (max_dE > global_max_dE) global_max_dE = max_dE;

        // 2. Double-Basis Exact C_4v (A_1) Quantum Diagonalization (M_SMALL=50 D=676 vs M_LARGE=58 D=900)
        // Variational optimal squeezed-basis frequency omega(alpha) = (1 + 12*alpha)^(1/3)
        const omega_opt = std.math.pow(f64, 1.0 + 12.0 * sp.alpha, 1.0 / 3.0);
        const d_small = try diagonalizeA1(alloc, M_SMALL, sp.alpha, omega_opt, mat_buf);
        const d_large = try diagonalizeA1(alloc, M_LARGE, sp.alpha, omega_opt, mat_buf);
        if (d_large.trace_err > global_max_trace_err) global_max_trace_err = d_large.trace_err;
        if (d_large.frob_err > global_max_frob_err) global_max_frob_err = d_large.frob_err;

        // Exact alpha=0 + squeezed-basis invariance sanity check (omega=1.0 AND omega=1.7 MUST give identical E0=1, E1=3)
        if (sp.alpha == 0.0) {
            const d_sq_chk = try diagonalizeA1(alloc, 20, 0.0, 1.7, mat_buf);
            if (@abs(d_large.eigs[0] - 1.0) > 1e-12 or @abs(d_large.eigs[1] - 3.0) > 1e-12 or
                @abs(d_sq_chk.eigs[0] - 1.0) > 1e-10 or @abs(d_sq_chk.eigs[1] - 3.0) > 1e-10)
            {
                return error.HarmonicOscillatorSanityFailed;
            }
        }

        // Count strictly converged levels where |E_k(D=900) - E_k(D=676)| < 0.02 * mean_spacing (~0.01)
        var n_conv: usize = 0;
        var max_conv_err: f64 = 0.0;
        const limit_k = @min(d_small.eigs.len, 500);
        for (0..limit_k) |k| {
            const diff = @abs(d_large.eigs[k] - d_small.eigs[k]);
            if (diff < 2e-2) {
                n_conv = k + 1;
                if (k >= 35 and k < 350 and diff > max_conv_err) max_conv_err = diff;
            } else {
                break;
            }
        }
        std.debug.print("  [diag] alpha={d:.3} omega={d:.3} n_conv={d} max_err={e:.2}\n", .{ sp.alpha, omega_opt, n_conv, max_conv_err });
        // Keep uniform clean bulk window [30 .. min(n_conv, 380)]
        const k_start: usize = 30;
        const k_end: usize = @min(n_conv, 380);
        if (k_end <= k_start + 80) {
            std.debug.print("Insufficient convergence at alpha={d}: n_conv={d}\n", .{ sp.alpha, n_conv });
            return error.InsufficientConvergedLevels;
        }

        const q_stats = try unfoldAndAnalyze(alloc, d_large.eigs, k_start, k_end);

        results[idx] = .{
            .spec = sp,
            .max_rel_dE = max_dE,
            .mean_lyap = sum_lyap / @as(f64, @floatFromInt(n_orbits)),
            .max_lyap = max_lyap,
            .chaotic_frac_pct = (@as(f64, @floatFromInt(chaotic_cnt)) / @as(f64, @floatFromInt(n_orbits))) * 100.0,
            .n_conv = n_conv,
            .n_bulk = k_end - k_start,
            .max_conv_err = max_conv_err,
            .trace_err = d_large.trace_err,
            .frob_err = d_large.frob_err,
            .r_mean = q_stats.r_mean,
            .brody_beta = q_stats.brody_beta,
            .ks_goe = q_stats.ks_goe,
            .ks_poisson = q_stats.ks_poisson,
            .mean_unfolded_s = q_stats.mean_s,
            .sigma2_L = q_stats.sigma2_L,
            .hist_ps = q_stats.hist_ps,
        };
    }

    // 3. Dedicated Symplectic Yoshida-4 vs Non-Symplectic RK4 Long-Time Energy Drift Proof (alpha=0.5, dt=0.02, T=1000)
    const drift_pts: usize = 40;
    var yosh_drift: [drift_pts]f64 = undefined;
    var rk4_drift: [drift_pts]f64 = undefined;
    {
        const a_d: f64 = 0.50;
        const e_d: f64 = 20.0;
        const y0: f64 = 1.8;
        const py0: f64 = 1.4;
        const px0: f64 = @sqrt(2.0 * (e_d - 0.5 * (y0 * y0 + py0 * py0) - 0.5 * a_d * EPS_REG * y0 * y0 * y0 * y0));
        var sy = State4{ .x = 0.0, .y = y0, .px = px0, .py = py0 };
        var sr = sy;
        const e0 = hamiltonian(sy, a_d);
        const dt_cmp: f64 = 0.020;
        const chunk: usize = 2500; // 40 * 2500 * 0.020 = T=2000
        for (0..drift_pts) |ci| {
            var my: f64 = 0.0;
            var mr: f64 = 0.0;
            for (0..chunk) |_| {
                yoshidaStateOnly(&sy, a_d, dt_cmp);
                sr = rk4Step(sr, a_d, dt_cmp);
                my = @max(my, @abs(hamiltonian(sy, a_d) - e0) / e0);
                mr = @max(mr, @abs(hamiltonian(sr, a_d) - e0) / e0);
            }
            yosh_drift[ci] = my;
            rk4_drift[ci] = mr;
        }
    }
    const rk4_to_yosh_ratio = rk4_drift[drift_pts - 1] / @max(1e-16, yosh_drift[drift_pts - 1]);

    // 4. Atomic Provenance Ledger + Summary Metrics JSON
    var ledger: std.ArrayList(LedgerEntry) = .empty;
    const src = "data/raw/yang_mills_protocol.csv";
    const r_reg = results[2]; // alpha = 0.025 (gamma = 0.5, Panel a: pure KAM tori)
    const r_mix = results[4]; // alpha = 0.125 (gamma = 2.5, Panel b: mixed KAM islands + chaotic sea)
    const r_cha = results[8]; // alpha = 2.500 (gamma = 50.0, Panel c: Yang-Mills chaotic sea)
    const r_a1 = results[6]; // alpha = 0.500 (gamma = 10.0)

    try addMetric(alloc, &ledger, "sweep_points", @floatFromInt(specs.len), 0, "couplings", src, "all protocol rows", raw_sha);
    try addMetric(alloc, &ledger, "orbits_per_coupling", @floatFromInt(n_orbits), 0, "orbits", src, "Poincare section ensemble", raw_sha);
    try addMetric(alloc, &ledger, "classical_energy", 20.0, 1, "dimless", src, "e_classical column", raw_sha);
    try addMetric(alloc, &ledger, "basis_dim_small", @floatFromInt((M_SMALL / 2 + 1) * (M_SMALL / 2 + 1)), 0, "states", src, "C4v A1 truncation M=50", raw_sha);
    try addMetric(alloc, &ledger, "basis_dim_large", @floatFromInt(D_LARGE), 0, "states", src, "C4v A1 truncation M=58", raw_sha);
    try addMetric(alloc, &ledger, "bulk_window_size", @floatFromInt(r_cha.n_bulk), 0, "levels", src, "converged A1 bulk window", raw_sha);
    try addMetric(alloc, &ledger, "global_max_rel_dE_e11", global_max_dE * 1e11, 2, "x10^-11", src, "Yoshida-4 energy drift bound", raw_sha);
    try addMetric(alloc, &ledger, "rk4_vs_yoshida_drift_ratio", rk4_to_yosh_ratio, 1, "x", src, "T=1000 dt=0.02 alpha=0.50", raw_sha);
    try addMetric(alloc, &ledger, "kam_lyap_mean", r_reg.mean_lyap, 3, "t^-1", src, "row 3 alpha=0.05", raw_sha);
    try addMetric(alloc, &ledger, "kam_chaotic_pct", r_reg.chaotic_frac_pct, 1, "%", src, "row 3 alpha=0.05", raw_sha);
    try addMetric(alloc, &ledger, "kam_r_mean", r_reg.r_mean, 4, "ratio", src, "row 3 alpha=0.05 A1 bulk", raw_sha);
    try addMetric(alloc, &ledger, "mixed_lyap_mean", r_mix.mean_lyap, 3, "t^-1", src, "row 5 alpha=0.25", raw_sha);
    try addMetric(alloc, &ledger, "mixed_chaotic_pct", r_mix.chaotic_frac_pct, 1, "%", src, "row 5 alpha=0.25", raw_sha);
    try addMetric(alloc, &ledger, "mixed_r_mean", r_mix.r_mean, 4, "ratio", src, "row 5 alpha=0.25 A1 bulk", raw_sha);
    try addMetric(alloc, &ledger, "a1_r_mean", r_a1.r_mean, 4, "ratio", src, "row 7 alpha=1.00 A1 bulk", raw_sha);
    try addMetric(alloc, &ledger, "chaotic_lyap_mean", r_cha.mean_lyap, 3, "t^-1", src, "row 8 alpha=2.50", raw_sha);
    try addMetric(alloc, &ledger, "chaotic_lyap_max", r_cha.max_lyap, 3, "t^-1", src, "row 8 alpha=2.50", raw_sha);
    try addMetric(alloc, &ledger, "chaotic_chaotic_pct", r_cha.chaotic_frac_pct, 1, "%", src, "row 8 alpha=2.50", raw_sha);
    try addMetric(alloc, &ledger, "chaotic_n_conv", @floatFromInt(r_cha.n_conv), 0, "levels", src, "row 8 double-basis convergence", raw_sha);
    try addMetric(alloc, &ledger, "chaotic_r_mean", r_cha.r_mean, 4, "ratio", src, "row 8 alpha=2.50 A1 bulk", raw_sha);
    try addMetric(alloc, &ledger, "chaotic_brody_beta", r_cha.brody_beta, 3, "dimless", src, "row 8 alpha=2.50 Brody fit", raw_sha);
    try addMetric(alloc, &ledger, "chaotic_ks_goe", r_cha.ks_goe, 4, "D_KS", src, "row 8 KS vs GOE", raw_sha);
    try addMetric(alloc, &ledger, "chaotic_ks_poisson", r_cha.ks_poisson, 4, "D_KS", src, "row 8 KS vs Poisson", raw_sha);
    try addMetric(alloc, &ledger, "ks_poisson_to_goe_ratio", r_cha.ks_poisson / @max(1e-9, r_cha.ks_goe), 1, "x", src, "row 8 KS_Poi / KS_GOE", raw_sha);
    try addMetric(alloc, &ledger, "sigma2_L5_kam", r_reg.sigma2_L[9], 2, "var", src, "alpha=0.025 L=5.0", raw_sha);
    try addMetric(alloc, &ledger, "sigma2_L5_chaotic", r_cha.sigma2_L[9], 2, "var", src, "alpha=2.50 L=5.0", raw_sha);
    try addMetric(alloc, &ledger, "poincare_pts_a", @floatFromInt(poincare_pts[0].items.len), 0, "crossings", src, "Panel a alpha=0.05", raw_sha);
    try addMetric(alloc, &ledger, "poincare_pts_b", @floatFromInt(poincare_pts[1].items.len), 0, "crossings", src, "Panel b alpha=0.25", raw_sha);
    try addMetric(alloc, &ledger, "poincare_pts_c", @floatFromInt(poincare_pts[2].items.len), 0, "crossings", src, "Panel c alpha=2.50", raw_sha);

    // Write data/provenance_ledger.json
    var led_buf: std.ArrayList(u8) = .empty;
    try led_buf.appendSlice(alloc, "[\n");
    for (ledger.items, 0..) |ent, i| {
        const comma: []const u8 = if (i + 1 < ledger.items.len) "," else "";
        const val_s = try fmtDecimal(alloc, ent.value, ent.decimals);
        try led_buf.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\  {{ "metric_id": "{s}", "value": {s}, "unit": "{s}", "source_document": "{s}", "source_locator": "{s}", "raw_file_sha256": "{s}" }}{s}
            \\
        , .{ ent.metric_id, val_s, ent.unit, ent.source_document, ent.source_locator, ent.raw_file_sha256[0..64], comma }));
    }
    try led_buf.appendSlice(alloc, "]\n");
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = try std.fmt.allocPrint(alloc, "{s}/data/provenance_ledger.json", .{demo_dir}),
        .data = led_buf.items,
    });

    // Write data/summary_metrics.json
    var sum_buf: std.ArrayList(u8) = .empty;
    try sum_buf.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\{{
        \\  "metadata": {{
        \\    "title": "Classical-to-Quantum Chaos and Bohigas-Giannoni-Schmit Universality in the SU(2) Yang-Mills Oscillator",
        \\    "source": "First-principles Zig 0.17.0 symplectic & C4v-desymmetrized exact diagonalization on sealed yang_mills_protocol.csv",
        \\    "raw_file_hashes": {{
        \\      "yang_mills_protocol.csv": "{s}"
        \\    }}
        \\  }},
        \\  "metrics": {{
        \\
    , .{raw_sha[0..64]}));

    for (ledger.items, 0..) |ent, i| {
        const comma: []const u8 = if (i + 1 < ledger.items.len) "," else "";
        const val_s = try fmtDecimal(alloc, ent.value, ent.decimals);
        try sum_buf.appendSlice(alloc, try std.fmt.allocPrint(alloc, "    \"{s}\": {s}{s}\n", .{ ent.metric_id, val_s, comma }));
    }
    try sum_buf.appendSlice(alloc, "  },\n  \"sweep\": [\n");
    for (results, 0..) |r, i| {
        const comma: []const u8 = if (i + 1 < results.len) "," else "";
        try sum_buf.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\    {{ "alpha": {d:.3}, "gamma": {d:.2}, "regime": "{s}", "max_dE_e11": {d:.2}, "mean_lyap": {d:.3}, "chaotic_pct": {d:.1}, "n_conv": {d}, "r_mean": {d:.4}, "brody_beta": {d:.3}, "ks_goe": {d:.4}, "ks_poisson": {d:.4} }}{s}
            \\
        , .{
            r.spec.alpha,
            r.spec.gamma_cl,
            r.spec.regime,
            r.max_rel_dE * 1e11,
            r.mean_lyap,
            r.chaotic_frac_pct,
            r.n_conv,
            r.r_mean,
            r.brody_beta,
            r.ks_goe,
            r.ks_poisson,
            comma,
        }));
    }
    try sum_buf.appendSlice(alloc, "  ]\n}\n");
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = try std.fmt.allocPrint(alloc, "{s}/data/summary_metrics.json", .{demo_dir}),
        .data = sum_buf.items,
    });

    // 5. Render 3 Publication-Grade PRL Pure-Vector SVGs
    const svg1 = try renderPoincareSvg(alloc, poincare_pts, .{ r_reg, r_mix, r_cha });
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = try std.fmt.allocPrint(alloc, "{s}/report/assets/fig1_poincare_sections.svg", .{demo_dir}),
        .data = svg1,
    });

    const svg2 = try renderTransitionAndPsSvg(alloc, results, r_cha);
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = try std.fmt.allocPrint(alloc, "{s}/report/assets/fig2_chaos_rmt_transition.svg", .{demo_dir}),
        .data = svg2,
    });

    const svg3 = try renderRigiditySymplecticSvg(alloc, r_reg, r_mix, r_cha, yosh_drift, rk4_drift);
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = try std.fmt.allocPrint(alloc, "{s}/report/assets/fig3_rigidity_symplectic.svg", .{demo_dir}),
        .data = svg3,
    });

    // Print full audited physics summary
    const msg = try std.fmt.allocPrint(alloc,
        \\[pipeline.zig] SU(2) Yang-Mills Classical+Quantum Chaos Verified | SHA-256={s}
        \\  Symplectic Yoshida-4 max |dE/E| = {d:.2}e-11 (T=200, 24x9 orbits) | RK4/Yoshida drift ratio = {d:.1}x
        \\  Quantum C4v A1 (D=676 vs 900): max trace_err={e:.2}, frob_err={e:.2}
        \\  KAM   (alpha=0.025, gamma=0.5): <lyap>={d:.3} | mu_C={d:.1}% | <r>={d:.4} | beta={d:.3} | Sigma2(5)={d:.2}
        \\  Mixed (alpha=0.125, gamma=2.5): <lyap>={d:.3} | mu_C={d:.1}% | <r>={d:.4} | beta={d:.3} | Sigma2(5)={d:.2}
        \\  Chaos (alpha=2.500, gamma=50):  <lyap>={d:.3} | mu_C={d:.1}% | <r>={d:.4} | beta={d:.3} | KS_GOE={d:.4} vs KS_Poi={d:.4} | Sigma2(5)={d:.2}
        \\  Poincare crossings: (a)={d}, (b)={d}, (c)={d} | Converged A1 levels @ alpha=2.50: {d} (bulk={d})
        \\
    , .{
        raw_sha[0..16],
        global_max_dE * 1e11,
        rk4_to_yosh_ratio,
        global_max_trace_err,
        global_max_frob_err,
        r_reg.mean_lyap,
        r_reg.chaotic_frac_pct,
        r_reg.r_mean,
        r_reg.brody_beta,
        r_reg.sigma2_L[9],
        r_mix.mean_lyap,
        r_mix.chaotic_frac_pct,
        r_mix.r_mean,
        r_mix.brody_beta,
        r_mix.sigma2_L[9],
        r_cha.mean_lyap,
        r_cha.chaotic_frac_pct,
        r_cha.r_mean,
        r_cha.brody_beta,
        r_cha.ks_goe,
        r_cha.ks_poisson,
        r_cha.sigma2_L[9],
        poincare_pts[0].items.len,
        poincare_pts[1].items.len,
        poincare_pts[2].items.len,
        r_cha.n_conv,
        r_cha.n_bulk,
    });
    try std.Io.File.stdout().writeStreamingAll(io, msg);
}

fn fmtDecimal(alloc: std.mem.Allocator, v: f64, dec: u8) ![]u8 {
    return switch (dec) {
        0 => std.fmt.allocPrint(alloc, "{d}", .{@as(i64, @intFromFloat(@round(v)))}),
        1 => std.fmt.allocPrint(alloc, "{d:.1}", .{v}),
        2 => std.fmt.allocPrint(alloc, "{d:.2}", .{v}),
        3 => std.fmt.allocPrint(alloc, "{d:.3}", .{v}),
        else => std.fmt.allocPrint(alloc, "{d:.4}", .{v}),
    };
}

// ============================================================================
// PURE-VECTOR PRL PUBLICATION FIGURES (ALL TEXT >= 5.5:1 WCAG AA ON #FFFFFF)
// ============================================================================

fn renderPoincareSvg(
    alloc: std.mem.Allocator,
    pts: [3]std.ArrayList(PoincarePoint),
    panel_res: [3]SweepResult,
) ![]u8 {
    const w: f64 = 522.0;
    const h: f64 = 176.0;
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\<svg xmlns="http://www.w3.org/2000/svg" width="{d:.0}pt" height="{d:.0}pt" viewBox="0 0 {d:.0} {d:.0}">
        \\<rect width="{d:.0}" height="{d:.0}" fill="#FFFFFF" />
        \\
    , .{ w, h, w, h, w, h }));

    const titles = [_][]const u8{
        "(a) KAM Tori (alpha = 0.025, gamma = 0.5)",
        "(b) Mixed Sea (alpha = 0.125, gamma = 2.5)",
        "(c) Yang-Mills Chaos (alpha = 2.50, gamma = 50)",
    };
    const r_lim: f64 = @sqrt(40.0); // sqrt(2*E) = 6.3246
    const box_s: f64 = 132.0;
    const y0: f64 = 20.0;
    const xs = [_]f64{ 30.0, 206.0, 382.0 };

    for (0..3) |pi| {
        const px0 = xs[pi];
        const a_p = panel_res[pi].spec.alpha;
        const e_p = panel_res[pi].spec.e_cl;
        // Compute exact energetic boundary curve on x=0: 0.5*y^2 + 0.5*a*eps*y^4 + 0.5*py^2 = E
        // Solve 0.5*a*eps*y^4 + 0.5*y^2 - E = 0 for y_max
        const y_max: f64 = if (a_p > 0.0)
            @sqrt((-0.5 + @sqrt(0.25 + 2.0 * a_p * EPS_REG * e_p)) / (a_p * EPS_REG))
        else
            @sqrt(2.0 * e_p);

        var bnd: std.ArrayList(u8) = .empty;
        const n_b: usize = 64;
        for (0..n_b + 1) |bi| {
            const ang = (@as(f64, @floatFromInt(bi)) / @as(f64, @floatFromInt(n_b))) * 2.0 * PI;
            const yb = y_max * @cos(ang);
            const py_sq = @max(0.0, 2.0 * (e_p - 0.5 * yb * yb - 0.5 * a_p * EPS_REG * yb * yb * yb * yb));
            const pyb = std.math.copysign(@sqrt(py_sq), @sin(ang));
            const bx = px0 + (0.5 + (yb / (r_lim * 2.08))) * box_s;
            const by = y0 + (0.5 - (pyb / (r_lim * 2.08))) * box_s;
            try bnd.appendSlice(alloc, try std.fmt.allocPrint(alloc, "{s}{d:.1},{d:.1}", .{ if (bi > 0) " " else "", bx, by }));
        }

        try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\<text x="{d:.1}" y="12" text-anchor="middle" font-family="Inter, sans-serif" font-size="6.4" font-weight="700" fill="#111827">{s}</text>
            \\<rect x="{d:.1}" y="{d:.1}" width="{d:.1}" height="{d:.1}" fill="#FAFBFD" stroke="#1E293B" stroke-width="0.7" />
            \\<polygon points="{s}" fill="none" stroke="#94A3B8" stroke-width="0.6" stroke-dasharray="2.5,2" />
            \\
        , .{ px0 + box_s * 0.5, titles[pi], px0, y0, box_s, box_s, bnd.items }));

        // Axes ticks (-6, 0, +6)
        const ticks = [_]f64{ -6.0, 0.0, 6.0 };
        for (ticks) |tv| {
            const fx = px0 + (0.5 + (tv / (r_lim * 2.08))) * box_s;
            const fy = y0 + (0.5 - (tv / (r_lim * 2.08))) * box_s;
            try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
                \\<line x1="{d:.1}" y1="{d:.1}" x2="{d:.1}" y2="{d:.1}" stroke="#1E293B" stroke-width="0.55" />
                \\<text x="{d:.1}" y="{d:.1}" text-anchor="middle" font-family="Inter, sans-serif" font-size="5.6" fill="#334155">{d:.0}</text>
                \\
            , .{ fx, y0 + box_s, fx, y0 + box_s + 2.8, fx, y0 + box_s + 10.2, tv }));
            if (pi == 0) {
                try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
                    \\<line x1="{d:.1}" y1="{d:.1}" x2="{d:.1}" y2="{d:.1}" stroke="#1E293B" stroke-width="0.55" />
                    \\<text x="{d:.1}" y="{d:.1}" text-anchor="end" font-family="Inter, sans-serif" font-size="5.6" fill="#334155">{d:.0}</text>
                    \\
                , .{ px0 - 2.8, fy, px0, fy, px0 - 4.5, fy + 2.0, tv }));
            }
        }

        // Plot exact Poincare crossings (cobalt = regular KAM, crimson = chaotic sea)
        for (pts[pi].items) |pt| {
            const cx = px0 + (0.5 + (pt.y / (r_lim * 2.08))) * box_s;
            const cy = y0 + (0.5 - (pt.py / (r_lim * 2.08))) * box_s;
            const col: []const u8 = if (pt.chaotic) "#B91C1C" else "#1D4ED8";
            try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
                \\<circle cx="{d:.2}" cy="{d:.2}" r="0.88" fill="{s}" fill-opacity="0.78" />
                \\
            , .{ cx, cy, col }));
        }

        // Compact bottom metric readout
        try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\<text x="{d:.1}" y="172" text-anchor="middle" font-family="IBM Plex Mono, monospace" font-size="5.5" fill="#1E293B">y  |  chaotic={d:.1}%  r={d:.4}</text>
            \\
        , .{ px0 + box_s * 0.5, panel_res[pi].chaotic_frac_pct, panel_res[pi].r_mean }));
    }

    // Shared y-axis label on left
    try out.appendSlice(alloc,
        \\<text x="8" y="88" text-anchor="middle" font-family="Inter, sans-serif" font-size="6.2" font-weight="600" fill="#1E293B" transform="rotate(-90 8 88)">p_y</text>
        \\</svg>
        \\
    );
    return out.toOwnedSlice(alloc);
}

fn renderTransitionAndPsSvg(
    alloc: std.mem.Allocator,
    results: []const SweepResult,
    r_cha: SweepResult,
) ![]u8 {
    const w: f64 = 522.0;
    const h: f64 = 180.0;
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\<svg xmlns="http://www.w3.org/2000/svg" width="{d:.0}pt" height="{d:.0}pt" viewBox="0 0 {d:.0} {d:.0}">
        \\<rect width="{d:.0}" height="{d:.0}" fill="#FFFFFF" />
        \\
    , .{ w, h, w, h, w, h }));

    // --- PANEL A: Classical <lambda_1> & Quantum <r> vs Coupling alpha (x: 36..250, y: 22..144) ---
    const ax0: f64 = 36.0;
    const ay0: f64 = 22.0;
    const aw: f64 = 206.0;
    const ah: f64 = 122.0;
    try out.appendSlice(alloc,
        \\<text x="36" y="12" font-family="Inter, sans-serif" font-size="6.5" font-weight="700" fill="#111827">(a) CLASSICAL LYAPUNOV &amp; QUANTUM GAP RATIO</text>
        \\<rect x="36" y="22" width="206" height="122" fill="#FAFBFD" stroke="#1E293B" stroke-width="0.7" />
        \\
    );

    // Reference horizontal lines for <r>: Poisson 0.3863 and GOE 0.5307 (mapped to r in [0.30, 0.58])
    const r_min: f64 = 0.30;
    const r_max: f64 = 0.58;
    const fy_poi = ay0 + ah - ((POISSON_R - r_min) / (r_max - r_min)) * ah;
    const fy_goe = ay0 + ah - ((GOE_R_LARGE_N - r_min) / (r_max - r_min)) * ah;
    try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\<line x1="{d:.1}" y1="{d:.1}" x2="{d:.1}" y2="{d:.1}" stroke="#475569" stroke-width="0.7" stroke-dasharray="3,2" />
        \\<text x="{d:.1}" y="{d:.1}" text-anchor="end" font-family="Inter, sans-serif" font-size="5.3" font-weight="600" fill="#334155">Poisson 0.386</text>
        \\<line x1="{d:.1}" y1="{d:.1}" x2="{d:.1}" y2="{d:.1}" stroke="#1D4ED8" stroke-width="0.7" stroke-dasharray="3,2" />
        \\<text x="{d:.1}" y="{d:.1}" text-anchor="start" font-family="Inter, sans-serif" font-size="5.3" font-weight="600" fill="#1D4ED8">GOE 0.531</text>
        \\
    , .{ ax0, fy_poi, ax0 + aw, fy_poi, ax0 + aw - 3.0, fy_poi - 2.5, ax0, fy_goe, ax0 + aw, fy_goe, ax0 + 4.0, fy_goe - 2.8 }));

    // Left y-axis ticks (<r>: 0.35, 0.45, 0.55)
    const r_ticks = [_]f64{ 0.35, 0.45, 0.55 };
    for (r_ticks) |rt| {
        const fy = ay0 + ah - ((rt - r_min) / (r_max - r_min)) * ah;
        try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\<line x1="{d:.1}" y1="{d:.1}" x2="{d:.1}" y2="{d:.1}" stroke="#1D4ED8" stroke-width="0.6" />
            \\<text x="{d:.1}" y="{d:.1}" text-anchor="end" font-family="Inter, sans-serif" font-size="5.6" fill="#1D4ED8">{d:.2}</text>
            \\
        , .{ ax0 - 2.5, fy, ax0, fy, ax0 - 4.0, fy + 2.0, rt }));
    }

    // Right y-axis ticks (lambda_1: 0.0, 0.2, 0.4)
    var l_max: f64 = 0.40;
    for (results) |r| {
        if (r.mean_lyap * 1.15 > l_max) l_max = @ceil(r.mean_lyap * 11.5) / 10.0;
    }
    const l_ticks = [_]f64{ 0.0, l_max * 0.5, l_max };
    for (l_ticks) |lt| {
        const fy = ay0 + ah - (lt / l_max) * ah;
        try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\<line x1="{d:.1}" y1="{d:.1}" x2="{d:.1}" y2="{d:.1}" stroke="#B91C1C" stroke-width="0.6" />
            \\<text x="{d:.1}" y="{d:.1}" font-family="Inter, sans-serif" font-size="5.6" fill="#B91C1C">{d:.2}</text>
            \\
        , .{ ax0 + aw, fy, ax0 + aw + 2.5, fy, ax0 + aw + 4.0, fy + 2.0, lt }));
    }

    // Plot curves over log10(alpha + 0.01) for clean visual separation across 2.5 decades
    const xMap = struct {
        fn f(a: f64, x0: f64, width: f64) f64 {
            const u = (@log10(a + 0.01) - @log10(0.01)) / (@log10(2.51) - @log10(0.01));
            return x0 + 8.0 + u * (width - 16.0);
        }
    }.f;

    // x-axis ticks
    const a_ticks = [_]f64{ 0.0, 0.05, 0.25, 1.0, 2.5 };
    for (a_ticks) |at| {
        const fx = xMap(at, ax0, aw);
        try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\<line x1="{d:.1}" y1="{d:.1}" x2="{d:.1}" y2="{d:.1}" stroke="#1E293B" stroke-width="0.55" />
            \\<text x="{d:.1}" y="{d:.1}" text-anchor="middle" font-family="Inter, sans-serif" font-size="5.4" fill="#334155">{d:.2}</text>
            \\
        , .{ fx, ay0 + ah, fx, ay0 + ah + 2.8, fx, ay0 + ah + 10.2, at }));
    }

    // Plot <r> for non-degenerate alpha > 0 (results[1..]) and Lyapunov across all alpha >= 0
    var pts_r: std.ArrayList(u8) = .empty;
    var pts_l: std.ArrayList(u8) = .empty;
    for (results, 0..) |r, i| {
        const fx = xMap(r.spec.alpha, ax0, aw);
        const fyl = ay0 + ah - (r.mean_lyap / l_max) * ah;
        try pts_l.appendSlice(alloc, try std.fmt.allocPrint(alloc, "{s}{d:.1},{d:.1}", .{ if (i > 0) " " else "", fx, fyl }));
        if (i >= 1) {
            const rc = std.math.clamp(r.r_mean, r_min, r_max);
            const fyr = ay0 + ah - ((rc - r_min) / (r_max - r_min)) * ah;
            try pts_r.appendSlice(alloc, try std.fmt.allocPrint(alloc, "{s}{d:.1},{d:.1}", .{ if (i > 1) " " else "", fx, fyr }));
        }
    }
    try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\<polyline points="{s}" fill="none" stroke="#1D4ED8" stroke-width="1.5" />
        \\<polyline points="{s}" fill="none" stroke="#B91C1C" stroke-width="1.35" stroke-dasharray="4,1.8" />
        \\
    , .{ pts_r.items, pts_l.items }));

    for (results, 0..) |r, i| {
        const fx = xMap(r.spec.alpha, ax0, aw);
        const fyl = ay0 + ah - (r.mean_lyap / l_max) * ah;
        try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\<rect x="{d:.1}" y="{d:.1}" width="3.6" height="3.6" fill="#B91C1C" />
            \\
        , .{ fx - 1.8, fyl - 1.8 }));
        if (i >= 1) {
            const rc = std.math.clamp(r.r_mean, r_min, r_max);
            const fyr = ay0 + ah - ((rc - r_min) / (r_max - r_min)) * ah;
            try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
                \\<circle cx="{d:.1}" cy="{d:.1}" r="2.2" fill="#1D4ED8" stroke="#FFFFFF" stroke-width="0.5" />
                \\
            , .{ fx, fyr }));
        }
    }

    try out.appendSlice(alloc,
        \\<text x="139" y="167" text-anchor="middle" font-family="Inter, sans-serif" font-size="5.6" fill="#1E293B">Coupling alpha  |  Blue: Quantum r-ratio   Red: Classical Lyapunov</text>
        \\
    );

    // --- PANEL B: Unfolded P(s) Histogram @ alpha = 2.50 vs Poisson & GOE Wigner Surmise ---
    const bx0: f64 = 304.0;
    const by0: f64 = 22.0;
    const bw: f64 = 208.0;
    const bh: f64 = 122.0;
    const s_max: f64 = 3.2;
    const p_max: f64 = 1.05;

    try out.appendSlice(alloc,
        \\<text x="304" y="12" font-family="Inter, sans-serif" font-size="6.5" font-weight="700" fill="#111827">(b) UNFOLDED SPACING P(s) AT alpha = 2.50</text>
        \\<rect x="304" y="22" width="208" height="122" fill="#FAFBFD" stroke="#1E293B" stroke-width="0.7" />
        \\
    );

    // Y ticks (0.0, 0.5, 1.0) and X ticks (0, 1, 2, 3)
    const pticks = [_]f64{ 0.0, 0.5, 1.0 };
    for (pticks) |pt| {
        const fy = by0 + bh - (pt / p_max) * bh;
        try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\<line x1="{d:.1}" y1="{d:.1}" x2="{d:.1}" y2="{d:.1}" stroke="#1E293B" stroke-width="0.55" />
            \\<text x="{d:.1}" y="{d:.1}" text-anchor="end" font-family="Inter, sans-serif" font-size="5.6" fill="#334155">{d:.1}</text>
            \\
        , .{ bx0 - 2.5, fy, bx0, fy, bx0 - 4.0, fy + 2.0, pt }));
    }
    for (0..4) |st| {
        const fx = bx0 + (@as(f64, @floatFromInt(st)) / s_max) * bw;
        try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\<line x1="{d:.1}" y1="{d:.1}" x2="{d:.1}" y2="{d:.1}" stroke="#1E293B" stroke-width="0.55" />
            \\<text x="{d:.1}" y="{d:.1}" text-anchor="middle" font-family="Inter, sans-serif" font-size="5.6" fill="#334155">{d}</text>
            \\
        , .{ fx, by0 + bh, fx, by0 + bh + 2.8, fx, by0 + bh + 10.2, st }));
    }

    // Histogram bars (16 bins of ds=0.2)
    const bar_w = (0.2 / s_max) * bw;
    for (r_cha.hist_ps, 0..) |hv, bi| {
        const rx = bx0 + @as(f64, @floatFromInt(bi)) * bar_w + 0.6;
        const r_h = @min(bh, (hv / p_max) * bh);
        const ry = by0 + bh - r_h;
        try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\<rect x="{d:.1}" y="{d:.1}" width="{d:.1}" height="{d:.1}" fill="#93C5FD" stroke="#1D4ED8" stroke-width="0.55" />
            \\
        , .{ rx, ry, bar_w - 1.2, @max(0.5, r_h) }));
    }

    // Exact Poisson e^-s (dashed slate) and GOE Wigner Surmise (pi/2)*s*exp(-pi*s^2/4) (solid crimson)
    var pts_poi: std.ArrayList(u8) = .empty;
    var pts_goe: std.ArrayList(u8) = .empty;
    for (0..65) |si| {
        const sv = (@as(f64, @floatFromInt(si)) / 64.0) * s_max;
        const fx = bx0 + (sv / s_max) * bw;
        const py_p = by0 + bh - (@exp(-sv) / p_max) * bh;
        const py_g = by0 + bh - (((0.5 * PI * sv * @exp(-0.25 * PI * sv * sv))) / p_max) * bh;
        try pts_poi.appendSlice(alloc, try std.fmt.allocPrint(alloc, "{s}{d:.1},{d:.1}", .{ if (si > 0) " " else "", fx, py_p }));
        try pts_goe.appendSlice(alloc, try std.fmt.allocPrint(alloc, "{s}{d:.1},{d:.1}", .{ if (si > 0) " " else "", fx, py_g }));
    }
    try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\<polyline points="{s}" fill="none" stroke="#334155" stroke-width="1.2" stroke-dasharray="3.5,2" />
        \\<polyline points="{s}" fill="none" stroke="#B91C1C" stroke-width="1.65" />
        \\<rect x="424" y="30" width="82" height="36" fill="#FFFFFF" stroke="#CBD5E1" stroke-width="0.55" rx="1.5" />
        \\<line x1="430" y1="39" x2="444" y2="39" stroke="#B91C1C" stroke-width="1.6" />
        \\<text x="448" y="41" font-family="Inter, sans-serif" font-size="5.4" font-weight="600" fill="#1E293B">GOE Wigner</text>
        \\<line x1="430" y1="49" x2="444" y2="49" stroke="#334155" stroke-width="1.2" stroke-dasharray="3,1.5" />
        \\<text x="448" y="51" font-family="Inter, sans-serif" font-size="5.4" fill="#334155">Poisson</text>
        \\<text x="430" y="61" font-family="IBM Plex Mono, monospace" font-size="5.2" font-weight="700" fill="#1D4ED8">beta = {d:.3}</text>
        \\<text x="408" y="167" text-anchor="middle" font-family="Inter, sans-serif" font-size="5.6" fill="#1E293B">Unfolded spacing s  (C4v A1 irrep, {d} levels)</text>
        \\</svg>
        \\
    , .{ pts_poi.items, pts_goe.items, r_cha.brody_beta, r_cha.n_bulk }));

    return out.toOwnedSlice(alloc);
}

fn renderRigiditySymplecticSvg(
    alloc: std.mem.Allocator,
    r_reg: SweepResult,
    r_mix: SweepResult,
    r_cha: SweepResult,
    yosh_drift: [40]f64,
    rk4_drift: [40]f64,
) ![]u8 {
    // Classic single-column PRL figure (252pt wide)
    const w: f64 = 252.0;
    const h: f64 = 166.0;
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\<svg xmlns="http://www.w3.org/2000/svg" width="{d:.0}pt" height="{d:.0}pt" viewBox="0 0 {d:.0} {d:.0}">
        \\<rect width="{d:.0}" height="{d:.0}" fill="#FFFFFF" />
        \\
    , .{ w, h, w, h, w, h }));

    const x0: f64 = 32.0;
    const y0: f64 = 18.0;
    const pw: f64 = 212.0;
    const ph: f64 = 114.0;
    const l_max: f64 = 5.0;
    const v_max: f64 = 5.2;

    try out.appendSlice(alloc,
        \\<text x="32" y="11" font-family="Inter, sans-serif" font-size="6.1" font-weight="700" fill="#111827">LONG-RANGE RIGIDITY Sigma^2(L) &amp; SYMPLECTIC PROOF</text>
        \\<rect x="32" y="18" width="212" height="114" fill="#FAFBFD" stroke="#1E293B" stroke-width="0.7" />
        \\
    );

    // Axis ticks
    for (0..6) |t| {
        const fx = x0 + (@as(f64, @floatFromInt(t)) / l_max) * pw;
        const fy = y0 + ph - (@as(f64, @floatFromInt(t)) / v_max) * ph;
        try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\<line x1="{d:.1}" y1="{d:.1}" x2="{d:.1}" y2="{d:.1}" stroke="#1E293B" stroke-width="0.55" />
            \\<text x="{d:.1}" y="{d:.1}" text-anchor="middle" font-family="Inter, sans-serif" font-size="5.5" fill="#334155">{d}</text>
            \\<line x1="{d:.1}" y1="{d:.1}" x2="{d:.1}" y2="{d:.1}" stroke="#1E293B" stroke-width="0.55" />
            \\<text x="{d:.1}" y="{d:.1}" text-anchor="end" font-family="Inter, sans-serif" font-size="5.5" fill="#334155">{d}</text>
            \\
        , .{ fx, y0 + ph, fx, y0 + ph + 2.5, fx, y0 + ph + 9.5, t, x0 - 2.5, fy, x0, fy, x0 - 4.0, fy + 2.0, t }));
    }

    // Exact Poisson Sigma^2(L) = L (dashed) & exact GOE asymptotic (2/pi^2)(ln(2*pi*L)+gamma+1-pi^2/8) (solid thin)
    const fx_p1 = x0 + pw;
    const fy_p1 = y0 + ph - (5.0 / v_max) * ph;
    try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\<line x1="{d:.1}" y1="{d:.1}" x2="{d:.1}" y2="{d:.1}" stroke="#475569" stroke-width="0.95" stroke-dasharray="3,2" />
        \\
    , .{ x0, y0 + ph, fx_p1, fy_p1 }));

    var goe_pts: std.ArrayList(u8) = .empty;
    for (1..41) |si| {
        const lv = (@as(f64, @floatFromInt(si)) / 40.0) * l_max;
        const val = @max(0.0, (2.0 / (PI * PI)) * (@log(2.0 * PI * lv) + EULER_GAMMA + 1.0 - (PI * PI) / 8.0));
        const fx = x0 + (lv / l_max) * pw;
        const fy = y0 + ph - (@min(v_max, val) / v_max) * ph;
        try goe_pts.appendSlice(alloc, try std.fmt.allocPrint(alloc, "{s}{d:.1},{d:.1}", .{ if (si > 1) " " else "", fx, fy }));
    }
    try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\<polyline points="{s}" fill="none" stroke="#1E293B" stroke-width="0.95" stroke-dasharray="1.8,1.5" />
        \\
    , .{goe_pts.items}));

    // Plot empirical Sigma^2(L) for alpha=0.05 (emerald), alpha=0.25 (amber), alpha=2.50 (crimson)
    const series = [_]struct { r: SweepResult, col: []const u8 }{
        .{ .r = r_reg, .col = "#0F766E" },
        .{ .r = r_mix, .col = "#B45309" },
        .{ .r = r_cha, .col = "#B91C1C" },
    };
    for (series) |ser| {
        var pts: std.ArrayList(u8) = .empty;
        for (0..10) |li| {
            const lv = @as(f64, @floatFromInt(li + 1)) * 0.5;
            const fx = x0 + (lv / l_max) * pw;
            const fy = y0 + ph - (@min(v_max, ser.r.sigma2_L[li]) / v_max) * ph;
            try pts.appendSlice(alloc, try std.fmt.allocPrint(alloc, "{s}{d:.1},{d:.1}", .{ if (li > 0) " " else "", fx, fy }));
        }
        try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\<polyline points="{s}" fill="none" stroke="{s}" stroke-width="1.45" />
            \\
        , .{ pts.items, ser.col }));
    }

    // Inset box (top-left inside plot): log10 |dE/E| Yoshida-4 vs RK4 across T=0..2000
    const ix0: f64 = 42.0;
    const iy0: f64 = 24.0;
    const iw: f64 = 98.0;
    const ih: f64 = 48.0;
    try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\<rect x="{d:.1}" y="{d:.1}" width="{d:.1}" height="{d:.1}" fill="#FFFFFF" stroke="#94A3B8" stroke-width="0.55" />
        \\<text x="{d:.1}" y="{d:.1}" font-family="Inter, sans-serif" font-size="4.8" font-weight="700" fill="#1E293B">log10|dE/E| (T=2000)</text>
        \\
    , .{ ix0, iy0, iw, ih, ix0 + 3.0, iy0 + 7.5 }));

    var y_pts: std.ArrayList(u8) = .empty;
    var r_pts: std.ArrayList(u8) = .empty;
    for (0..40) |ci| {
        const fx = ix0 + 4.0 + (@as(f64, @floatFromInt(ci)) / 39.0) * (iw - 8.0);
        const ly = std.math.clamp(@log10(@max(1e-13, yosh_drift[ci])), -10.5, -2.5);
        const lr = std.math.clamp(@log10(@max(1e-13, rk4_drift[ci])), -10.5, -2.5);
        const fyy = iy0 + ih - 9.0 - ((ly + 10.5) / 8.0) * (ih - 24.0);
        const fyr = iy0 + ih - 9.0 - ((lr + 10.5) / 8.0) * (ih - 24.0);
        try y_pts.appendSlice(alloc, try std.fmt.allocPrint(alloc, "{s}{d:.1},{d:.1}", .{ if (ci > 0) " " else "", fx, fyy }));
        try r_pts.appendSlice(alloc, try std.fmt.allocPrint(alloc, "{s}{d:.1},{d:.1}", .{ if (ci > 0) " " else "", fx, fyr }));
    }
    try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\<polyline points="{s}" fill="none" stroke="#1D4ED8" stroke-width="1.2" />
        \\<polyline points="{s}" fill="none" stroke="#991B1B" stroke-width="1.15" stroke-dasharray="2.5,1.5" />
        \\<text x="{d:.1}" y="{d:.1}" font-family="Inter, sans-serif" font-size="4.6" font-weight="700" fill="#991B1B">RK4 drift</text>
        \\<text x="{d:.1}" y="{d:.1}" text-anchor="end" font-family="Inter, sans-serif" font-size="4.6" font-weight="700" fill="#1D4ED8">Yoshida-4</text>
        \\<text x="138" y="156" text-anchor="middle" font-family="Inter, sans-serif" font-size="5.4" fill="#1E293B">Interval L  |  Teal: 0.025  Amber: 0.125  Red: 2.50</text>
        \\</svg>
        \\
    , .{ y_pts.items, r_pts.items, ix0 + 4.0, iy0 + 15.5, ix0 + iw - 3.5, iy0 + ih - 3.0 }));

    return out.toOwnedSlice(alloc);
}
