const std = @import("std");

extern "c" fn pow(x: f64, y: f64) f64;
extern "c" fn fmod(x: f64, y: f64) f64;
extern "c" fn sqrt(x: f64) f64;
fn pyFDiv(a: f64, b: f64) f64 {
    if (b == 0.0) unreachable; // ZeroDivisionError: out of domain
    return a / b;
}
fn pyFloatPow(a: f64, b: f64) f64 {
    if (a == 0.0 and b < 0.0) unreachable; // ZeroDivisionError: out of domain
    if (a < 0.0 and std.math.isFinite(b) and b != @trunc(b)) unreachable; // complex result: out of subset
    const r = pow(a, b);
    if (std.math.isInf(r) and std.math.isFinite(a) and std.math.isFinite(b)) unreachable; // OverflowError: out of domain
    return r;
}
fn pyFloatToInt(x: f64) i64 {
    if (std.math.isNan(x) or std.math.isInf(x)) unreachable; // ValueError/OverflowError: out of domain
    return @intFromFloat(@trunc(x));
}
fn pyIdx(i: i64, len: usize) usize {
    const l: i64 = @intCast(len);
    const j: i64 = if (i < 0) i + l else i;
    return @intCast(j); // negative -> trap == Python IndexError (out of domain)
}
fn pyAdd(qzx1: i64, qzx2: i64) i64 { return qzx1 + qzx2; } // runtime fn: never comptime-folded (overflow traps at runtime, as Python OOD)
fn pySub(qzx1: i64, qzx2: i64) i64 { return qzx1 - qzx2; }
fn pyMul(qzx1: i64, qzx2: i64) i64 { return qzx1 * qzx2; }
fn pyFDivI(qzx1: i64, qzx2: i64) i64 { return @divFloor(qzx1, qzx2); }
fn pyNeg(qzx1: i64) i64 { return -qzx1; }
fn pyRangeLen(start: i64, stop: i64, step: i64) i64 {
    if (step == 0) unreachable; // Python ValueError: out of domain
    const s: i128 = @as(i128, start);
    const e: i128 = @as(i128, stop);
    const k: i128 = @as(i128, step);
    if (k > 0) {
        if (s >= e) return 0;
        return @intCast(@divFloor(e - s - 1, k) + 1);
    } else {
        if (s <= e) return 0;
        return @intCast(@divFloor(s - e - 1, -k) + 1);
    }
}

pub fn @"rel_channel_x1000000"(p2z_in_0_v: i64) i64 {
    // uroboros:zig-tir
    var s: f64 = 0.0;
    s = pyFDiv(@as(f64, @floatFromInt(p2z_in_0_v)), @as(f64, @bitCast(@as(u64, 0x406fe00000000000))));
    if ((s <= @as(f64, @bitCast(@as(u64, 0x3fa4b5dcc63f1412))))) {
        return pyFloatToInt(((pyFDiv(s, @as(f64, @bitCast(@as(u64, 0x4029d70a3d70a3d7)))) * @as(f64, @bitCast(@as(u64, 0x412e848000000000)))) + @as(f64, @bitCast(@as(u64, 0x3fe0000000000000)))));
    }
    return pyFloatToInt(((pyFloatPow(pyFDiv((s + @as(f64, @bitCast(@as(u64, 0x3fac28f5c28f5c29)))), @as(f64, @bitCast(@as(u64, 0x3ff0e147ae147ae1)))), @as(f64, @bitCast(@as(u64, 0x4003333333333333)))) * @as(f64, @bitCast(@as(u64, 0x412e848000000000)))) + @as(f64, @bitCast(@as(u64, 0x3fe0000000000000)))));
}

fn @"p2z_tir_wcag_contrast_x100$h1_rel_channel_x1000000"(p2z_a: std.mem.Allocator, p2z_hin_0_v: i64) i64 {
    _ = p2z_a;
    var s: f64 = 0.0;
    s = pyFDiv(@as(f64, @floatFromInt(p2z_hin_0_v)), @as(f64, @bitCast(@as(u64, 0x406fe00000000000))));
    if ((s <= @as(f64, @bitCast(@as(u64, 0x3fa4b5dcc63f1412))))) {
        return pyFloatToInt(((pyFDiv(s, @as(f64, @bitCast(@as(u64, 0x4029d70a3d70a3d7)))) * @as(f64, @bitCast(@as(u64, 0x412e848000000000)))) + @as(f64, @bitCast(@as(u64, 0x3fe0000000000000)))));
    }
    return pyFloatToInt(((pyFloatPow(pyFDiv((s + @as(f64, @bitCast(@as(u64, 0x3fac28f5c28f5c29)))), @as(f64, @bitCast(@as(u64, 0x3ff0e147ae147ae1)))), @as(f64, @bitCast(@as(u64, 0x4003333333333333)))) * @as(f64, @bitCast(@as(u64, 0x412e848000000000)))) + @as(f64, @bitCast(@as(u64, 0x3fe0000000000000)))));
}

pub fn @"wcag_contrast_x100"(p2z_in_0_r1: i64, p2z_in_1_g1: i64, p2z_in_2_b1: i64, p2z_in_3_r2: i64, p2z_in_4_g2: i64, p2z_in_5_b2: i64) i64 {
    // uroboros:zig-tir
    var p2z_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer p2z_arena.deinit();
    const p2z_a = p2z_arena.allocator();
    var l1: f64 = 0.0;
    var l2: f64 = 0.0;
    var hi: f64 = 0.0;
    var lo: f64 = 0.0;
    l1 = (((@as(f64, @bitCast(@as(u64, 0x3fcb367a0f9096bc))) * pyFDiv(@as(f64, @floatFromInt(@"p2z_tir_wcag_contrast_x100$h1_rel_channel_x1000000"(p2z_a, p2z_in_0_r1))), @as(f64, @bitCast(@as(u64, 0x412e848000000000))))) + (@as(f64, @bitCast(@as(u64, 0x3fe6e2eb1c432ca5))) * pyFDiv(@as(f64, @floatFromInt(@"p2z_tir_wcag_contrast_x100$h1_rel_channel_x1000000"(p2z_a, p2z_in_1_g1))), @as(f64, @bitCast(@as(u64, 0x412e848000000000)))))) + (@as(f64, @bitCast(@as(u64, 0x3fb27bb2fec56d5d))) * pyFDiv(@as(f64, @floatFromInt(@"p2z_tir_wcag_contrast_x100$h1_rel_channel_x1000000"(p2z_a, p2z_in_2_b1))), @as(f64, @bitCast(@as(u64, 0x412e848000000000))))));
    l2 = (((@as(f64, @bitCast(@as(u64, 0x3fcb367a0f9096bc))) * pyFDiv(@as(f64, @floatFromInt(@"p2z_tir_wcag_contrast_x100$h1_rel_channel_x1000000"(p2z_a, p2z_in_3_r2))), @as(f64, @bitCast(@as(u64, 0x412e848000000000))))) + (@as(f64, @bitCast(@as(u64, 0x3fe6e2eb1c432ca5))) * pyFDiv(@as(f64, @floatFromInt(@"p2z_tir_wcag_contrast_x100$h1_rel_channel_x1000000"(p2z_a, p2z_in_4_g2))), @as(f64, @bitCast(@as(u64, 0x412e848000000000)))))) + (@as(f64, @bitCast(@as(u64, 0x3fb27bb2fec56d5d))) * pyFDiv(@as(f64, @floatFromInt(@"p2z_tir_wcag_contrast_x100$h1_rel_channel_x1000000"(p2z_a, p2z_in_5_b2))), @as(f64, @bitCast(@as(u64, 0x412e848000000000))))));
    hi = @as(f64, if ((l1 >= l2)) l1 else l2);
    lo = @as(f64, if ((l1 >= l2)) l2 else l1);
    return pyFloatToInt(((pyFDiv((hi + @as(f64, @bitCast(@as(u64, 0x3fa999999999999a)))), (lo + @as(f64, @bitCast(@as(u64, 0x3fa999999999999a))))) * @as(f64, @bitCast(@as(u64, 0x4059000000000000)))) + @as(f64, @bitCast(@as(u64, 0x3fe0000000000000)))));
}

pub fn @"wcag_passes_aa"(p2z_in_0_cr_x100: i64, p2z_in_1_size_x10: i64, p2z_in_2_is_bold: bool) bool {
    // uroboros:zig-tir
    if (((p2z_in_1_size_x10 >= @as(i64, 180)) or ((p2z_in_1_size_x10 >= @as(i64, 140)) and p2z_in_2_is_bold))) {
        return (p2z_in_0_cr_x100 >= @as(i64, 300));
    }
    return (p2z_in_0_cr_x100 >= @as(i64, 450));
}

pub fn @"cmyk_gcr_tac_x10"(p2z_in_0_r: i64, p2z_in_1_g: i64, p2z_in_2_b: i64) i64 {
    // uroboros:zig-tir
    var rf: f64 = 0.0;
    var gf: f64 = 0.0;
    var bf: f64 = 0.0;
    var mx: f64 = 0.0;
    var k_raw: f64 = 0.0;
    var c0: f64 = 0.0;
    var m0: f64 = 0.0;
    var y0: f64 = 0.0;
    var k: f64 = 0.0;
    var rem: f64 = 0.0;
    var c: f64 = 0.0;
    var m: f64 = 0.0;
    var y: f64 = 0.0;
    rf = pyFDiv(@as(f64, @floatFromInt(p2z_in_0_r)), @as(f64, @bitCast(@as(u64, 0x406fe00000000000))));
    gf = pyFDiv(@as(f64, @floatFromInt(p2z_in_1_g)), @as(f64, @bitCast(@as(u64, 0x406fe00000000000))));
    bf = pyFDiv(@as(f64, @floatFromInt(p2z_in_2_b)), @as(f64, @bitCast(@as(u64, 0x406fe00000000000))));
    mx = rf;
    if ((gf > mx)) {
        mx = gf;
    }
    if ((bf > mx)) {
        mx = bf;
    }
    k_raw = (@as(f64, @bitCast(@as(u64, 0x3ff0000000000000))) - mx);
    if ((k_raw >= @as(f64, @bitCast(@as(u64, 0x3feff7ced916872b))))) {
        return @as(i64, 2600);
    }
    c0 = pyFDiv(((@as(f64, @bitCast(@as(u64, 0x3ff0000000000000))) - rf) - k_raw), (@as(f64, @bitCast(@as(u64, 0x3ff0000000000000))) - k_raw));
    m0 = pyFDiv(((@as(f64, @bitCast(@as(u64, 0x3ff0000000000000))) - gf) - k_raw), (@as(f64, @bitCast(@as(u64, 0x3ff0000000000000))) - k_raw));
    y0 = pyFDiv(((@as(f64, @bitCast(@as(u64, 0x3ff0000000000000))) - bf) - k_raw), (@as(f64, @bitCast(@as(u64, 0x3ff0000000000000))) - k_raw));
    k = (k_raw * @as(f64, @bitCast(@as(u64, 0x3fe999999999999a))));
    rem = (k_raw * @as(f64, @bitCast(@as(u64, 0x3fc999999999999a))));
    c = ((c0 * (@as(f64, @bitCast(@as(u64, 0x3ff0000000000000))) - k_raw)) + rem);
    m = ((m0 * (@as(f64, @bitCast(@as(u64, 0x3ff0000000000000))) - k_raw)) + rem);
    y = ((y0 * (@as(f64, @bitCast(@as(u64, 0x3ff0000000000000))) - k_raw)) + rem);
    if ((c > @as(f64, @bitCast(@as(u64, 0x3ff0000000000000))))) {
        c = @as(f64, @bitCast(@as(u64, 0x3ff0000000000000)));
    }
    if ((m > @as(f64, @bitCast(@as(u64, 0x3ff0000000000000))))) {
        m = @as(f64, @bitCast(@as(u64, 0x3ff0000000000000)));
    }
    if ((y > @as(f64, @bitCast(@as(u64, 0x3ff0000000000000))))) {
        y = @as(f64, @bitCast(@as(u64, 0x3ff0000000000000)));
    }
    return pyFloatToInt((((((c + m) + y) + k) * @as(f64, @bitCast(@as(u64, 0x408f400000000000)))) + @as(f64, @bitCast(@as(u64, 0x3fe0000000000000)))));
}

pub fn @"span_collision_kind"(p2z_in_0_ax0: i64, p2z_in_1_ay0: i64, p2z_in_2_ax1: i64, p2z_in_3_ay1: i64, p2z_in_4_bx0: i64, p2z_in_5_by0: i64, p2z_in_6_bx1: i64, p2z_in_7_by1: i64, p2z_in_8_same_line: bool) i64 {
    // uroboros:zig-tir
    var aw: i64 = 0;
    var ah: i64 = 0;
    var bw: i64 = 0;
    var bh: i64 = 0;
    var ay_pad: i64 = 0;
    var ax_pad: i64 = 0;
    var by_pad: i64 = 0;
    var bx_pad: i64 = 0;
    var ca0: i64 = 0;
    var cb0: i64 = 0;
    var ca1: i64 = 0;
    var cb1: i64 = 0;
    var da0: i64 = 0;
    var db0: i64 = 0;
    var da1: i64 = 0;
    var db1: i64 = 0;
    var left: i64 = 0;
    var right: i64 = 0;
    var top: i64 = 0;
    var bottom: i64 = 0;
    var iw: i64 = 0;
    var ih: i64 = 0;
    var min_h: i64 = 0;
    aw = pySub(p2z_in_2_ax1, p2z_in_0_ax0);
    ah = pySub(p2z_in_3_ay1, p2z_in_1_ay0);
    bw = pySub(p2z_in_6_bx1, p2z_in_4_bx0);
    bh = pySub(p2z_in_7_by1, p2z_in_5_by0);
    if (((aw < @as(i64, 10)) or (ah < @as(i64, 10)) or (bw < @as(i64, 10)) or (bh < @as(i64, 10)))) {
        return @as(i64, 0);
    }
    ay_pad = pyFDivI(pyMul(ah, @as(i64, 20)), @as(i64, 100));
    ax_pad = pyFDivI(pyMul(aw, @as(i64, 10)), @as(i64, 100));
    if ((ax_pad > @as(i64, 10))) {
        ax_pad = @as(i64, 10);
    }
    by_pad = pyFDivI(pyMul(bh, @as(i64, 20)), @as(i64, 100));
    bx_pad = pyFDivI(pyMul(bw, @as(i64, 10)), @as(i64, 100));
    if ((bx_pad > @as(i64, 10))) {
        bx_pad = @as(i64, 10);
    }
    ca0 = pyAdd(p2z_in_0_ax0, ax_pad);
    cb0 = pyAdd(p2z_in_1_ay0, ay_pad);
    ca1 = pySub(p2z_in_2_ax1, ax_pad);
    cb1 = pySub(p2z_in_3_ay1, ay_pad);
    da0 = pyAdd(p2z_in_4_bx0, bx_pad);
    db0 = pyAdd(p2z_in_5_by0, by_pad);
    da1 = pySub(p2z_in_6_bx1, bx_pad);
    db1 = pySub(p2z_in_7_by1, by_pad);
    if (((ca1 <= ca0) or (cb1 <= cb0) or (da1 <= da0) or (db1 <= db0))) {
        return @as(i64, 0);
    }
    left = @as(i64, if ((ca0 >= da0)) ca0 else da0);
    right = @as(i64, if ((ca1 <= da1)) ca1 else da1);
    top = @as(i64, if ((cb0 >= db0)) cb0 else db0);
    bottom = @as(i64, if ((cb1 <= db1)) cb1 else db1);
    iw = pySub(right, left);
    ih = pySub(bottom, top);
    if (((iw <= @as(i64, 0)) or (ih <= @as(i64, 0)))) {
        return @as(i64, 0);
    }
    min_h = @as(i64, if ((ah <= bh)) ah else bh);
    if (p2z_in_8_same_line) {
        if (((iw > @as(i64, 35)) and (pyMul(ih, @as(i64, 100)) > pyMul(@as(i64, 35), min_h)))) {
            return @as(i64, 1);
        }
        return @as(i64, 0);
    }
    if (((iw > @as(i64, 25)) and (ih > @as(i64, 25)))) {
        return @as(i64, 2);
    }
    return @as(i64, 0);
}

pub fn @"is_orphan_headline"(p2z_in_0_w0_x10: i64, p2z_in_1_w_last_x10: i64, p2z_in_2_words_last: i64, p2z_in_3_word_len: i64) bool {
    // uroboros:zig-tir
    if (((p2z_in_0_w0_x10 < @as(i64, 2600)) or (p2z_in_2_words_last != @as(i64, 1)) or (p2z_in_3_word_len > @as(i64, 15)))) {
        return false;
    }
    return (pyMul(p2z_in_1_w_last_x10, @as(i64, 100)) < pyMul(p2z_in_0_w0_x10, @as(i64, 38)));
}

pub fn @"rule10_is_grounded_x100"(p2z_in_0_val_x100: i64, p2z_in_1_authorized_x100: []const i64) bool {
    // uroboros:zig-tir
    var a: i64 = 0;
    var diff: i64 = 0;
    {
        const p2z_fs2: []const i64 = p2z_in_1_authorized_x100;
        var p2z_fi3: usize = 0;
        while (p2z_fi3 < p2z_fs2.len) : (p2z_fi3 += 1) {
            a = p2z_fs2[p2z_fi3];
            diff = pySub(p2z_in_0_val_x100, a);
            if ((diff < @as(i64, 0))) {
                diff = pyNeg(diff);
            }
            if ((diff <= @as(i64, 5))) {
                return true;
            }
        }
    }
    return false;
}

pub fn @"effective_dpi_x10"(p2z_in_0_native_w: i64, p2z_in_1_native_h: i64, p2z_in_2_placed_w_x10: i64, p2z_in_3_placed_h_x10: i64) i64 {
    // uroboros:zig-tir
    var dpi_w: f64 = 0.0;
    var dpi_h: f64 = 0.0;
    var lo: f64 = 0.0;
    if (((p2z_in_0_native_w <= @as(i64, 0)) or (p2z_in_1_native_h <= @as(i64, 0)) or (p2z_in_2_placed_w_x10 <= @as(i64, 0)) or (p2z_in_3_placed_h_x10 <= @as(i64, 0)))) {
        return @as(i64, 0);
    }
    dpi_w = pyFDiv((@as(f64, @floatFromInt(p2z_in_0_native_w)) * @as(f64, @bitCast(@as(u64, 0x4086800000000000)))), @as(f64, @floatFromInt(p2z_in_2_placed_w_x10)));
    dpi_h = pyFDiv((@as(f64, @floatFromInt(p2z_in_1_native_h)) * @as(f64, @bitCast(@as(u64, 0x4086800000000000)))), @as(f64, @floatFromInt(p2z_in_3_placed_h_x10)));
    lo = @as(f64, if ((dpi_w <= dpi_h)) dpi_w else dpi_h);
    return pyFloatToInt(((lo * @as(f64, @bitCast(@as(u64, 0x4024000000000000)))) + @as(f64, @bitCast(@as(u64, 0x3fe0000000000000)))));
}

pub fn @"detect_grid_columns"(p2z_in_0_span_x0s: []const i64, p2z_in_1_span_x1s: []const i64, p2z_in_2_page_w: i64) i64 {
    // uroboros:zig-tir
    var n: i64 = 0;
    var third: i64 = 0;
    var two_third: i64 = 0;
    var half: i64 = 0;
    var left_only: i64 = 0;
    var mid_only: i64 = 0;
    var right_only: i64 = 0;
    var left_half: i64 = 0;
    var right_half: i64 = 0;
    var full_span: i64 = 0;
    var i: i64 = 0;
    var x0: i64 = 0;
    var x1: i64 = 0;
    var w: i64 = 0;
    n = @as(i64, @intCast((p2z_in_0_span_x0s).len));
    if (((n == @as(i64, 0)) or (p2z_in_2_page_w <= @as(i64, 0)))) {
        return @as(i64, 1);
    }
    third = pyFDivI(p2z_in_2_page_w, @as(i64, 3));
    two_third = pyFDivI(pyMul(p2z_in_2_page_w, @as(i64, 2)), @as(i64, 3));
    half = pyFDivI(p2z_in_2_page_w, @as(i64, 2));
    left_only = @as(i64, 0);
    mid_only = @as(i64, 0);
    right_only = @as(i64, 0);
    left_half = @as(i64, 0);
    right_half = @as(i64, 0);
    full_span = @as(i64, 0);
    {
        const p2z_rs8: i64 = @as(i64, 0);
        const p2z_re9: i64 = n;
        const p2z_rk10: i64 = @as(i64, 1);
        const p2z_cnt11: i64 = pyRangeLen(p2z_rs8, p2z_re9, p2z_rk10);
        p2z_fl1: for (0..@as(usize, @intCast(p2z_cnt11))) |p2z_fi12| {
            i = @intCast(@as(i128, p2z_rs8) + @as(i128, @intCast(p2z_fi12)) * @as(i128, p2z_rk10));
            x0 = (p2z_blk2: { const p2z_sl3: []const i64 = p2z_in_0_span_x0s; const p2z_ix4: i64 = i; break :p2z_blk2 p2z_sl3[pyIdx(p2z_ix4, p2z_sl3.len)]; });
            x1 = (p2z_blk5: { const p2z_sl6: []const i64 = p2z_in_1_span_x1s; const p2z_ix7: i64 = i; break :p2z_blk5 p2z_sl6[pyIdx(p2z_ix7, p2z_sl6.len)]; });
            w = pySub(x1, x0);
            if ((w < @as(i64, 18))) {
                continue :p2z_fl1;
            }
            if ((pyMul(w, @as(i64, 100)) >= pyMul(p2z_in_2_page_w, @as(i64, 68)))) {
                full_span = pyAdd(full_span, @as(i64, 1));
            } else {
                if ((x1 <= pyAdd(third, @as(i64, 20)))) {
                    left_only = pyAdd(left_only, @as(i64, 1));
                } else {
                    if (((x0 >= pySub(third, @as(i64, 20))) and (x1 <= pyAdd(two_third, @as(i64, 20))))) {
                        mid_only = pyAdd(mid_only, @as(i64, 1));
                    } else {
                        if ((x0 >= pySub(two_third, @as(i64, 20)))) {
                            right_only = pyAdd(right_only, @as(i64, 1));
                        }
                    }
                }
            }
            if ((x1 <= pyAdd(half, @as(i64, 28)))) {
                left_half = pyAdd(left_half, @as(i64, 1));
            } else {
                if ((x0 >= pySub(half, @as(i64, 28)))) {
                    right_half = pyAdd(right_half, @as(i64, 1));
                }
            }
        }
    }
    if (((left_only >= @as(i64, 3)) and (mid_only >= @as(i64, 3)) and (right_only >= @as(i64, 3)))) {
        return @as(i64, 3);
    }
    if (((left_half >= @as(i64, 3)) and (right_half >= @as(i64, 3)))) {
        return @as(i64, 2);
    }
    if ((full_span > @as(i64, 0))) {
        return @as(i64, 1);
    }
    return @as(i64, 1);
}

pub fn @"classify_page_archetype"(p2z_in_0_photo_pct_x10: i64, p2z_in_1_text_spans: i64, p2z_in_2_max_font_x10: i64, p2z_in_3_col_count: i64, p2z_in_4_page_idx: i64, p2z_in_5_page_count: i64) i64 {
    // uroboros:zig-tir
    if (((p2z_in_4_page_idx == @as(i64, 1)) and ((p2z_in_2_max_font_x10 >= @as(i64, 220)) or (p2z_in_0_photo_pct_x10 >= @as(i64, 550))))) {
        return @as(i64, 0);
    }
    if ((p2z_in_0_photo_pct_x10 >= @as(i64, 750))) {
        return @as(i64, 1);
    }
    if ((p2z_in_0_photo_pct_x10 >= @as(i64, 300))) {
        return @as(i64, 2);
    }
    if (((p2z_in_4_page_idx == p2z_in_5_page_count) and (p2z_in_5_page_count >= @as(i64, 3)))) {
        return @as(i64, 5);
    }
    if ((p2z_in_1_text_spans >= @as(i64, 45))) {
        return @as(i64, 3);
    }
    if ((p2z_in_3_col_count >= @as(i64, 2))) {
        return @as(i64, 4);
    }
    return @as(i64, 6);
}
