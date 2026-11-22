//! Pure Zig 0.17.0 Zero-Python Operations Research Compiler, PFSP Solver,
//! SHA-256 Sealer & Vector SVG Engine for the Elsevier Computers & Industrial
//! Engineering (CAIE) Reference Paper.
//!
//! Benchmarks all 31 canonical OR-Library Permutation Flowshop Scheduling
//! (F_m | prmu | C_max) instances from Carlier (1978), Heller (1960), and
//! Reeves (1995) (`data/raw/flowshop1.txt`) using:
//!   1. CDS (Campbell-Dudek-Smith, 1970)
//!   2. NEH (Nawaz-Enscore-Ham, 1983) with Taillard O(nm) acceleration
//!   3. NEH + First-Improvement Insertion Local Search (NEH+LS)
//!   4. Iterated Greedy (Ruiz & Stutzle, 2007) — 10 deterministic seeds x 400 iters
//!   5. Live destruction-size sensitivity ablation (d in {2, 4, 6})
//!
//! Compile & run:
//!   zig run -O ReleaseSafe scripts/pipeline.zig -- <demo_dir>

const std = @import("std");

const MAX_N = 100;
const MAX_M = 20;
const IG_SEEDS: usize = 10;
const IG_ITERS: usize = 400;
const ABL_SEEDS: usize = 5;
const ABL_ITERS: usize = 300;
const CONV_POINTS = [_]usize{ 0, 10, 25, 50, 100, 150, 200, 300, 400 };

const Instance = struct {
    name: []const u8,
    group_idx: usize, // 0=Carlier, 1=Heller, 2=Reeves20, 3=Reeves30, 4=Reeves50-75
    n: usize,
    m: usize,
    p: [MAX_N][MAX_M]i64, // p[job][machine]
    lb: i64,
    sum_p: i64,
};

const BenchResult = struct {
    name: []const u8,
    group_idx: usize,
    n: usize,
    m: usize,
    lb: i64,
    cds: i64,
    neh: i64,
    neh_ls: i64,
    ig_best: i64,
    ig_mean: f64,
    ig_sd: f64,
    imp_vs_neh_pct: f64,
    gap_cds_lb_pct: f64,
    gap_neh_lb_pct: f64,
    gap_neh_ls_lb_pct: f64,
    gap_ig_best_lb_pct: f64,
    gap_ig_mean_lb_pct: f64,
    best_perm: [MAX_N]usize,
    conv_gap_lb: [CONV_POINTS.len]f64,
    abl_d2_gap: f64,
    abl_d4_gap: f64,
    abl_d6_gap: f64,
};

const LedgerEntry = struct {
    metric_id: []const u8,
    value: f64,
    is_int: bool,
    unit: []const u8,
    source_document: []const u8,
    source_locator: []const u8,
    raw_file_sha256: [64]u8,
};

const Rng = struct {
    state: u64,
    fn init(seed: u64) Rng {
        return .{ .state = seed ^ 0x9E3779B97F4A7C15 };
    }
    fn nextU64(self: *Rng) u64 {
        self.state +%= 0x9E3779B97F4A7C15;
        var z = self.state;
        z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
        z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
        return z ^ (z >> 31);
    }
    fn nextIndex(self: *Rng, bound: usize) usize {
        return @intCast(self.nextU64() % @as(u64, @intCast(bound)));
    }
    fn nextF64(self: *Rng) f64 {
        return @as(f64, @floatFromInt(self.nextU64() >> 11)) * (1.0 / 9007199254740992.0);
    }
};

const TaillardBuf = struct {
    e: [MAX_N + 1][MAX_M]i64 = undefined,
    q: [MAX_N + 1][MAX_M]i64 = undefined,
    f: [MAX_M]i64 = undefined,
};

fn sha256Hex(bytes: []const u8) [64]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    const hex = "0123456789abcdef";
    var out: [64]u8 = undefined;
    for (digest, 0..) |b, i| {
        out[i * 2] = hex[b >> 4];
        out[i * 2 + 1] = hex[b & 0x0f];
    }
    return out;
}

fn round2(v: f64) f64 {
    return @round(v * 100.0) / 100.0;
}

fn addMetric(
    alloc: std.mem.Allocator,
    ledger: *std.ArrayList(LedgerEntry),
    id: []const u8,
    val: f64,
    is_int: bool,
    unit: []const u8,
    src_doc: []const u8,
    locator: []const u8,
    sha: [64]u8,
) !void {
    try ledger.append(alloc, .{
        .metric_id = id,
        .value = if (is_int) @round(val) else round2(val),
        .is_int = is_int,
        .unit = unit,
        .source_document = src_doc,
        .source_locator = locator,
        .raw_file_sha256 = sha,
    });
}

fn evalMakespanDirect(inst: *const Instance, perm: []const usize) i64 {
    var comp: [MAX_M]i64 = @splat(0);
    for (perm) |job| {
        comp[0] += inst.p[job][0];
        var j: usize = 1;
        while (j < inst.m) : (j += 1) {
            comp[j] = @max(comp[j], comp[j - 1]) + inst.p[job][j];
        }
    }
    return comp[inst.m - 1];
}

fn verifyPermutation(inst: *const Instance, perm: []const usize, claimed_cmax: i64) !void {
    if (perm.len != inst.n) return error.InvalidPermutationLength;
    var seen: [MAX_N]bool = @splat(false);
    for (perm) |j| {
        if (j >= inst.n or seen[j]) return error.InvalidPermutationBijection;
        seen[j] = true;
    }
    const recomputed = evalMakespanDirect(inst, perm);
    if (recomputed != claimed_cmax) return error.TaillardMakespanMismatch;
    if (recomputed < inst.lb) return error.LowerBoundViolation;
}

fn computeLowerBound(inst: *const Instance) i64 {
    var best_lb: i64 = 0;
    // Job lower bound
    for (0..inst.n) |i| {
        var s: i64 = 0;
        for (0..inst.m) |k| s += inst.p[i][k];
        if (s > best_lb) best_lb = s;
    }
    // Machine lower bound (Ignall-Schrage / Taillard)
    for (0..inst.m) |k| {
        var min_head: i64 = std.math.maxInt(i64);
        var min_tail: i64 = std.math.maxInt(i64);
        var sum_k: i64 = 0;
        for (0..inst.n) |i| {
            var h: i64 = 0;
            for (0..k) |r| h += inst.p[i][r];
            var t: i64 = 0;
            for ((k + 1)..inst.m) |r| t += inst.p[i][r];
            if (h < min_head) min_head = h;
            if (t < min_tail) min_tail = t;
            sum_k += inst.p[i][k];
        }
        const lb_k = min_head + sum_k + min_tail;
        if (lb_k > best_lb) best_lb = lb_k;
    }
    return best_lb;
}

/// Taillard O(k*m) exact evaluation of inserting job `u` into all k+1 positions of `seq[0..k]`.
fn bestInsertionTaillard(
    inst: *const Instance,
    seq: []const usize,
    u: usize,
    buf: *TaillardBuf,
) struct { pos: usize, cmax: i64 } {
    const k = seq.len;
    const m = inst.m;
    if (k == 0) {
        var s: i64 = 0;
        for (0..m) |j| s += inst.p[u][j];
        return .{ .pos = 0, .cmax = s };
    }

    // Forward heads e[0..k-1]
    for (0..k) |i| {
        const job = seq[i];
        buf.e[i][0] = (if (i > 0) buf.e[i - 1][0] else 0) + inst.p[job][0];
        var j: usize = 1;
        while (j < m) : (j += 1) {
            const prev_job = if (i > 0) buf.e[i - 1][j] else 0;
            buf.e[i][j] = @max(prev_job, buf.e[i][j - 1]) + inst.p[job][j];
        }
    }

    // Backward tails q[0..k-1]
    var bi: usize = k;
    while (bi > 0) {
        bi -= 1;
        const job = seq[bi];
        buf.q[bi][m - 1] = (if (bi + 1 < k) buf.q[bi + 1][m - 1] else 0) + inst.p[job][m - 1];
        var bj: usize = m - 1;
        while (bj > 0) {
            bj -= 1;
            const next_job = if (bi + 1 < k) buf.q[bi + 1][bj] else 0;
            buf.q[bi][bj] = @max(next_job, buf.q[bi][bj + 1]) + inst.p[job][bj];
        }
    }

    var best_pos: usize = 0;
    var best_cmax: i64 = std.math.maxInt(i64);

    for (0..(k + 1)) |pos| {
        var cmax: i64 = 0;
        for (0..m) |j| {
            const head = if (pos > 0) buf.e[pos - 1][j] else 0;
            const prev_m = if (j > 0) buf.f[j - 1] else 0;
            buf.f[j] = @max(head, prev_m) + inst.p[u][j];
            const tail = if (pos < k) buf.q[pos][j] else 0;
            const total = buf.f[j] + tail;
            if (total > cmax) cmax = total;
        }
        if (cmax < best_cmax) {
            best_cmax = cmax;
            best_pos = pos;
        }
    }
    return .{ .pos = best_pos, .cmax = best_cmax };
}

fn insertAt(seq: *[MAX_N]usize, len: *usize, pos: usize, val: usize) void {
    var i: usize = len.*;
    while (i > pos) : (i -= 1) {
        seq[i] = seq[i - 1];
    }
    seq[pos] = val;
    len.* += 1;
}

fn removeAt(seq: *[MAX_N]usize, len: *usize, pos: usize) usize {
    const val = seq[pos];
    var i: usize = pos;
    while (i + 1 < len.*) : (i += 1) {
        seq[i] = seq[i + 1];
    }
    len.* -= 1;
    return val;
}

/// 1. Campbell-Dudek-Smith (CDS, 1970) heuristic using m-1 Johnson-rule reductions.
fn solveCDS(inst: *const Instance, out_perm: *[MAX_N]usize) i64 {
    var best_cmax: i64 = std.math.maxInt(i64);
    var cand: [MAX_N]usize = undefined;
    var left_jobs: [MAX_N]usize = undefined;
    var right_jobs: [MAX_N]usize = undefined;
    var a_val: [MAX_N]i64 = undefined;
    var b_val: [MAX_N]i64 = undefined;

    for (1..inst.m) |l| {
        var n_left: usize = 0;
        var n_right: usize = 0;
        for (0..inst.n) |i| {
            var sa: i64 = 0;
            var sb: i64 = 0;
            for (0..l) |r| sa += inst.p[i][r];
            for ((inst.m - l)..inst.m) |r| sb += inst.p[i][r];
            a_val[i] = sa;
            b_val[i] = sb;
            if (sa <= sb) {
                left_jobs[n_left] = i;
                n_left += 1;
            } else {
                right_jobs[n_right] = i;
                n_right += 1;
            }
        }
        // Sort left_jobs by ascending a_val
        for (0..n_left) |i| {
            var j = i + 1;
            while (j < n_left) : (j += 1) {
                if (a_val[left_jobs[j]] < a_val[left_jobs[i]]) {
                    const tmp = left_jobs[i];
                    left_jobs[i] = left_jobs[j];
                    left_jobs[j] = tmp;
                }
            }
        }
        // Sort right_jobs by descending b_val
        for (0..n_right) |i| {
            var j = i + 1;
            while (j < n_right) : (j += 1) {
                if (b_val[right_jobs[j]] > b_val[right_jobs[i]]) {
                    const tmp = right_jobs[i];
                    right_jobs[i] = right_jobs[j];
                    right_jobs[j] = tmp;
                }
            }
        }
        for (0..n_left) |i| cand[i] = left_jobs[i];
        for (0..n_right) |i| cand[n_left + i] = right_jobs[i];
        const c = evalMakespanDirect(inst, cand[0..inst.n]);
        if (c < best_cmax) {
            best_cmax = c;
            @memcpy(out_perm[0..inst.n], cand[0..inst.n]);
        }
    }
    return best_cmax;
}

/// 2. Nawaz-Enscore-Ham (NEH, 1983) with Taillard O(nm) acceleration.
fn solveNEH(inst: *const Instance, out_perm: *[MAX_N]usize, buf: *TaillardBuf) i64 {
    var order: [MAX_N]usize = undefined;
    var totals: [MAX_N]i64 = undefined;
    for (0..inst.n) |i| {
        order[i] = i;
        var s: i64 = 0;
        for (0..inst.m) |k| s += inst.p[i][k];
        totals[i] = s;
    }
    // Sort jobs descending by total processing time (tie-break by index)
    for (0..inst.n) |i| {
        var j = i + 1;
        while (j < inst.n) : (j += 1) {
            if (totals[order[j]] > totals[order[i]] or
                (totals[order[j]] == totals[order[i]] and order[j] < order[i]))
            {
                const tmp = order[i];
                order[i] = order[j];
                order[j] = tmp;
            }
        }
    }

    var len: usize = 0;
    var cur_cmax: i64 = 0;
    for (0..inst.n) |idx| {
        const u = order[idx];
        const res = bestInsertionTaillard(inst, out_perm[0..len], u, buf);
        insertAt(out_perm, &len, res.pos, u);
        cur_cmax = res.cmax;
    }
    return cur_cmax;
}

/// 3. Taillard-accelerated first-improvement insertion local search.
fn insertionLocalSearch(
    inst: *const Instance,
    perm: *[MAX_N]usize,
    cmax_in: i64,
    buf: *TaillardBuf,
    rng: ?*Rng,
) i64 {
    var cmax = cmax_in;
    var test_order: [MAX_N]usize = undefined;
    for (0..inst.n) |i| test_order[i] = perm[i];

    var improved = true;
    var passes: usize = 0;
    while (improved and passes < 24) {
        improved = false;
        passes += 1;
        if (rng) |r| {
            // Fisher-Yates shuffle of job-probe order
            var i: usize = inst.n;
            while (i > 1) {
                i -= 1;
                const j = r.nextIndex(i + 1);
                const tmp = test_order[i];
                test_order[i] = test_order[j];
                test_order[j] = tmp;
            }
        }

        for (0..inst.n) |ti| {
            const job = test_order[ti];
            var cur_pos: usize = 0;
            for (0..inst.n) |k| {
                if (perm[k] == job) {
                    cur_pos = k;
                    break;
                }
            }
            var len: usize = inst.n;
            _ = removeAt(perm, &len, cur_pos);
            const res = bestInsertionTaillard(inst, perm[0..len], job, buf);
            if (res.cmax < cmax) {
                insertAt(perm, &len, res.pos, job);
                cmax = res.cmax;
                improved = true;
            } else {
                insertAt(perm, &len, cur_pos, job);
            }
        }
    }
    return cmax;
}

/// 4. Iterated Greedy (Ruiz & Stutzle, 2007) with Taillard acceleration + Boltzmann acceptance.
fn solveIG(
    inst: *const Instance,
    init_perm: *const [MAX_N]usize,
    init_cmax: i64,
    d_param: usize,
    iters: usize,
    seed: u64,
    buf: *TaillardBuf,
    best_out: *[MAX_N]usize,
    conv_out: ?*[CONV_POINTS.len]i64,
) i64 {
    const d = @min(d_param, inst.n - 1);
    var rng = Rng.init(seed);
    var cur: [MAX_N]usize = undefined;
    @memcpy(cur[0..inst.n], init_perm[0..inst.n]);
    var cur_cmax = init_cmax;

    @memcpy(best_out[0..inst.n], init_perm[0..inst.n]);
    var best_cmax = init_cmax;

    // Ruiz & Stutzle (2007) temperature: T = tau * sum(p) / (10 * n * m), tau = 0.4
    const temp = 0.4 * @as(f64, @floatFromInt(inst.sum_p)) / @as(f64, @floatFromInt(10 * inst.n * inst.m));

    var next_cp: usize = 0;
    if (conv_out) |co| {
        co[0] = best_cmax;
        next_cp = 1;
    }

    var cand: [MAX_N]usize = undefined;
    var removed: [16]usize = undefined;

    for (1..(iters + 1)) |it| {
        @memcpy(cand[0..inst.n], cur[0..inst.n]);
        var len: usize = inst.n;

        // Destruction phase: remove d distinct jobs uniformly
        for (0..d) |r| {
            const idx = rng.nextIndex(len);
            removed[r] = removeAt(&cand, &len, idx);
        }

        // Construction phase: greedy Taillard insertion
        var cand_cmax: i64 = 0;
        for (0..d) |r| {
            const ins = bestInsertionTaillard(inst, cand[0..len], removed[r], buf);
            insertAt(&cand, &len, ins.pos, removed[r]);
            cand_cmax = ins.cmax;
        }

        // Local search phase
        cand_cmax = insertionLocalSearch(inst, &cand, cand_cmax, buf, &rng);

        // Acceptance criterion (Boltzmann Metropolis)
        if (cand_cmax < cur_cmax) {
            @memcpy(cur[0..inst.n], cand[0..inst.n]);
            cur_cmax = cand_cmax;
            if (cur_cmax < best_cmax) {
                best_cmax = cur_cmax;
                @memcpy(best_out[0..inst.n], cur[0..inst.n]);
            }
        } else if (cand_cmax == cur_cmax) {
            if (rng.nextF64() < 0.5) {
                @memcpy(cur[0..inst.n], cand[0..inst.n]);
            }
        } else if (temp > 1e-9) {
            const diff = @as(f64, @floatFromInt(cand_cmax - cur_cmax));
            const prob = @exp(-diff / temp);
            if (rng.nextF64() < prob) {
                @memcpy(cur[0..inst.n], cand[0..inst.n]);
                cur_cmax = cand_cmax;
            }
        }

        if (conv_out) |co| {
            if (next_cp < CONV_POINTS.len and it == CONV_POINTS[next_cp]) {
                co[next_cp] = best_cmax;
                next_cp += 1;
            }
        }
    }
    return best_cmax;
}

fn parseInstances(alloc: std.mem.Allocator, raw: []const u8) ![]Instance {
    var list: std.ArrayList(Instance) = .empty;
    var lines = std.mem.splitScalar(u8, raw, '\n');

    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (!std.mem.startsWith(u8, line, "instance ")) continue;
        const name = try alloc.dupe(u8, std.mem.trim(u8, line["instance ".len..], " \t\r"));

        // Skip separator lines until description line, then dims line
        var dims_line: []const u8 = "";
        while (lines.next()) |nxt_raw| {
            const nxt = std.mem.trim(u8, nxt_raw, " \t\r");
            if (nxt.len == 0 or nxt[0] == '+') continue;
            // First non-empty non-'+' line is description; next non-empty is "n m"
            while (lines.next()) |d_raw| {
                const d_tr = std.mem.trim(u8, d_raw, " \t\r");
                if (d_tr.len == 0) continue;
                dims_line = d_tr;
                break;
            }
            break;
        }

        var d_tok = std.mem.tokenizeAny(u8, dims_line, " \t");
        const n = try std.fmt.parseInt(usize, d_tok.next() orelse return error.MissingN, 10);
        const m = try std.fmt.parseInt(usize, d_tok.next() orelse return error.MissingM, 10);
        if (n == 0 or n > MAX_N or m == 0 or m > MAX_M) return error.DimensionsOutOfBounds;

        var inst = Instance{
            .name = name,
            .group_idx = 0,
            .n = n,
            .m = m,
            .p = undefined,
            .lb = 0,
            .sum_p = 0,
        };
        if (std.mem.startsWith(u8, name, "car")) {
            inst.group_idx = 0;
        } else if (std.mem.startsWith(u8, name, "hel")) {
            inst.group_idx = 1;
        } else if (n == 20) {
            inst.group_idx = 2;
        } else if (n == 30) {
            inst.group_idx = 3;
        } else {
            inst.group_idx = 4;
        }

        var job_idx: usize = 0;
        while (job_idx < n) {
            const j_raw = lines.next() orelse return error.UnexpectedEofInJobs;
            const j_tr = std.mem.trim(u8, j_raw, " \t\r");
            if (j_tr.len == 0) continue;
            var tok = std.mem.tokenizeAny(u8, j_tr, " \t");
            for (0..m) |expected_m| {
                const mid = try std.fmt.parseInt(usize, tok.next() orelse return error.MissingMachineId, 10);
                const pt = try std.fmt.parseInt(i64, tok.next() orelse return error.MissingProcTime, 10);
                if (mid != expected_m or pt < 0) return error.InvalidJobMatrixEntry;
                inst.p[job_idx][mid] = pt;
                inst.sum_p += pt;
            }
            job_idx += 1;
        }
        inst.lb = computeLowerBound(&inst);
        try list.append(alloc, inst);
    }
    return list.toOwnedSlice(alloc);
}

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(alloc);
    const demo_dir: []const u8 = if (args.len >= 2) args[1] else ".";

    const raw_path = try std.fmt.allocPrint(alloc, "{s}/data/raw/flowshop1.txt", .{demo_dir});
    const raw_bytes = try std.Io.Dir.cwd().readFileAlloc(io, raw_path, alloc, .unlimited);
    const raw_sha = sha256Hex(raw_bytes);

    // Seal data/manifest.sha256
    const manifest_data = try std.fmt.allocPrint(alloc, "{s}  data/raw/flowshop1.txt\n", .{raw_sha[0..64]});
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = try std.fmt.allocPrint(alloc, "{s}/data/manifest.sha256", .{demo_dir}),
        .data = manifest_data,
    });

    const instances = try parseInstances(alloc, raw_bytes);
    if (instances.len != 31) return error.Expected31OrLibraryInstances;

    var buf: TaillardBuf = .{};
    var results = try alloc.alloc(BenchResult, instances.len);

    var car1_inst_idx: usize = 0;
    var sum_gap_cds: f64 = 0;
    var sum_gap_neh: f64 = 0;
    var sum_gap_neh_ls: f64 = 0;
    var sum_gap_ig_best: f64 = 0;
    var sum_gap_ig_mean: f64 = 0;
    var sum_imp_vs_neh: f64 = 0;
    var sum_imp_vs_cds: f64 = 0;
    var ig_strict_wins_neh: i64 = 0;
    var ig_ties_neh: i64 = 0;
    var ig_hits_lb: i64 = 0;
    var sum_abl_d2: f64 = 0;
    var sum_abl_d4: f64 = 0;
    var sum_abl_d6: f64 = 0;

    var grp_cnt: [5]f64 = @splat(0);
    var grp_cds: [5]f64 = @splat(0);
    var grp_neh: [5]f64 = @splat(0);
    var grp_nls: [5]f64 = @splat(0);
    var grp_igb: [5]f64 = @splat(0);

    for (instances, 0..) |*inst, idx| {
        if (std.mem.eql(u8, inst.name, "car1")) car1_inst_idx = idx;

        var perm_cds: [MAX_N]usize = undefined;
        const c_cds = solveCDS(inst, &perm_cds);
        try verifyPermutation(inst, perm_cds[0..inst.n], c_cds);

        var perm_neh: [MAX_N]usize = undefined;
        const c_neh = solveNEH(inst, &perm_neh, &buf);
        try verifyPermutation(inst, perm_neh[0..inst.n], c_neh);

        var perm_nls: [MAX_N]usize = undefined;
        @memcpy(perm_nls[0..inst.n], perm_neh[0..inst.n]);
        const c_nls = insertionLocalSearch(inst, &perm_nls, c_neh, &buf, null);
        try verifyPermutation(inst, perm_nls[0..inst.n], c_nls);

        // 10 deterministic IG seeds (d=4, 400 iters)
        var ig_best: i64 = std.math.maxInt(i64);
        var best_perm: [MAX_N]usize = undefined;
        var seed_vals: [IG_SEEDS]f64 = undefined;
        var conv_sum: [CONV_POINTS.len]f64 = @splat(0);

        for (0..IG_SEEDS) |s| {
            var tmp_perm: [MAX_N]usize = undefined;
            var cp_vals: [CONV_POINTS.len]i64 = undefined;
            const seed_u64 = @as(u64, @intCast((idx + 1) * 1009 + (s + 1) * 7919));
            const c_ig = solveIG(inst, &perm_nls, c_nls, 4, IG_ITERS, seed_u64, &buf, &tmp_perm, &cp_vals);
            try verifyPermutation(inst, tmp_perm[0..inst.n], c_ig);
            if (c_ig > c_nls) return error.IgMonotonicityViolated;
            seed_vals[s] = @floatFromInt(c_ig);
            for (0..CONV_POINTS.len) |ci| {
                const g_lb = (@as(f64, @floatFromInt(cp_vals[ci] - inst.lb)) / @as(f64, @floatFromInt(inst.lb))) * 100.0;
                conv_sum[ci] += g_lb;
            }
            if (c_ig < ig_best) {
                ig_best = c_ig;
                @memcpy(best_perm[0..inst.n], tmp_perm[0..inst.n]);
            }
        }

        var mean_ig: f64 = 0;
        for (seed_vals) |v| mean_ig += v;
        mean_ig /= @as(f64, @floatFromInt(IG_SEEDS));

        var var_ig: f64 = 0;
        for (seed_vals) |v| {
            const df = v - mean_ig;
            var_ig += df * df;
        }
        const sd_ig = @sqrt(var_ig / @as(f64, @floatFromInt(IG_SEEDS)));

        // Live destruction-size ablation: d in {2, 4, 6} (5 seeds x 300 iters)
        const d_vals = [_]usize{ 2, 4, 6 };
        var abl_gaps: [3]f64 = undefined;
        for (d_vals, 0..) |dv, di| {
            var s_gap: f64 = 0;
            for (0..ABL_SEEDS) |s| {
                var tmp_p: [MAX_N]usize = undefined;
                const seed_a = @as(u64, @intCast((idx + 1) * 4099 + (dv * 97) + (s + 1) * 3571));
                const c_a = solveIG(inst, &perm_nls, c_nls, dv, ABL_ITERS, seed_a, &buf, &tmp_p, null);
                try verifyPermutation(inst, tmp_p[0..inst.n], c_a);
                s_gap += (@as(f64, @floatFromInt(c_a - inst.lb)) / @as(f64, @floatFromInt(inst.lb))) * 100.0;
            }
            abl_gaps[di] = s_gap / @as(f64, @floatFromInt(ABL_SEEDS));
        }

        const lb_f = @as(f64, @floatFromInt(inst.lb));
        const gap_cds = (@as(f64, @floatFromInt(c_cds - inst.lb)) / lb_f) * 100.0;
        const gap_neh = (@as(f64, @floatFromInt(c_neh - inst.lb)) / lb_f) * 100.0;
        const gap_nls = (@as(f64, @floatFromInt(c_nls - inst.lb)) / lb_f) * 100.0;
        const gap_igb = (@as(f64, @floatFromInt(ig_best - inst.lb)) / lb_f) * 100.0;
        const gap_igm = ((mean_ig - lb_f) / lb_f) * 100.0;
        const imp_neh = (@as(f64, @floatFromInt(c_neh - ig_best)) / @as(f64, @floatFromInt(c_neh))) * 100.0;
        const imp_cds = (@as(f64, @floatFromInt(c_cds - ig_best)) / @as(f64, @floatFromInt(c_cds))) * 100.0;

        var conv_avg: [CONV_POINTS.len]f64 = undefined;
        for (0..CONV_POINTS.len) |ci| conv_avg[ci] = round2(conv_sum[ci] / @as(f64, @floatFromInt(IG_SEEDS)));

        results[idx] = .{
            .name = inst.name,
            .group_idx = inst.group_idx,
            .n = inst.n,
            .m = inst.m,
            .lb = inst.lb,
            .cds = c_cds,
            .neh = c_neh,
            .neh_ls = c_nls,
            .ig_best = ig_best,
            .ig_mean = mean_ig,
            .ig_sd = sd_ig,
            .imp_vs_neh_pct = imp_neh,
            .gap_cds_lb_pct = gap_cds,
            .gap_neh_lb_pct = gap_neh,
            .gap_neh_ls_lb_pct = gap_nls,
            .gap_ig_best_lb_pct = gap_igb,
            .gap_ig_mean_lb_pct = gap_igm,
            .best_perm = best_perm,
            .conv_gap_lb = conv_avg,
            .abl_d2_gap = abl_gaps[0],
            .abl_d4_gap = abl_gaps[1],
            .abl_d6_gap = abl_gaps[2],
        };

        sum_gap_cds += gap_cds;
        sum_gap_neh += gap_neh;
        sum_gap_neh_ls += gap_nls;
        sum_gap_ig_best += gap_igb;
        sum_gap_ig_mean += gap_igm;
        sum_imp_vs_neh += imp_neh;
        sum_imp_vs_cds += imp_cds;
        if (ig_best < c_neh) ig_strict_wins_neh += 1 else ig_ties_neh += 1;
        if (ig_best == inst.lb) ig_hits_lb += 1;
        sum_abl_d2 += abl_gaps[0];
        sum_abl_d4 += abl_gaps[1];
        sum_abl_d6 += abl_gaps[2];

        const g = inst.group_idx;
        grp_cnt[g] += 1.0;
        grp_cds[g] += gap_cds;
        grp_neh[g] += gap_neh;
        grp_nls[g] += gap_nls;
        grp_igb[g] += gap_igb;
    }

    const n_inst_f = @as(f64, @floatFromInt(instances.len));
    const mean_gap_cds = round2(sum_gap_cds / n_inst_f);
    const mean_gap_neh = round2(sum_gap_neh / n_inst_f);
    const mean_gap_nls = round2(sum_gap_neh_ls / n_inst_f);
    const mean_gap_igb = round2(sum_gap_ig_best / n_inst_f);
    const mean_gap_igm = round2(sum_gap_ig_mean / n_inst_f);
    const mean_imp_neh = round2(sum_imp_vs_neh / n_inst_f);
    const mean_imp_cds = round2(sum_imp_vs_cds / n_inst_f);
    const mean_abl_d2 = round2(sum_abl_d2 / n_inst_f);
    const mean_abl_d4 = round2(sum_abl_d4 / n_inst_f);
    const mean_abl_d6 = round2(sum_abl_d6 / n_inst_f);

    // Find notable instance metrics
    var rec41_idx: usize = 0;
    var hel1_idx: usize = 0;
    for (results, 0..) |r, i| {
        if (std.mem.eql(u8, r.name, "reC41")) rec41_idx = i;
        if (std.mem.eql(u8, r.name, "hel1")) hel1_idx = i;
    }

    // Build atomic provenance ledger
    var ledger: std.ArrayList(LedgerEntry) = .empty;
    const src = "data/raw/flowshop1.txt";
    try addMetric(alloc, &ledger, "total_instances", n_inst_f, true, "instances", src, "all OR-Library PFSP blocks", raw_sha);
    try addMetric(alloc, &ledger, "ig_seeds_per_instance", @floatFromInt(IG_SEEDS), true, "seeds", src, "deterministic SplitMix64 protocol", raw_sha);
    try addMetric(alloc, &ledger, "total_ig_replications", @floatFromInt(instances.len * IG_SEEDS), true, "runs", src, "31 instances x 10 seeds", raw_sha);
    try addMetric(alloc, &ledger, "ig_iterations_per_run", @floatFromInt(IG_ITERS), true, "iterations", src, "IG destruction-construction budget", raw_sha);
    try addMetric(alloc, &ledger, "mean_gap_cds_lb_pct", mean_gap_cds, false, "%", src, "CDS mean gap vs analytical LB", raw_sha);
    try addMetric(alloc, &ledger, "mean_gap_neh_lb_pct", mean_gap_neh, false, "%", src, "NEH mean gap vs analytical LB", raw_sha);
    try addMetric(alloc, &ledger, "mean_gap_neh_ls_lb_pct", mean_gap_nls, false, "%", src, "NEH+LS mean gap vs analytical LB", raw_sha);
    try addMetric(alloc, &ledger, "mean_gap_ig_best_lb_pct", mean_gap_igb, false, "%", src, "IG best mean gap vs analytical LB", raw_sha);
    try addMetric(alloc, &ledger, "mean_gap_ig_mean_lb_pct", mean_gap_igm, false, "%", src, "IG 10-seed mean gap vs LB", raw_sha);
    try addMetric(alloc, &ledger, "mean_imp_ig_vs_neh_pct", mean_imp_neh, false, "%", src, "mean C_max reduction IG over NEH", raw_sha);
    try addMetric(alloc, &ledger, "mean_imp_ig_vs_cds_pct", mean_imp_cds, false, "%", src, "mean C_max reduction IG over CDS", raw_sha);
    try addMetric(alloc, &ledger, "ig_strict_wins_vs_neh", @floatFromInt(ig_strict_wins_neh), true, "instances", src, "instances where IG_best < NEH", raw_sha);
    try addMetric(alloc, &ledger, "ig_ties_vs_neh", @floatFromInt(ig_ties_neh), true, "instances", src, "instances where IG_best == NEH", raw_sha);
    try addMetric(alloc, &ledger, "ig_proven_lb_optima", @floatFromInt(ig_hits_lb), true, "instances", src, "instances where IG_best == LB_mach", raw_sha);
    try addMetric(alloc, &ledger, "ablation_d2_gap_lb_pct", mean_abl_d2, false, "%", src, "ablation d=2 mean gap vs LB", raw_sha);
    try addMetric(alloc, &ledger, "ablation_d4_gap_lb_pct", mean_abl_d4, false, "%", src, "ablation d=4 mean gap vs LB", raw_sha);
    try addMetric(alloc, &ledger, "ablation_d6_gap_lb_pct", mean_abl_d6, false, "%", src, "ablation d=6 mean gap vs LB", raw_sha);
    try addMetric(alloc, &ledger, "car1_ig_best_cmax", @floatFromInt(results[car1_inst_idx].ig_best), true, "time units", src, "instance car1 (11x5)", raw_sha);
    try addMetric(alloc, &ledger, "car1_lb", @floatFromInt(results[car1_inst_idx].lb), true, "time units", src, "instance car1 analytical LB", raw_sha);
    try addMetric(alloc, &ledger, "hel1_ig_best_cmax", @floatFromInt(results[hel1_idx].ig_best), true, "time units", src, "instance hel1 (100x10)", raw_sha);
    try addMetric(alloc, &ledger, "rec41_neh_cmax", @floatFromInt(results[rec41_idx].neh), true, "time units", src, "instance reC41 (75x20) NEH", raw_sha);
    try addMetric(alloc, &ledger, "rec41_ig_best_cmax", @floatFromInt(results[rec41_idx].ig_best), true, "time units", src, "instance reC41 (75x20) IG best", raw_sha);

    // Group mean metrics into ledger for Rule 10 chart/prose grounding
    const grp_keys = [_][]const u8{ "carlier", "heller", "reeves20", "reeves30", "reeves50_75" };
    for (0..5) |g| {
        const k_cds = try std.fmt.allocPrint(alloc, "grp_{s}_gap_cds_pct", .{grp_keys[g]});
        const k_neh = try std.fmt.allocPrint(alloc, "grp_{s}_gap_neh_pct", .{grp_keys[g]});
        const k_ig = try std.fmt.allocPrint(alloc, "grp_{s}_gap_ig_pct", .{grp_keys[g]});
        try addMetric(alloc, &ledger, k_cds, round2(grp_cds[g] / grp_cnt[g]), false, "%", src, grp_keys[g], raw_sha);
        try addMetric(alloc, &ledger, k_neh, round2(grp_neh[g] / grp_cnt[g]), false, "%", src, grp_keys[g], raw_sha);
        try addMetric(alloc, &ledger, k_ig, round2(grp_igb[g] / grp_cnt[g]), false, "%", src, grp_keys[g], raw_sha);
    }

    // Write data/provenance_ledger.json
    var led_buf: std.ArrayList(u8) = .empty;
    try led_buf.appendSlice(alloc, "[\n");
    for (ledger.items, 0..) |ent, i| {
        const comma: []const u8 = if (i + 1 < ledger.items.len) "," else "";
        const val_s = if (ent.is_int)
            try std.fmt.allocPrint(alloc, "{d}", .{@as(i64, @intFromFloat(@round(ent.value)))})
        else
            try std.fmt.allocPrint(alloc, "{d:.2}", .{ent.value});
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
        \\    "title": "Taillard-Accelerated Iterated Greedy for Permutation Flowshop Scheduling on 31 OR-Library Benchmarks",
        \\    "source": "J. E. Beasley OR-Library (Brunel University) — flowshop1.txt (Carlier 1978, Heller 1960, Reeves 1995)",
        \\    "raw_file_hashes": {{
        \\      "flowshop1.txt": "{s}"
        \\    }}
        \\  }},
        \\  "metrics": {{
        \\
    , .{raw_sha[0..64]}));

    for (ledger.items, 0..) |ent, i| {
        const comma: []const u8 = if (i + 1 < ledger.items.len) "," else "";
        const val_s = if (ent.is_int)
            try std.fmt.allocPrint(alloc, "{d}", .{@as(i64, @intFromFloat(@round(ent.value)))})
        else
            try std.fmt.allocPrint(alloc, "{d:.2}", .{ent.value});
        try sum_buf.appendSlice(alloc, try std.fmt.allocPrint(alloc, "    \"{s}\": {s}{s}\n", .{ ent.metric_id, val_s, comma }));
    }
    try sum_buf.appendSlice(alloc, "  },\n  \"instances\": [\n");
    for (results, 0..) |r, i| {
        const comma: []const u8 = if (i + 1 < results.len) "," else "";
        try sum_buf.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\    {{ "name": "{s}", "n": {d}, "m": {d}, "lb": {d}, "cds": {d}, "neh": {d}, "neh_ls": {d}, "ig_best": {d}, "ig_mean": {d:.1}, "ig_sd": {d:.1}, "imp_vs_neh_pct": {d:.2}, "gap_ig_best_lb_pct": {d:.2} }}{s}
            \\
        , .{
            r.name,
            r.n,
            r.m,
            r.lb,
            r.cds,
            r.neh,
            r.neh_ls,
            r.ig_best,
            r.ig_mean,
            r.ig_sd,
            r.imp_vs_neh_pct,
            r.gap_ig_best_lb_pct,
            comma,
        }));
    }
    try sum_buf.appendSlice(alloc, "  ]\n}\n");
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = try std.fmt.allocPrint(alloc, "{s}/data/summary_metrics.json", .{demo_dir}),
        .data = sum_buf.items,
    });

    // Emit pure-vector SVGs
    const svg1 = try renderBenchmarkConvergenceSvg(alloc, grp_cnt, grp_cds, grp_neh, grp_nls, grp_igb, results);
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = try std.fmt.allocPrint(alloc, "{s}/report/assets/fig_benchmark_convergence.svg", .{demo_dir}),
        .data = svg1,
    });

    const svg2 = try renderGanttAblationSvg(
        alloc,
        &instances[car1_inst_idx],
        &results[car1_inst_idx],
        mean_abl_d2,
        mean_abl_d4,
        mean_abl_d6,
        ig_strict_wins_neh,
        ig_ties_neh,
        ig_hits_lb,
    );
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = try std.fmt.allocPrint(alloc, "{s}/report/assets/fig_gantt_ablation.svg", .{demo_dir}),
        .data = svg2,
    });

    const out_msg = try std.fmt.allocPrint(alloc,
        \\[pipeline.zig] Solved & verified 31 OR-Library PFSP instances (310 IG runs + 465 ablation runs) | SHA-256={s}
        \\  Mean Gap vs LB: CDS={d:.2}% | NEH={d:.2}% | NEH+LS={d:.2}% | IG(Best)={d:.2}% | IG(Mean)={d:.2}%
        \\  IG vs NEH: mean reduction={d:.2}% | strict wins={d}/31 | ties={d}/31 | proven LB optima={d}/31
        \\  Ablation (d=2,4,6 gap vs LB): d=2 -> {d:.2}% | d=4 -> {d:.2}% | d=6 -> {d:.2}%
        \\  Landmarks: car1={d} (LB={d}) | hel1={d} | reC41 NEH={d} -> IG={d}
        \\
    , .{
        raw_sha[0..16],
        mean_gap_cds,
        mean_gap_neh,
        mean_gap_nls,
        mean_gap_igb,
        mean_gap_igm,
        mean_imp_neh,
        ig_strict_wins_neh,
        ig_ties_neh,
        ig_hits_lb,
        mean_abl_d2,
        mean_abl_d4,
        mean_abl_d6,
        results[car1_inst_idx].ig_best,
        results[car1_inst_idx].lb,
        results[hel1_idx].ig_best,
        results[rec41_idx].neh,
        results[rec41_idx].ig_best,
    });
    try std.Io.File.stdout().writeStreamingAll(io, out_msg);
}

fn renderBenchmarkConvergenceSvg(
    alloc: std.mem.Allocator,
    grp_cnt: [5]f64,
    grp_cds: [5]f64,
    grp_neh: [5]f64,
    grp_nls: [5]f64,
    grp_igb: [5]f64,
    results: []const BenchResult,
) ![]u8 {
    const w: f64 = 519.0;
    const h: f64 = 186.0;
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\<svg xmlns="http://www.w3.org/2000/svg" width="{d:.0}pt" height="{d:.0}pt" viewBox="0 0 {d:.0} {d:.0}">
        \\<rect width="{d:.0}" height="{d:.0}" fill="#FFFFFF" />
        \\
    , .{ w, h, w, h, w, h }));

    // --- PANEL A: Grouped Mean Gap vs LB (%) by Benchmark Family (x: 34..274, y: 24..148) ---
    const lx0: f64 = 34.0;
    const ly0: f64 = 24.0;
    const lw: f64 = 240.0;
    const lh: f64 = 124.0;

    try out.appendSlice(alloc,
        \\<text x="34" y="13" font-family="Inter, sans-serif" font-size="6.8" font-weight="700" letter-spacing="0.6" fill="#0F2942">(a) MEAN GAP TO ANALYTICAL LB (%) BY BENCHMARK FAMILY</text>
        \\
    );

    var ymax: f64 = 20.0;
    for (0..5) |g| {
        const v = grp_cds[g] / grp_cnt[g];
        if (v > ymax) ymax = v;
    }
    ymax = @ceil(ymax / 5.0) * 5.0;

    var tick: f64 = 0.0;
    while (tick <= ymax + 0.01) : (tick += 5.0) {
        const fy = ly0 + lh - (tick / ymax) * lh;
        const col: []const u8 = if (tick == 0.0) "#25303B" else "#DFE5EC";
        const sw: f64 = if (tick == 0.0) 0.75 else 0.45;
        try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\<line x1="{d:.1}" y1="{d:.1}" x2="{d:.1}" y2="{d:.1}" stroke="{s}" stroke-width="{d:.2}" />
            \\<text x="{d:.1}" y="{d:.1}" text-anchor="end" font-family="Inter, sans-serif" font-size="5.8" fill="#475569">{d:.0}%</text>
            \\
        , .{ lx0, fy, lx0 + lw, fy, col, sw, lx0 - 4.0, fy + 2.0, tick }));
    }

    const grp_lbls = [_][]const u8{ "Carlier", "Heller", "Reeves 20", "Reeves 30", "Reeves 50-75" };
    const alg_cols = [_][]const u8{ "#94A3B8", "#0B5CAD", "#146646", "#A83E0A" };
    const slot_w = lw / 5.0;
    const bw: f64 = 8.4;

    for (0..5) |g| {
        const gx0 = lx0 + @as(f64, @floatFromInt(g)) * slot_w + 5.5;
        const vals = [_]f64{
            grp_cds[g] / grp_cnt[g],
            grp_neh[g] / grp_cnt[g],
            grp_nls[g] / grp_cnt[g],
            grp_igb[g] / grp_cnt[g],
        };
        for (vals, 0..) |v, ai| {
            const bh = (v / ymax) * lh;
            const bx = gx0 + @as(f64, @floatFromInt(ai)) * (bw + 1.1);
            const by = ly0 + lh - bh;
            try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
                \\<rect x="{d:.1}" y="{d:.1}" width="{d:.1}" height="{d:.1}" fill="{s}" rx="0.8" />
                \\
            , .{ bx, by, bw, @max(1.0, bh), alg_cols[ai] }));
            if (ai == 3) {
                try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
                    \\<text x="{d:.1}" y="{d:.1}" text-anchor="middle" font-family="Inter, sans-serif" font-size="5.3" font-weight="700" fill="#A83E0A">{d:.1}</text>
                    \\
                , .{ bx + bw * 0.5, by - 2.5, v }));
            }
        }
        try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\<text x="{d:.1}" y="{d:.1}" text-anchor="middle" font-family="Inter, sans-serif" font-size="5.7" fill="#334155">{s}</text>
            \\
        , .{ lx0 + (@as(f64, @floatFromInt(g)) + 0.5) * slot_w, ly0 + lh + 11.0, grp_lbls[g] }));
    }

    // Legend row below Panel A
    const leg_lbls = [_][]const u8{ "CDS", "NEH", "NEH+LS", "IG (d=4)" };
    for (leg_lbls, 0..) |ll, li| {
        const lx = 44.0 + @as(f64, @floatFromInt(li)) * 56.0;
        try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\<rect x="{d:.1}" y="167" width="6.5" height="6.5" fill="{s}" rx="1" />
            \\<text x="{d:.1}" y="172.5" font-family="Inter, sans-serif" font-size="5.8" font-weight="600" fill="#1E293B">{s}</text>
            \\
        , .{ lx, alg_cols[li], lx + 9.0, ll }));
    }

    // --- PANEL B: IG Convergence Curves on Hard Reeves Instances (x: 312..510, y: 24..148) ---
    const rx0: f64 = 312.0;
    const ry0: f64 = 24.0;
    const rw: f64 = 198.0;
    const rh: f64 = 124.0;
    try out.appendSlice(alloc,
        \\<text x="312" y="13" font-family="Inter, sans-serif" font-size="6.8" font-weight="700" letter-spacing="0.6" fill="#0F2942">(b) IG ANYTIME CONVERGENCE (HARD REEVES)</text>
        \\
    );

    const track_names = [_][]const u8{ "reC19", "reC25", "reC37", "reC41" };
    const track_cols = [_][]const u8{ "#0F2942", "#0B5CAD", "#146646", "#A83E0A" };
    var track_idx: [4]usize = @splat(0);
    var c_ymax: f64 = 8.0;
    for (track_names, 0..) |tn, ti| {
        for (results, 0..) |r, ri| {
            if (std.mem.eql(u8, r.name, tn)) {
                track_idx[ti] = ri;
                for (r.conv_gap_lb) |gv| {
                    if (gv > c_ymax) c_ymax = gv;
                }
            }
        }
    }
    c_ymax = @ceil(c_ymax / 2.0) * 2.0 + 2.0;

    var ct: f64 = 0.0;
    const c_step: f64 = if (c_ymax > 14.0) 4.0 else 2.0;
    while (ct <= c_ymax + 0.01) : (ct += c_step) {
        const fy = ry0 + rh - (ct / c_ymax) * rh;
        const col: []const u8 = if (ct == 0.0) "#25303B" else "#DFE5EC";
        const sw: f64 = if (ct == 0.0) 0.75 else 0.45;
        try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\<line x1="{d:.1}" y1="{d:.1}" x2="{d:.1}" y2="{d:.1}" stroke="{s}" stroke-width="{d:.2}" />
            \\<text x="{d:.1}" y="{d:.1}" text-anchor="end" font-family="Inter, sans-serif" font-size="5.8" fill="#475569">{d:.0}%</text>
            \\
        , .{ rx0, fy, rx0 + rw, fy, col, sw, rx0 - 4.0, fy + 2.0, ct }));
    }

    const x_ticks = [_]usize{ 0, 100, 200, 300, 400 };
    for (x_ticks) |xt| {
        const fx = rx0 + (@as(f64, @floatFromInt(xt)) / 400.0) * rw;
        try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\<line x1="{d:.1}" y1="{d:.1}" x2="{d:.1}" y2="{d:.1}" stroke="#475569" stroke-width="0.6" />
            \\<text x="{d:.1}" y="{d:.1}" text-anchor="middle" font-family="Inter, sans-serif" font-size="5.7" fill="#475569">{d}</text>
            \\
        , .{ fx, ry0 + rh, fx, ry0 + rh + 3.0, fx, ry0 + rh + 11.0, xt }));
    }

    for (track_idx, 0..) |ri, ti| {
        const r = results[ri];
        var pts: std.ArrayList(u8) = .empty;
        for (CONV_POINTS, 0..) |iter_v, ci| {
            const fx = rx0 + (@as(f64, @floatFromInt(iter_v)) / 400.0) * rw;
            const fy = ry0 + rh - (r.conv_gap_lb[ci] / c_ymax) * rh;
            try pts.appendSlice(alloc, try std.fmt.allocPrint(alloc, "{s}{d:.1},{d:.1}", .{ if (ci > 0) " " else "", fx, fy }));
        }
        try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\<polyline points="{s}" fill="none" stroke="{s}" stroke-width="1.45" />
            \\
        , .{ pts.items, track_cols[ti] }));
        const end_y = ry0 + rh - (r.conv_gap_lb[CONV_POINTS.len - 1] / c_ymax) * rh;
        try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\<circle cx="{d:.1}" cy="{d:.1}" r="2.2" fill="{s}" />
            \\
        , .{ rx0 + rw, end_y, track_cols[ti] }));
    }

    // Legend row below Panel B
    const t_lbls = [_][]const u8{ "reC19 (30x10)", "reC25 (30x15)", "reC37 (75x20)", "reC41 (75x20)" };
    for (t_lbls, 0..) |tl, ti| {
        const lx = 304.0 + @as(f64, @floatFromInt(ti)) * 54.5;
        try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\<line x1="{d:.1}" y1="170" x2="{d:.1}" y2="170" stroke="{s}" stroke-width="1.8" />
            \\<text x="{d:.1}" y="172.5" font-family="Inter, sans-serif" font-size="5.3" font-weight="600" fill="#1E293B">{s}</text>
            \\
        , .{ lx, lx + 8.0, track_cols[ti], lx + 10.5, tl }));
    }

    try out.appendSlice(alloc, "</svg>\n");
    return out.toOwnedSlice(alloc);
}

fn renderGanttAblationSvg(
    alloc: std.mem.Allocator,
    car1: *const Instance,
    car1_res: *const BenchResult,
    abl_d2: f64,
    abl_d4: f64,
    abl_d6: f64,
    wins: i64,
    ties: i64,
    lb_hits: i64,
) ![]u8 {
    const w: f64 = 519.0;
    const h: f64 = 178.0;
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\<svg xmlns="http://www.w3.org/2000/svg" width="{d:.0}pt" height="{d:.0}pt" viewBox="0 0 {d:.0} {d:.0}">
        \\<rect width="{d:.0}" height="{d:.0}" fill="#FFFFFF" />
        \\
    , .{ w, h, w, h, w, h }));

    // --- PANEL A: Exact Optimal Gantt Schedule for car1 (11 jobs x 5 machines) ---
    const gx0: f64 = 30.0;
    const gy0: f64 = 24.0;
    const gw: f64 = 282.0;
    const gh: f64 = 122.0;
    const row_h = gh / @as(f64, @floatFromInt(car1.m));
    const cmax_f = @as(f64, @floatFromInt(car1_res.ig_best));

    try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\<text x="30" y="13" font-family="Inter, sans-serif" font-size="6.8" font-weight="700" letter-spacing="0.6" fill="#0F2942">(a) AUDITED SCHEDULE GANTT: car1 (11×5, makespan = {d})</text>
        \\
    , .{car1_res.ig_best}));

    var start_t: [MAX_N][MAX_M]i64 = undefined;
    var end_t: [MAX_N][MAX_M]i64 = undefined;
    for (0..car1.n) |pos| {
        const job = car1_res.best_perm[pos];
        for (0..car1.m) |mach| {
            const prev_j = if (pos > 0) end_t[pos - 1][mach] else 0;
            const prev_m = if (mach > 0) end_t[pos][mach - 1] else 0;
            start_t[pos][mach] = @max(prev_j, prev_m);
            end_t[pos][mach] = start_t[pos][mach] + car1.p[job][mach];
        }
    }

    const job_cols = [_][]const u8{
        "#0F2942", "#0B5CAD", "#146646", "#A83E0A", "#335C67",
        "#475569", "#1E6091", "#2D6A4F", "#9A4307", "#1D4E89",
        "#475569",
    };

    for (0..car1.m) |mach| {
        const ry = gy0 + @as(f64, @floatFromInt(mach)) * row_h;
        try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\<rect x="{d:.1}" y="{d:.1}" width="{d:.1}" height="{d:.1}" fill="#F4F6F9" />
            \\<text x="{d:.1}" y="{d:.1}" text-anchor="end" font-family="Inter, sans-serif" font-size="6.0" font-weight="700" fill="#1E293B">M{d}</text>
            \\
        , .{ gx0, ry + 2.0, gw, row_h - 4.0, gx0 - 5.0, ry + row_h * 0.5 + 2.0, mach + 1 }));

        for (0..car1.n) |pos| {
            const job = car1_res.best_perm[pos];
            const bx = gx0 + (@as(f64, @floatFromInt(start_t[pos][mach])) / cmax_f) * gw;
            const bw = (@as(f64, @floatFromInt(car1.p[job][mach])) / cmax_f) * gw;
            const col = job_cols[job % job_cols.len];
            try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
                \\<rect x="{d:.1}" y="{d:.1}" width="{d:.1}" height="{d:.1}" fill="{s}" stroke="#FFFFFF" stroke-width="0.55" rx="1.0" />
                \\
            , .{ bx, ry + 3.0, @max(1.2, bw), row_h - 6.0, col }));
            if (bw >= 13.5) {
                try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
                    \\<text x="{d:.1}" y="{d:.1}" text-anchor="middle" font-family="Inter, sans-serif" font-size="5.2" font-weight="700" fill="#FFFFFF">J{d}</text>
                    \\
                , .{ bx + bw * 0.5, ry + row_h * 0.5 + 1.8, job + 1 }));
            }
        }
    }

    // Time axis + C_max dashed marker
    const g_ticks = [_]i64{ 0, 2000, 4000, 6000, car1_res.ig_best };
    try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\<line x1="{d:.1}" y1="{d:.1}" x2="{d:.1}" y2="{d:.1}" stroke="#25303B" stroke-width="0.7" />
        \\<line x1="{d:.1}" y1="{d:.1}" x2="{d:.1}" y2="{d:.1}" stroke="#A83E0A" stroke-width="0.9" stroke-dasharray="2.5,1.5" />
        \\
    , .{ gx0, gy0 + gh, gx0 + gw, gy0 + gh, gx0 + gw, gy0, gx0 + gw, gy0 + gh }));

    for (g_ticks) |gt| {
        const tx = gx0 + (@as(f64, @floatFromInt(gt)) / cmax_f) * gw;
        const is_end = (gt == car1_res.ig_best);
        const col: []const u8 = if (is_end) "#A83E0A" else "#475569";
        const wt: []const u8 = if (is_end) "700" else "400";
        try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\<line x1="{d:.1}" y1="{d:.1}" x2="{d:.1}" y2="{d:.1}" stroke="{s}" stroke-width="0.6" />
            \\<text x="{d:.1}" y="{d:.1}" text-anchor="middle" font-family="Inter, sans-serif" font-size="5.6" font-weight="{s}" fill="{s}">{d}</text>
            \\
        , .{ tx, gy0 + gh, tx, gy0 + gh + 3.0, col, tx, gy0 + gh + 11.0, wt, col, gt }));
    }

    // --- PANEL B: Destruction Size Sensitivity Ablation (d=2, 4, 6) + Win Summary ---
    const ax0: f64 = 344.0;
    const aw: f64 = 166.0;
    try out.appendSlice(alloc,
        \\<text x="344" y="13" font-family="Inter, sans-serif" font-size="6.8" font-weight="700" letter-spacing="0.6" fill="#0F2942">(b) DESTRUCTION SIZE d ABLATION</text>
        \\
    );

    const abl_items = [_]struct { lbl: []const u8, v: f64, col: []const u8 }{
        .{ .lbl = "d = 2 (narrow)", .v = abl_d2, .col = "#475569" },
        .{ .lbl = "d = 4 (canonical)", .v = abl_d4, .col = "#A83E0A" },
        .{ .lbl = "d = 6 (wide)", .v = abl_d6, .col = "#0B5CAD" },
    };
    const max_a = @max(abl_d2, @max(abl_d4, abl_d6)) * 1.25;
    for (abl_items, 0..) |ai, idx| {
        const by = 32.0 + @as(f64, @floatFromInt(idx)) * 28.0;
        const bw_v = (ai.v / max_a) * aw;
        try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\<text x="{d:.1}" y="{d:.1}" font-family="Inter, sans-serif" font-size="6.1" font-weight="600" fill="#1E293B">{s}</text>
            \\<text x="{d:.1}" y="{d:.1}" text-anchor="end" font-family="IBM Plex Mono, monospace" font-size="6.1" font-weight="700" fill="{s}">{d:.2}%</text>
            \\<rect x="{d:.1}" y="{d:.1}" width="{d:.1}" height="9" fill="#E8EDF3" rx="1.5" />
            \\<rect x="{d:.1}" y="{d:.1}" width="{d:.1}" height="9" fill="{s}" rx="1.5" />
            \\
        , .{ ax0, by, ai.lbl, ax0 + aw, by, ai.col, ai.v, ax0, by + 3.5, aw, ax0, by + 3.5, bw_v, ai.col }));
    }

    // Compact audited win/tie/LB-optima summary strip below ablation bars
    try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\<rect x="{d:.1}" y="118" width="{d:.1}" height="46" fill="#F3F5F8" stroke="#CBD5E1" stroke-width="0.6" rx="2" />
        \\<text x="{d:.1}" y="130" font-family="Inter, sans-serif" font-size="5.8" font-weight="700" letter-spacing="0.7" fill="#0F2942">31-INSTANCE DOMINANCE SCORECARD</text>
        \\<text x="{d:.1}" y="143" font-family="Inter, sans-serif" font-size="6.1" fill="#1E293B">Strict wins vs. NEH: <tspan font-weight="700" fill="#146646">{d} / 31</tspan>  (ties: {d})</text>
        \\<text x="{d:.1}" y="155" font-family="Inter, sans-serif" font-size="6.1" fill="#1E293B">Matched analytical LB: <tspan font-weight="700" fill="#0B5CAD">{d} / 31</tspan> (zero violations)</text>
        \\
    , .{ ax0, aw, ax0 + 8.0, ax0 + 8.0, wins, ties, ax0 + 8.0, lb_hits }));

    try out.appendSlice(alloc, "</svg>\n");
    return out.toOwnedSlice(alloc);
}
