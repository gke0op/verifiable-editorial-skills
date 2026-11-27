//! Complete 5-Gate Verification Court & Pure-Zig SHA-256 Compilation Latch.
//! Every numerical invariant delegates directly to `kernels_p2zig.zig` (transpiled via `p2zig --strict`).

const std = @import("std");
const kernels = @import("kernels_p2zig.zig");
const mupdf = @import("mupdf.zig");

pub const ContrastViolation = struct {
    page: usize,
    text: []const u8,
    size_pt: f64,
    fg_hex: [7]u8,
    bg_hex: [7]u8,
    ratio_x100: i64,
    required_x100: i64,
};

pub const ContrastReport = struct {
    pages: usize,
    total_spans: usize,
    total_violations: usize,
    worst_cr_x100: i64,
    passed: bool,
    violations: []const ContrastViolation,
};

pub const GeometryIssue = struct {
    page: usize,
    kind: []const u8,
    detail: []const u8,
};

pub const GeometryReport = struct {
    pages: usize,
    total_spans: usize,
    collisions: usize,
    clipped: usize,
    trim_overflow: usize,
    headline_orphans: usize,
    noisy_overlays: usize,
    worst_rms: f64,
    passed: bool,
    issues: []const GeometryIssue,
};

pub const PageCoverage = struct {
    page: usize,
    enforced: bool,
    visible_pct: f64,
    bleed_edges: i64,
    passed: bool,
};

pub const CoverageReport = struct {
    pages: usize,
    enforced_count: usize,
    min_visible_pct: f64,
    avg_visible_pct: f64,
    failures: []const []const u8,
    page_reports: []const PageCoverage,
    passed: bool,
};

pub const UngroundedToken = struct {
    page: usize,
    token: []const u8,
    value: f64,
    context: []const u8,
};

pub const ProseReport = struct {
    pages: usize,
    authorized_pool: usize,
    numbers_checked: usize,
    ungrounded_count: usize,
    passed: bool,
    ungrounded: []const UngroundedToken,
};

pub const VeraPdfResult = struct {
    available: bool,
    compliant: bool,
    passed_rules: i64,
    failed_rules: i64,
};

pub const PrepressReport = struct {
    pages: usize,
    image_count: usize,
    min_eff_dpi_x10: i64, // -1 if pure vector (0 raster images)
    unembedded_fonts: []const []const u8,
    bleed_all_pages: bool,
    min_bleed_margin_pt: f64,
    cmyk_p99_tac_x10: i64,
    cmyk_peak_tac_x10: i64,
    ua_struct_pass: bool,
    verapdf: VeraPdfResult,
    failures: []const []const u8,
    passed: bool,
};

pub const LatchReport = struct {
    manifest_files: usize,
    manifest_verified: usize,
    ledger_records: usize,
    metrics_verified: usize,
    failures: []const []const u8,
    passed: bool,
};

fn isAsciiAlnum(ch: u8) bool {
    return (ch >= 'A' and ch <= 'Z') or (ch >= 'a' and ch <= 'z') or (ch >= '0' and ch <= '9');
}

fn isCheckableCodepoint(cp: u21) bool {
    if (cp < 0x80) return isAsciiAlnum(@intCast(cp));
    // Exclude standalone decorative arrows, geometric shapes, dingbats, box drawing & punctuation
    if (cp >= 0x2000 and cp <= 0x206F) return false;
    if (cp >= 0x2190 and cp <= 0x27BF) return false;
    if (cp == 0x00A0 or cp == 0x00B7) return false;
    return true;
}

fn isSpanCheckable(txt: []const u8) bool {
    if (txt.len == 0) return false;
    var i: usize = 0;
    while (i < txt.len) {
        const b0 = txt[i];
        if (b0 < 0x80) {
            if (isAsciiAlnum(b0)) return true;
            i += 1;
            continue;
        }
        const slen = std.unicode.utf8ByteSequenceLength(b0) catch {
            i += 1;
            continue;
        };
        if (i + slen > txt.len) break;
        const cp = std.unicode.utf8Decode(txt[i .. i + slen]) catch {
            i += 1;
            continue;
        };
        if (isCheckableCodepoint(cp)) return true;
        i += slen;
    }
    return false;
}

fn pixelL1(a: mupdf.Rgb, b: mupdf.Rgb) i32 {
    const dr: i32 = @as(i32, a.r) - @as(i32, b.r);
    const dg: i32 = @as(i32, a.g) - @as(i32, b.g);
    const db: i32 = @as(i32, a.b) - @as(i32, b.b);
    return @as(i32, @intCast(@abs(dr))) + @as(i32, @intCast(@abs(dg))) + @as(i32, @intCast(@abs(db)));
}

const CrRgbSample = struct { cr: i64, rgb: mupdf.Rgb };

fn crSampleLessThan(_: void, a: CrRgbSample, b: CrRgbSample) bool {
    return a.cr < b.cr;
}

fn sampleCompositedCoreContrast(
    alloc: std.mem.Allocator,
    bg_ppm: mupdf.PpmImage,
    fg_ppm: mupdf.PpmImage,
    sp: mupdf.PageSpan,
    dpi: u32,
    ink_crs: *std.ArrayList(i64),
) !struct { has_ink: bool, core_cr: i64, best_fg: mupdf.Rgb, best_bg: mupdf.Rgb } {
    const w = @min(bg_ppm.width, fg_ppm.width);
    const h = @min(bg_ppm.height, fg_ppm.height);
    const scale: f64 = @as(f64, @floatFromInt(dpi)) / 72.0;
    const ix0: usize = @intFromFloat(std.math.clamp(@round(sp.x0 * scale), 0.0, @as(f64, @floatFromInt(w - 1))));
    const ix1: usize = @max(ix0 + 1, @as(usize, @intFromFloat(std.math.clamp(@round(sp.x1 * scale), 0.0, @as(f64, @floatFromInt(w))))));
    const iy0: usize = @intFromFloat(std.math.clamp(@round(sp.y0 * scale), 0.0, @as(f64, @floatFromInt(h - 1))));
    const iy1: usize = @max(iy0 + 1, @as(usize, @intFromFloat(std.math.clamp(@round(sp.y1 * scale), 0.0, @as(f64, @floatFromInt(h))))));

    ink_crs.clearRetainingCapacity();
    const csx = @max(@as(usize, 1), (ix1 - ix0) / 64);
    const csy = @max(@as(usize, 1), (iy1 - iy0) / 24);
    var max_delta: i32 = 0;
    var best_ink_fg: mupdf.Rgb = sp.fg;
    var best_ink_bg: mupdf.Rgb = bg_ppm.pixelAt((ix0 + ix1) / 2, (iy0 + iy1) / 2);

    var cpy = iy0;
    while (cpy < iy1) : (cpy += csy) {
        var cpx = ix0;
        while (cpx < ix1) : (cpx += csx) {
            const fp = fg_ppm.pixelAt(cpx, cpy);
            const bp = bg_ppm.pixelAt(cpx, cpy);
            const dl = pixelL1(fp, bp);
            if (dl > max_delta) {
                max_delta = dl;
                best_ink_fg = fp;
                best_ink_bg = bp;
            }
            if (dl >= 6) {
                const pcr = kernels.wcag_contrast_x100(fp.r, fp.g, fp.b, bp.r, bp.g, bp.b);
                try ink_crs.append(alloc, pcr);
            }
        }
    }
    if (ink_crs.items.len == 0) {
        return .{ .has_ink = false, .core_cr = 100, .best_fg = best_ink_fg, .best_bg = best_ink_bg };
    }
    std.mem.sort(i64, ink_crs.items, {}, std.sort.asc(i64));
    const core_idx = (ink_crs.items.len - 1) * 98 / 100;
    return .{ .has_ink = true, .core_cr = ink_crs.items[core_idx], .best_fg = best_ink_fg, .best_bg = best_ink_bg };
}

/// Gate 1: Composited 144-DPI (with lazy 360-DPI Nyquist supersampling on sub-pixel hairline strokes)
/// background-vs-foreground WCAG 2.1 AA contrast across every span.
/// Defeats alpha-ghost text, Z-order overpainting/occlusion, `/BM /Screen`, `3 Tr`, phantom per-channel RGB medians,
/// split backgrounds, and trailing-dot foreground color poisoning.
pub fn auditContrast(
    alloc: std.mem.Allocator,
    io: std.Io,
    pdf_path: []const u8,
    pages: []const mupdf.PageData,
    tmp_tag: []const u8,
) !ContrastReport {
    const bg_pdf = try mupdf.makeBackgroundOnlyPdf(alloc, io, pdf_path, tmp_tag);
    defer mupdf.removeTmpBestEffort(io, bg_pdf);

    var violations: std.ArrayList(ContrastViolation) = .empty;
    var total_spans: usize = 0;
    var worst_cr: i64 = 2100;

    var bg_samples: std.ArrayList(CrRgbSample) = .empty;
    var ink_crs: std.ArrayList(i64) = .empty;

    const dpi: u32 = 144;
    const scale: f64 = @as(f64, @floatFromInt(dpi)) / 72.0;

    for (pages) |pg| {
        const bg_ppm = try mupdf.renderPagePpm(alloc, io, bg_pdf, pg.page_num, dpi, tmp_tag);
        const fg_ppm = try mupdf.renderPagePpm(alloc, io, pdf_path, pg.page_num, dpi, tmp_tag);
        const w = @min(bg_ppm.width, fg_ppm.width);
        const h = @min(bg_ppm.height, fg_ppm.height);
        if (w == 0 or h == 0) continue;

        // Lazy per-page 360-DPI cache for sub-Nyquist thin strokes (< 1px wide at 144 DPI)
        var hi_bg_ppm: ?mupdf.PpmImage = null;
        var hi_fg_ppm: ?mupdf.PpmImage = null;

        for (pg.spans) |sp| {
            if (!isSpanCheckable(sp.text)) continue;
            // Skip spans completely outside the visible page bounds (caught by geometry trim_overflow)
            if (sp.x1 <= 0.0 or sp.y1 <= 0.0 or sp.x0 >= pg.width or sp.y0 >= pg.height) continue;

            const ix0: usize = @intFromFloat(std.math.clamp(@round(sp.x0 * scale), 0.0, @as(f64, @floatFromInt(w - 1))));
            const ix1: usize = @max(ix0 + 1, @as(usize, @intFromFloat(std.math.clamp(@round(sp.x1 * scale), 0.0, @as(f64, @floatFromInt(w))))));
            const iy0: usize = @intFromFloat(std.math.clamp(@round(sp.y0 * scale), 0.0, @as(f64, @floatFromInt(h - 1))));
            const iy1: usize = @max(iy0 + 1, @as(usize, @intFromFloat(std.math.clamp(@round(sp.y1 * scale), 0.0, @as(f64, @floatFromInt(h))))));

            // 1. Composited foreground-vs-background pixel check (catches alpha opacity, Z-order white rects, /BM /Screen, 3 Tr)
            var comp = try sampleCompositedCoreContrast(alloc, bg_ppm, fg_ppm, sp, dpi, &ink_crs);

            // 2. Real observed background pixel check (never per-channel independent median!), evaluated across left & right halves on wide spans
            const span_w_pt = sp.x1 - sp.x0;
            const n_slices: usize = if (span_w_pt >= 36.0 and (ix1 - ix0) >= 8) 2 else 1;
            var worst_bg_cr: i64 = 2100;
            var worst_bg_rgb: mupdf.Rgb = comp.best_bg;
            const bsx = @max(@as(usize, 1), (ix1 - ix0) / 24);
            const bsy = @max(@as(usize, 1), (iy1 - iy0) / 10);

            for (0..n_slices) |si| {
                const sx0 = ix0 + (ix1 - ix0) * si / n_slices;
                const sx1 = @max(sx0 + 1, ix0 + (ix1 - ix0) * (si + 1) / n_slices);
                bg_samples.clearRetainingCapacity();
                var py = iy0;
                while (py < iy1) : (py += bsy) {
                    var px = sx0;
                    while (px < sx1) : (px += bsx) {
                        const pix = bg_ppm.pixelAt(px, py);
                        const pcr = kernels.wcag_contrast_x100(sp.fg.r, sp.fg.g, sp.fg.b, pix.r, pix.g, pix.b);
                        try bg_samples.append(alloc, .{ .cr = pcr, .rgb = pix });
                    }
                }
                if (bg_samples.items.len == 0) continue;
                std.mem.sort(CrRgbSample, bg_samples.items, {}, crSampleLessThan);
                const med = bg_samples.items[bg_samples.items.len / 2];
                if (med.cr < worst_bg_cr) {
                    worst_bg_cr = med.cr;
                    worst_bg_rgb = med.rgb;
                }
            }

            const size_x10 = mupdf.checkedRoundInt(i64, sp.size * 10.0, 0.0, 1.0e7) catch 100;
            const req: i64 = if (size_x10 >= 180 or (sp.is_bold and size_x10 >= 140)) 300 else 450;

            // Lazy 360-DPI Nyquist supersampling when symbolic contrast passes AA but 144-DPI thin-stroke AA dropped below threshold
            // (alpha ghosts, Z-order cover rects, `/BM /Screen`, and `3 Tr` still fail identically at 360 DPI!)
            if (comp.has_ink and comp.core_cr < req and worst_bg_cr >= req) {
                if (hi_bg_ppm == null) {
                    hi_bg_ppm = try mupdf.renderPagePpm(alloc, io, bg_pdf, pg.page_num, 360, tmp_tag);
                    hi_fg_ppm = try mupdf.renderPagePpm(alloc, io, pdf_path, pg.page_num, 360, tmp_tag);
                }
                comp = try sampleCompositedCoreContrast(alloc, hi_bg_ppm.?, hi_fg_ppm.?, sp, 360, &ink_crs);
            }

            // Combine composited pixel contrast with real-pixel half-median contrast
            var cr: i64 = worst_bg_cr;
            var eff_fg: mupdf.Rgb = sp.fg;
            var eff_bg: mupdf.Rgb = worst_bg_rgb;

            if (!comp.has_ink) {
                // Zero visible pixel delta between bg and fg -> text is occluded, invisible (`3 Tr`), or `/BM /Screen` erased
                cr = 100;
                eff_fg = comp.best_fg;
                eff_bg = comp.best_bg;
            } else if (comp.core_cr < cr and (comp.core_cr < 300 or sp.size >= 10.0 or comp.core_cr * 100 < cr * 70)) {
                cr = comp.core_cr;
                eff_fg = comp.best_fg;
                eff_bg = comp.best_bg;
            }

            total_spans += 1;
            if (cr < worst_cr) worst_cr = cr;

            if (!kernels.wcag_passes_aa(cr, size_x10, sp.is_bold)) {
                var fg_h: [7]u8 = undefined;
                var bg_h: [7]u8 = undefined;
                _ = eff_fg.formatHex(&fg_h);
                _ = eff_bg.formatHex(&bg_h);
                const cut_len = @min(sp.text.len, 48);
                try violations.append(alloc, .{
                    .page = pg.page_num,
                    .text = try alloc.dupe(u8, sp.text[0..cut_len]),
                    .size_pt = sp.size,
                    .fg_hex = fg_h,
                    .bg_hex = bg_h,
                    .ratio_x100 = cr,
                    .required_x100 = req,
                });
            }
        }
    }

    const vlist = try violations.toOwnedSlice(alloc);
    return .{
        .pages = pages.len,
        .total_spans = total_spans,
        .total_violations = vlist.len,
        .worst_cr_x100 = if (total_spans > 0) worst_cr else 2100,
        .passed = vlist.len == 0,
        .violations = vlist,
    };
}

fn lumaAt(ppm: mupdf.PpmImage, px: usize, py: usize) f64 {
    const rgb = ppm.pixelAt(px, py);
    return 0.299 * @as(f64, @floatFromInt(rgb.r)) +
        0.587 * @as(f64, @floatFromInt(rgb.g)) +
        0.114 * @as(f64, @floatFromInt(rgb.b));
}

const HeadLine = struct {
    text: []const u8,
    size: f64,
    x0: f64,
    x1: f64,
    y0: f64,
    y1: f64,
    yc: f64,
};

fn countAlphaWords(s: []const u8) struct { count: i64, first_len: i64 } {
    var count: i64 = 0;
    var first_len: i64 = 0;
    var it = std.mem.tokenizeAny(u8, s, " \t\r\n");
    while (it.next()) |w| {
        var has_al = false;
        for (w) |ch| {
            if (isAsciiAlnum(ch)) {
                has_al = true;
                break;
            }
        }
        if (has_al) {
            if (count == 0) first_len = @intCast(w.len);
            count += 1;
        }
    }
    return .{ .count = count, .first_len = first_len };
}

fn countUtf8PrintableFreq(alloc: std.mem.Allocator, spans: []const mupdf.PageSpan, page_w: f64, page_h: f64, filter_trim: bool) !std.AutoHashMap(u21, usize) {
    var freq = std.AutoHashMap(u21, usize).init(alloc);
    for (spans) |sp| {
        if (filter_trim and (sp.x1 < 0.0 or sp.y1 < 0.0 or sp.x0 > page_w or sp.y0 > page_h)) continue;
        var it = std.unicode.Utf8View.initUnchecked(sp.text).iterator();
        while (it.nextCodepoint()) |cp| {
            const ok = if (cp < 0x80) isAsciiAlnum(@intCast(cp)) else (cp >= 0x00C0 and !(cp >= 0x2000 and cp <= 0x206F));
            if (!ok) continue;
            const gop = try freq.getOrPut(cp);
            if (gop.found_existing) gop.value_ptr.* += 1 else gop.value_ptr.* = 1;
        }
    }
    return freq;
}

const SpanObb = struct {
    cx: f64,
    cy: f64,
    ux: f64,
    uy: f64,
    vx: f64,
    vy: f64,
    hu: f64,
    hv: f64,
};

fn buildSpanObb(sp: mupdf.PageSpan) SpanObb {
    const dlen = @sqrt(sp.dir_x * sp.dir_x + sp.dir_y * sp.dir_y);
    const ux: f64 = if (dlen > 1e-6) sp.dir_x / dlen else 1.0;
    const uy: f64 = if (dlen > 1e-6) sp.dir_y / dlen else 0.0;
    const vx: f64 = -uy;
    const vy: f64 = ux;
    const bw = sp.x1 - sp.x0;
    const bh = sp.y1 - sp.y0;
    const cx = 0.5 * (sp.x0 + sp.x1);
    const cy = 0.5 * (sp.y0 + sp.y1);
    // Reconstruct tight oriented length & thickness along (u, v) from AABB + font size
    const thick = @max(2.0, @min(sp.size * 0.95, @min(bw, bh)));
    const a_cos = @abs(ux);
    const a_sin = @abs(uy);
    var len: f64 = if (a_cos >= a_sin)
        (bw - thick * a_sin) / @max(0.25, a_cos)
    else
        (bh - thick * a_cos) / @max(0.25, a_sin);
    if (len < thick) len = @max(bw, bh);
    // Shrink slightly to glyph ink core (15% height, 1pt ends)
    return .{
        .cx = cx,
        .cy = cy,
        .ux = ux,
        .uy = uy,
        .vx = vx,
        .vy = vy,
        .hu = @max(1.0, len * 0.5 - 1.0),
        .hv = @max(1.0, thick * 0.38),
    };
}

fn obbSatOverlaps(a: mupdf.PageSpan, b: mupdf.PageSpan) bool {
    // Fast AABB reject
    if (a.x1 <= b.x0 + 1.5 or b.x1 <= a.x0 + 1.5 or a.y1 <= b.y0 + 1.5 or b.y1 <= a.y0 + 1.5) return false;
    const oa = buildSpanObb(a);
    const ob = buildSpanObb(b);
    const dx = ob.cx - oa.cx;
    const dy = ob.cy - oa.cy;
    const axes = [_][2]f64{
        .{ oa.ux, oa.uy },
        .{ oa.vx, oa.vy },
        .{ ob.ux, ob.uy },
        .{ ob.vx, ob.vy },
    };
    for (axes) |ax| {
        const dist = @abs(dx * ax[0] + dy * ax[1]);
        const ra = oa.hu * @abs(oa.ux * ax[0] + oa.uy * ax[1]) + oa.hv * @abs(oa.vx * ax[0] + oa.vy * ax[1]);
        const rb = ob.hu * @abs(ob.ux * ax[0] + ob.uy * ax[1]) + ob.hv * @abs(ob.vx * ax[0] + ob.vy * ax[1]);
        if (dist + 2.0 >= ra + rb) return false;
    }
    return true;
}

/// Gate 2: Deterministic geometric collision (incl. rotated OBB SAT & vertical overlap), non-ASCII/polygon clip-path slicing,
/// trim overflow, left/center/right orphan-headline & texture-energy audit.
pub fn auditGeometry(
    alloc: std.mem.Allocator,
    io: std.Io,
    pdf_path: []const u8,
    pages: []const mupdf.PageData,
    max_bg_rms: f64,
    tmp_tag: []const u8,
) !GeometryReport {
    const bg_pdf = try mupdf.makeBackgroundOnlyPdf(alloc, io, pdf_path, tmp_tag);
    defer mupdf.removeTmpBestEffort(io, bg_pdf);
    const unclip_pdf = mupdf.makeUnclippedPdf(alloc, io, pdf_path, tmp_tag) catch null;
    defer if (unclip_pdf) |up| mupdf.removeTmpBestEffort(io, up);
    const unclip_pages: ?[]mupdf.PageData = if (unclip_pdf) |up| (mupdf.extractPages(alloc, io, up) catch null) else null;

    var issues: std.ArrayList(GeometryIssue) = .empty;
    var tot_spans: usize = 0;
    var tot_coll: usize = 0;
    var tot_clipped: usize = 0;
    var tot_over: usize = 0;
    var tot_orph: usize = 0;
    var tot_noisy: usize = 0;
    var worst_rms: f64 = 0.0;

    for (pages, 0..) |pg, pg_idx| {
        tot_spans += pg.spans.len;

        // 0. PDF `W n` / `W* n` clip-path character slicing check (full UTF-8 printable codepoints + dynamic trace polygons)
        var missing_chars: usize = pg.trace_clipped_chars;
        if (unclip_pages) |upgs| {
            if (pg_idx < upgs.len) {
                var vis_freq = try countUtf8PrintableFreq(alloc, pg.spans, pg.width, pg.height, false);
                var raw_freq = try countUtf8PrintableFreq(alloc, upgs[pg_idx].spans, pg.width, pg.height, true);
                var stext_missing: usize = 0;
                var rit = raw_freq.iterator();
                while (rit.next()) |ent| {
                    const vis_c = vis_freq.get(ent.key_ptr.*) orelse 0;
                    if (ent.value_ptr.* > vis_c) stext_missing += (ent.value_ptr.* - vis_c);
                }
                if (stext_missing > missing_chars) missing_chars = stext_missing;
            }
        }
        if (missing_chars > 0) {
            tot_clipped += 1;
            try issues.append(alloc, .{
                .page = pg.page_num,
                .kind = "clip_path_sliced_text",
                .detail = try std.fmt.allocPrint(alloc, "{d} printable character(s) sliced by W/W* clip path", .{missing_chars}),
            });
        }

        // 1. Pairwise collisions: aligned p2zig kernel + tight vertical overlap + cross-angle OBB SAT
        for (pg.spans, 0..) |a, i| {
            const ax0 = mupdf.checkedRoundInt(i64, a.x0 * 10.0, -1.0e9, 1.0e9) catch 0;
            const ay0 = mupdf.checkedRoundInt(i64, a.y0 * 10.0, -1.0e9, 1.0e9) catch 0;
            const ax1 = mupdf.checkedRoundInt(i64, a.x1 * 10.0, -1.0e9, 1.0e9) catch 0;
            const ay1 = mupdf.checkedRoundInt(i64, a.y1 * 10.0, -1.0e9, 1.0e9) catch 0;
            var j: usize = i + 1;
            while (j < pg.spans.len) : (j += 1) {
                const b = pg.spans[j];
                const same_dir = (@abs(a.dir_x - b.dir_x) <= 0.05 and @abs(a.dir_y - b.dir_y) <= 0.05);
                var kind: i64 = 0;
                if (same_dir) {
                    const same_line = (a.block_idx == b.block_idx and a.line_idx == b.line_idx);
                    const bx0 = mupdf.checkedRoundInt(i64, b.x0 * 10.0, -1.0e9, 1.0e9) catch 0;
                    const by0 = mupdf.checkedRoundInt(i64, b.y0 * 10.0, -1.0e9, 1.0e9) catch 0;
                    const bx1 = mupdf.checkedRoundInt(i64, b.x1 * 10.0, -1.0e9, 1.0e9) catch 0;
                    const by1 = mupdf.checkedRoundInt(i64, b.y1 * 10.0, -1.0e9, 1.0e9) catch 0;
                    kind = kernels.span_collision_kind(ax0, ay0, ax1, ay1, bx0, by0, bx1, by1, same_line);
                    // Close vertical padding deadzone on cross-line horizontal crashes (e.g. 6pt spacing on 10pt font)
                    if (kind == 0 and !same_line and @abs(a.dir_y) < 0.05) {
                        const iw = @min(a.x1, b.x1) - @max(a.x0, b.x0);
                        const ih = @min(a.y1, b.y1) - @max(a.y0, b.y0);
                        const min_h = @min(a.y1 - a.y0, b.y1 - b.y0);
                        if (iw > 5.0 and min_h >= 6.0 and ih > min_h * 0.42) {
                            kind = 2;
                        }
                    }
                } else if (obbSatOverlaps(a, b)) {
                    kind = 3;
                }
                if (kind != 0) {
                    tot_coll += 1;
                    const d = try std.fmt.allocPrint(alloc, "'{s}' vs '{s}'", .{
                        a.text[0..@min(a.text.len, 28)],
                        b.text[0..@min(b.text.len, 28)],
                    });
                    try issues.append(alloc, .{
                        .page = pg.page_num,
                        .kind = if (kind == 1) "same_line_overlap" else if (kind == 3) "rotated_overlap" else "cross_line_overlap",
                        .detail = d,
                    });
                }
            }
        }

        // 2. Trim-box boundary overflow
        const eps: f64 = 1.5;
        for (pg.spans) |sp| {
            if (sp.x0 < -eps or sp.y0 < -eps or sp.x1 > pg.width + eps or sp.y1 > pg.height + eps) {
                tot_over += 1;
                try issues.append(alloc, .{
                    .page = pg.page_num,
                    .kind = "trim_overflow",
                    .detail = try alloc.dupe(u8, sp.text[0..@min(sp.text.len, 40)]),
                });
            }
        }

        // 3. Wide-headline 1-word orphan wrap via p2zig kernel (left, centered & right-aligned blocks)
        var h_lines: std.ArrayList(HeadLine) = .empty;
        for (pg.spans) |sp| {
            if (sp.size < 20.0 or @abs(sp.dir_x - 1.0) > 0.05 or @abs(sp.dir_y) > 0.05) continue;
            const yc = (sp.y0 + sp.y1) * 0.5;
            if (h_lines.items.len > 0) {
                var last = &h_lines.items[h_lines.items.len - 1];
                if (@abs(yc - last.yc) < sp.size * 0.45 and @abs(sp.size - last.size) < 2.0) {
                    last.text = try std.fmt.allocPrint(alloc, "{s} {s}", .{ last.text, sp.text });
                    last.x0 = @min(last.x0, sp.x0);
                    last.x1 = @max(last.x1, sp.x1);
                    last.y0 = @min(last.y0, sp.y0);
                    last.y1 = @max(last.y1, sp.y1);
                    continue;
                }
            }
            try h_lines.append(alloc, .{
                .text = sp.text,
                .size = sp.size,
                .x0 = sp.x0,
                .x1 = sp.x1,
                .y0 = sp.y0,
                .y1 = sp.y1,
                .yc = yc,
            });
        }
        var hl_i: usize = 0;
        while (hl_i < h_lines.items.len) {
            var blk_end = hl_i + 1;
            while (blk_end < h_lines.items.len) : (blk_end += 1) {
                const prev = h_lines.items[blk_end - 1];
                const cur = h_lines.items[blk_end];
                const v_gap = cur.y0 - prev.y1;
                const prev_xc = 0.5 * (prev.x0 + prev.x1);
                const cur_xc = 0.5 * (cur.x0 + cur.x1);
                const aligned = (@abs(cur.x0 - prev.x0) < 45.0) or (@abs(cur_xc - prev_xc) < 35.0) or (@abs(cur.x1 - prev.x1) < 45.0);
                if (v_gap >= -4.0 and v_gap <= prev.size * 0.65 and aligned and @abs(cur.size - prev.size) < 2.0) {
                    continue;
                }
                break;
            }
            if (blk_end - hl_i >= 2) {
                const first_ln = h_lines.items[hl_i];
                const last_ln = h_lines.items[blk_end - 1];
                const w0_x10 = mupdf.checkedRoundInt(i64, (first_ln.x1 - first_ln.x0) * 10.0, 0.0, 1.0e8) catch 0;
                const wl_x10 = mupdf.checkedRoundInt(i64, (last_ln.x1 - last_ln.x0) * 10.0, 0.0, 1.0e8) catch 0;
                const wc = countAlphaWords(last_ln.text);
                if (kernels.is_orphan_headline(w0_x10, wl_x10, wc.count, wc.first_len)) {
                    tot_orph += 1;
                    try issues.append(alloc, .{
                        .page = pg.page_num,
                        .kind = "headline_orphan",
                        .detail = try alloc.dupe(u8, last_ln.text[0..@min(last_ln.text.len, 40)]),
                    });
                }
            }
            hl_i = blk_end;
        }

        // 4. Background photo-overlay Sobel texture RMS
        const bg_ppm = try mupdf.renderPagePpm(alloc, io, bg_pdf, pg.page_num, 72, tmp_tag);
        const pw = bg_ppm.width;
        const ph = bg_ppm.height;
        if (pw >= 4 and ph >= 4) {
            for (pg.spans) |sp| {
                if (sp.size >= 22.0 or sp.text.len <= 2) continue;
                const ix0: usize = @intFromFloat(std.math.clamp(@round(sp.x0), 1.0, @as(f64, @floatFromInt(pw - 2))));
                const ix1: usize = @max(ix0 + 1, @as(usize, @intFromFloat(std.math.clamp(@round(sp.x1), 1.0, @as(f64, @floatFromInt(pw - 1))))));
                const iy0: usize = @intFromFloat(std.math.clamp(@round(sp.y0), 1.0, @as(f64, @floatFromInt(ph - 2))));
                const iy1: usize = @max(iy0 + 1, @as(usize, @intFromFloat(std.math.clamp(@round(sp.y1), 1.0, @as(f64, @floatFromInt(ph - 1))))));
                if (ix1 - ix0 < 6 or iy1 - iy0 < 4) continue;

                var sq_sum: f64 = 0.0;
                var cnt: usize = 0;
                const sx = @max(@as(usize, 1), (ix1 - ix0) / 16);
                const sy = @max(@as(usize, 1), (iy1 - iy0) / 6);
                var py = iy0;
                while (py < iy1) : (py += sy) {
                    var px = ix0;
                    while (px < ix1) : (px += sx) {
                        const gx = lumaAt(bg_ppm, px + 1, py) - lumaAt(bg_ppm, px - 1, py);
                        const gy = lumaAt(bg_ppm, px, py + 1) - lumaAt(bg_ppm, px, py - 1);
                        sq_sum += (gx * gx + gy * gy) * 0.25;
                        cnt += 1;
                    }
                }
                if (cnt == 0) continue;
                const rms = @sqrt(sq_sum / @as(f64, @floatFromInt(cnt)));
                if (rms > worst_rms) worst_rms = rms;
                if (rms > max_bg_rms) {
                    tot_noisy += 1;
                    const d = try std.fmt.allocPrint(alloc, "rms={d:.1} '{s}'", .{ rms, sp.text[0..@min(sp.text.len, 32)] });
                    try issues.append(alloc, .{ .page = pg.page_num, .kind = "noisy_overlay", .detail = d });
                }
            }
        }
    }

    return .{
        .pages = pages.len,
        .total_spans = tot_spans,
        .collisions = tot_coll,
        .clipped = tot_clipped,
        .trim_overflow = tot_over,
        .headline_orphans = tot_orph,
        .noisy_overlays = tot_noisy,
        .worst_rms = worst_rms,
        .passed = (tot_coll == 0 and tot_clipped == 0 and tot_over == 0 and tot_orph == 0 and tot_noisy == 0),
        .issues = try issues.toOwnedSlice(alloc),
    };
}

/// Parse 1-based page specification like "1,4-9" into a boolean lookup slice (index 1..=page_count).
/// Fails closed on malformed tokens, reversed ranges, out-of-range page numbers, or zero selected pages.
pub fn parsePageSpec(alloc: std.mem.Allocator, spec: ?[]const u8, page_count: usize) ![]bool {
    const mask = try alloc.alloc(bool, page_count + 1);
    if (spec == null or spec.?.len == 0) {
        @memset(mask, true);
        mask[0] = false;
        return mask;
    }
    @memset(mask, false);
    var selected: usize = 0;
    var it = std.mem.splitScalar(u8, spec.?, ',');
    while (it.next()) |raw_part| {
        const part = std.mem.trim(u8, raw_part, " \t");
        if (part.len == 0) return error.InvalidPageSpec;
        if (std.mem.findScalar(u8, part, '-')) |dash| {
            const a = std.fmt.parseInt(usize, part[0..dash], 10) catch return error.InvalidPageSpec;
            const b = std.fmt.parseInt(usize, part[dash + 1 ..], 10) catch return error.InvalidPageSpec;
            if (a == 0 or b == 0 or a > b or b > page_count) return error.InvalidPageSpec;
            var p = a;
            while (p <= b) : (p += 1) {
                mask[p] = true;
                selected += 1;
            }
        } else {
            const p = std.fmt.parseInt(usize, part, 10) catch return error.InvalidPageSpec;
            if (p == 0 or p > page_count) return error.InvalidPageSpec;
            mask[p] = true;
            selected += 1;
        }
    }
    if (selected == 0) return error.InvalidPageSpec;
    return mask;
}

/// Gate 3B: Exact clip-aware dual-key pixel-diff visible photography coverage (defeats raw rect inflation,
/// 100% blank-white plates, 1%-opacity ghost images, 1pt-inset fake bleed, and 2px edge double-counting).
pub fn auditCoverage(
    alloc: std.mem.Allocator,
    io: std.Io,
    pdf_path: []const u8,
    page_count: usize,
    min_pct: f64,
    min_bleed_edges: i64,
    page_spec: ?[]const u8,
    tmp_tag: []const u8,
) !CoverageReport {
    var failures: std.ArrayList([]const u8) = .empty;
    const mask = parsePageSpec(alloc, page_spec, page_count) catch {
        try failures.append(alloc, try std.fmt.allocPrint(alloc, "Invalid or out-of-range --pages specification '{s}' (document has {d} pages)", .{ page_spec orelse "", page_count }));
        return .{
            .pages = page_count,
            .enforced_count = 0,
            .min_visible_pct = 0.0,
            .avg_visible_pct = 0.0,
            .failures = try failures.toOwnedSlice(alloc),
            .page_reports = &.{},
            .passed = false,
        };
    };
    const dk = try mupdf.makeDualKeyPdfs(alloc, io, pdf_path, tmp_tag);
    defer mupdf.removeTmpBestEffort(io, dk.pdf_a);
    defer mupdf.removeTmpBestEffort(io, dk.pdf_b);

    var reports: std.ArrayList(PageCoverage) = .empty;
    const min_pct_x10 = try mupdf.checkedRoundInt(i64, min_pct * 10.0, 0.0, 1000.0);

    var min_vis: f64 = 100.0;
    var sum_vis: f64 = 0.0;
    var enf_cnt: usize = 0;

    var pg: usize = 1;
    while (pg <= page_count) : (pg += 1) {
        const enforced = mask[pg];
        var pct: f64 = 0.0;
        var b_edges: i64 = 0;
        var ok = true;

        if (dk.replaced_images > 0) {
            const pa = try mupdf.renderPagePpm(alloc, io, dk.pdf_a, pg, 72, tmp_tag);
            const pb = try mupdf.renderPagePpm(alloc, io, dk.pdf_b, pg, 72, tmp_tag);
            const po = try mupdf.renderPagePpm(alloc, io, pdf_path, pg, 72, tmp_tag);
            const w = @min(po.width, @min(pa.width, pb.width));
            const h = @min(po.height, @min(pa.height, pb.height));
            const total_px: i64 = @intCast(w * h);
            var changed: i64 = 0;
            var non_uniform_px: i64 = 0;
            var first_orig_set = false;
            var first_orig: mupdf.Rgb = .{ .r = 255, .g = 255, .b = 255 };
            var l_px: i64 = 0;
            var r_px: i64 = 0;
            var t_px: i64 = 0;
            var b_px: i64 = 0;

            var y: usize = 0;
            while (y < h) : (y += 1) {
                var x: usize = 0;
                while (x < w) : (x += 1) {
                    const ca = pa.pixelAt(x, y);
                    const cb = pb.pixelAt(x, y);
                    // Require strong dual-key delta (>= 128 L1 out of 765) to defeat `/ca 0.01` ghost plates
                    if (pixelL1(ca, cb) >= 128) {
                        const co = po.pixelAt(x, y);
                        if (!first_orig_set) {
                            first_orig = co;
                            first_orig_set = true;
                        }
                        if (pixelL1(co, first_orig) >= 12) non_uniform_px += 1;
                        changed += 1;
                        // Strict 1-pixel physical perimeter bleed (defeats 1pt-inset fake bleed & 2px edge double-counting)
                        if (x == 0) l_px += 1;
                        if (x + 1 == w) r_px += 1;
                        if (y == 0) t_px += 1;
                        if (y + 1 == h) b_px += 1;
                    }
                }
            }
            const is_flat_blank = (changed > 0 and non_uniform_px * 100 < changed);
            if (total_px > 0) {
                pct = (@as(f64, @floatFromInt(changed)) / @as(f64, @floatFromInt(total_px))) * 100.0;
            }
            b_edges = kernels.bleed_edge_count(l_px, r_px, t_px, b_px, @intCast(w), @intCast(h));
            if (enforced) {
                ok = (!is_flat_blank) and kernels.coverage_passes(changed, total_px, min_pct_x10, b_edges, min_bleed_edges);
                if (is_flat_blank) {
                    try failures.append(alloc, try std.fmt.allocPrint(alloc, "Page {d}: visible photo {d:.1}% is a flat/blank zero-texture plate (rejected)", .{ pg, pct }));
                }
            }
        } else if (enforced) {
            ok = (min_pct <= 0.0 and min_bleed_edges <= 0);
        }

        if (enforced) {
            enf_cnt += 1;
            if (pct < min_vis) min_vis = pct;
            sum_vis += pct;
            if (!ok and !(dk.replaced_images > 0 and failures.items.len > 0 and std.mem.find(u8, failures.items[failures.items.len - 1], "flat/blank") != null)) {
                try failures.append(alloc, try std.fmt.allocPrint(alloc, "Page {d}: visible photo {d:.1}% (min {d:.1}%), bleed edges {d} (min {d})", .{
                    pg, pct, min_pct, b_edges, min_bleed_edges,
                }));
            }
        }
        try reports.append(alloc, .{
            .page = pg,
            .enforced = enforced,
            .visible_pct = pct,
            .bleed_edges = b_edges,
            .passed = ok,
        });
    }

    const flist = try failures.toOwnedSlice(alloc);
    return .{
        .pages = page_count,
        .enforced_count = enf_cnt,
        .min_visible_pct = if (enf_cnt > 0) min_vis else 0.0,
        .avg_visible_pct = if (enf_cnt > 0) sum_vis / @as(f64, @floatFromInt(enf_cnt)) else 0.0,
        .failures = flist,
        .page_reports = try reports.toOwnedSlice(alloc),
        .passed = flist.len == 0,
    };
}

const SKIP_JSON_KEYS = [_][]const u8{
    "sampled_coordinates",
    "lat",
    "lon",
    "width_pt",
    "height_pt",
    "bbox",
    "raw_newick_sha256",
    "decimal_dates",
    "average_ppm",
    "deseasonalized_ppm",
    "co2_series_2000_2024",
    "ci_series_2000_2024",
};

fn isSkipJsonKey(k: []const u8) bool {
    for (SKIP_JSON_KEYS) |sk| {
        if (std.mem.eql(u8, k, sk)) return true;
    }
    return false;
}

fn addExactFloat(alloc: std.mem.Allocator, seen: *std.AutoHashMap(u64, void), out: *std.ArrayList(f64), val: f64) !void {
    if (!std.math.isFinite(val)) return;
    const norm_v: f64 = if (val == 0.0) 0.0 else val;
    const bits: u64 = @bitCast(norm_v);
    if (!seen.contains(bits)) {
        try seen.put(bits, {});
        try out.append(alloc, norm_v);
    }
}

fn jsonToFloat(v: std.json.Value) ?f64 {
    return switch (v) {
        .integer => |iv| @floatFromInt(iv),
        .float => |fv| fv,
        else => null,
    };
}

/// Mirror Python `_derive_exact_ratios`: register exact percentages derived from species/country counts
/// and explicit Botanica phenology totals (without polluting the pool with arbitrary axis/year array sums).
fn deriveExactSpeciesRatios(alloc: std.mem.Allocator, summary: std.json.Value, seen: *std.AutoHashMap(u64, void), out: *std.ArrayList(f64)) !void {
    if (summary != .object) return;
    const sp_val = summary.object.get("species") orelse return;
    if (sp_val != .array) return;
    for (sp_val.array.items) |sp| {
        if (sp != .object) continue;
        if (sp.object.get("gbif_total_occurrences")) |tot_v| {
            if (jsonToFloat(tot_v)) |tot| {
                if (tot > 0.0) {
                    if (sp.object.get("top_countries")) |tc_val| {
                        if (tc_val == .array) {
                            for (tc_val.array.items) |c| {
                                if (c != .object) continue;
                                const cnt = jsonToFloat(c.object.get("count") orelse continue) orelse continue;
                                const pct = (cnt / tot) * 100.0;
                                try addExactFloat(alloc, seen, out, pct);
                            }
                        }
                    }
                }
            }
        }
        // Explicit per-taxon sampled coordinate count (Botanica GBIF map sample size, e.g. 120)
        if (sp.object.get("sampled_coordinates")) |sc| {
            if (sc == .array and sc.array.items.len > 0) {
                try addExactFloat(alloc, seen, out, @floatFromInt(sc.array.items.len));
            }
        }
        // Explicit Botanica phenology totals & peak consecutive-pair share (scoped strictly to `species[].inat_monthly_flowering`)
        if (sp.object.get("inat_monthly_flowering")) |mf| {
            if (mf == .array and mf.array.items.len == 12) {
                var sum_v: f64 = 0.0;
                var vals: [12]f64 = @splat(0.0);
                for (mf.array.items, 0..) |it, idx| {
                    const fv = jsonToFloat(it) orelse 0.0;
                    vals[idx] = fv;
                    sum_v += fv;
                }
                if (sum_v > 0.0) {
                    try addExactFloat(alloc, seen, out, sum_v);
                    var best_pair: f64 = 0.0;
                    for (0..11) |i| {
                        const pair = vals[i] + vals[i + 1];
                        if (pair > best_pair) best_pair = pair;
                    }
                    try addExactFloat(alloc, seen, out, best_pair);
                    try addExactFloat(alloc, seen, out, (best_pair / sum_v) * 100.0);
                }
            }
        }
    }
}

/// Mirror Python `_load_authorized_numbers` for `background_citations.json`: register ONLY explicit
/// `citations[].values[]` / `citations[].value` exact scalars (never synthetic pairwise sums or pre-rounding).
fn collectCitationNumbers(alloc: std.mem.Allocator, parsed: std.json.Value, seen: *std.AutoHashMap(u64, void), out: *std.ArrayList(f64)) !void {
    const entries: []const std.json.Value = switch (parsed) {
        .object => |obj| if (obj.get("citations")) |cv| (if (cv == .array) cv.array.items else &.{}) else &.{},
        .array => |arr| arr.items,
        else => &.{},
    };
    for (entries) |entry| {
        if (entry != .object) continue;
        if (entry.object.get("values")) |vv| {
            if (vv == .array) {
                for (vv.array.items) |item| {
                    if (jsonToFloat(item)) |fv| try addExactFloat(alloc, seen, out, fv);
                }
            }
        }
        if (entry.object.get("value")) |v1| {
            if (jsonToFloat(v1)) |fv| try addExactFloat(alloc, seen, out, fv);
        }
    }
}

/// Collect ONLY literal JSON numbers (zero synthetic array sums / pairwise sums — defeats `chart_axis_ticks` & `panel_years` pollution).
fn collectJsonNumbers(alloc: std.mem.Allocator, val: std.json.Value, seen: *std.AutoHashMap(u64, void), out: *std.ArrayList(f64)) !void {
    switch (val) {
        .integer => |iv| try addExactFloat(alloc, seen, out, @floatFromInt(iv)),
        .float => |fv| try addExactFloat(alloc, seen, out, fv),
        .object => |obj| {
            var it = obj.iterator();
            while (it.next()) |entry| {
                if (isSkipJsonKey(entry.key_ptr.*)) continue;
                try collectJsonNumbers(alloc, entry.value_ptr.*, seen, out);
            }
        },
        .array => |arr| {
            for (arr.items) |it| {
                try collectJsonNumbers(alloc, it, seen, out);
            }
        },
        else => {},
    }
}

/// Precision-aware half-ULP Rule 10 grounding check (full IEEE-754 f64, zero coarse ±0.051 catch-all).
pub fn rule10IsGrounded(val: f64, decimals: u8, sci_exp: ?i32, bare_power: bool, authorized: []const f64) bool {
    if (!std.math.isFinite(val)) return false;
    if (bare_power) {
        const eps = @max(@as(f64, 1e-30), @abs(val) * 1e-9);
        for (authorized) |a| {
            if (@abs(a - val) <= eps) return true;
        }
        return false;
    }
    if (sci_exp) |ev| {
        const pow_i: f64 = @floatFromInt(ev - @as(i32, decimals));
        const half_ulp = 0.5 * std.math.pow(f64, 10.0, pow_i);
        const eps = @max(@as(f64, 1e-30), @abs(val) * 1e-12);
        for (authorized) |a| {
            if (@abs(a - val) <= half_ulp + eps) return true;
        }
        return false;
    }
    const half_ulp = 0.5 * std.math.pow(f64, 10.0, -@as(f64, @floatFromInt(decimals)));
    const eps = @max(@as(f64, 1e-12), @abs(val) * 1e-12);
    for (authorized) |a| {
        if (@abs(a - val) <= half_ulp + eps) return true;
    }
    return false;
}

fn isHexDigit(ch: u8) bool {
    return (ch >= '0' and ch <= '9') or (ch >= 'a' and ch <= 'f') or (ch >= 'A' and ch <= 'F');
}

fn isUrlOrDoiChar(ch: u8) bool {
    return ch > 32 and ch != ')' and ch != ']' and ch != ',' and ch != ';';
}

const SupChar = struct { ch: u8, len: usize };

fn decodeSupChar(s: []const u8) ?SupChar {
    if (s.len >= 2 and s[0] == 0xC2) {
        if (s[1] == 0xB9) return .{ .ch = '1', .len = 2 }; // ¹
        if (s[1] == 0xB2) return .{ .ch = '2', .len = 2 }; // ²
        if (s[1] == 0xB3) return .{ .ch = '3', .len = 2 }; // ³
    }
    if (s.len >= 3 and s[0] == 0xE2 and s[1] == 0x81) {
        if (s[2] == 0xB0) return .{ .ch = '0', .len = 3 }; // ⁰
        if (s[2] >= 0xB4 and s[2] <= 0xB9) return .{ .ch = '4' + (s[2] - 0xB4), .len = 3 }; // ⁴..⁹
        if (s[2] == 0xBA) return .{ .ch = '+', .len = 3 }; // ⁺
        if (s[2] == 0xBB) return .{ .ch = '-', .len = 3 }; // ⁻
    }
    return null;
}

fn isLetterOrMathAtEnd(buf: []const u8) bool {
    if (buf.len == 0) return false;
    const last = buf[buf.len - 1];
    if ((last >= 'A' and last <= 'Z') or (last >= 'a' and last <= 'z')) return true;
    // Greek U+0370..U+03FF: 2-byte UTF-8 0xCD 0xB0..0xCF 0xBF
    if (buf.len >= 2 and (buf[buf.len - 2] == 0xCD or buf[buf.len - 2] == 0xCE or buf[buf.len - 2] == 0xCF)) {
        return true;
    }
    // Unicode Mathematical Alphanumeric Symbols U+1D400..U+1D7FF: 4-byte UTF-8 0xF0 0x9D 0x90..0x9F ...
    if (buf.len >= 4 and buf[buf.len - 4] == 0xF0 and buf[buf.len - 3] == 0x9D and buf[buf.len - 2] >= 0x90 and buf[buf.len - 2] <= 0x9F) {
        return true;
    }
    return false;
}

fn isMathItalicBefore(s: []const u8, pos: usize) bool {
    if (pos < 4) return false;
    return s[pos - 4] == 0xF0 and s[pos - 3] == 0x9D and s[pos - 2] >= 0x90 and s[pos - 2] <= 0x9F;
}

fn matchSiUnitExp(raw: []const u8, i: usize) ?usize {
    const units = [_][]const u8{
        "day", "min", "mol", "yr", "cm", "mm", "km", "kg", "Hz", "Pa", "eV", "pc", "AU", "hr",
        "s",   "m",   "g",   "L",  "K",  "W",  "J",
    };
    const prev_ok = (i == 0) or !isAsciiAlnum(raw[i - 1]);
    if (!prev_ok) return null;
    for (units) |u| {
        if (!std.mem.startsWith(u8, raw[i..], u)) continue;
        var k = i + u.len;
        if (k < raw.len and isAsciiAlnum(raw[k])) continue;
        while (k < raw.len and (raw[k] == ' ' or raw[k] == '\t')) : (k += 1) {}
        if (k >= raw.len) continue;
        // Branch A: Unicode superscript [⁺⁻][⁰..⁹]+
        if (decodeSupChar(raw[k..])) |sc| {
            if (sc.ch == '+' or sc.ch == '-') {
                var p = k + sc.len;
                var digs: usize = 0;
                while (p < raw.len) {
                    const d = decodeSupChar(raw[p..]) orelse break;
                    if (d.ch < '0' or d.ch > '9') break;
                    digs += 1;
                    p += d.len;
                }
                if (digs > 0) return p;
            }
        }
        // Branch B: optional '^' then '-' or '−' then '1' at word boundary
        var p = k;
        if (p < raw.len and raw[p] == '^') p += 1;
        if (p < raw.len and raw[p] == '-') {
            p += 1;
        } else if (p + 2 < raw.len and raw[p] == 0xE2 and raw[p + 1] == 0x88 and raw[p + 2] == 0x92) {
            p += 3;
        } else continue;
        if (p < raw.len and raw[p] == '1') {
            const end = p + 1;
            if (end == raw.len or (!isAsciiAlnum(raw[end]) and raw[end] != '.')) return end;
        }
    }
    return null;
}

fn matchTrimDimPt(raw: []const u8, i: usize, page_w: f64, page_h: f64) ?usize {
    if (i > 0 and isAsciiAlnum(raw[i - 1])) return null;
    const pw: i64 = @intFromFloat(@round(page_w));
    const ph: i64 = @intFromFloat(@round(page_h));
    var wbuf: [24]u8 = undefined;
    var hbuf: [24]u8 = undefined;
    const ws = std.fmt.bufPrint(&wbuf, "{d}", .{pw}) catch return null;
    const hs = std.fmt.bufPrint(&hbuf, "{d}", .{ph}) catch return null;
    if (!std.mem.startsWith(u8, raw[i..], ws)) return null;
    var k = i + ws.len;
    while (k < raw.len and (raw[k] == ' ' or raw[k] == '\t')) : (k += 1) {}
    if (k + 1 < raw.len and raw[k] == 0xC3 and raw[k + 1] == 0x97) {
        k += 2; // '×'
    } else if (k < raw.len and (raw[k] == 'x' or raw[k] == 'X')) {
        k += 1;
    } else return null;
    while (k < raw.len and (raw[k] == ' ' or raw[k] == '\t')) : (k += 1) {}
    if (!std.mem.startsWith(u8, raw[k..], hs)) return null;
    k += hs.len;
    while (k < raw.len and (raw[k] == ' ' or raw[k] == '\t')) : (k += 1) {}
    if (!std.mem.startsWith(u8, raw[k..], "pt")) return null;
    k += 2;
    if (k < raw.len and isAsciiAlnum(raw[k])) return null;
    return k;
}

/// Normalize soft hyphens, zero-width invisibles, fullwidth digits, Unicode Mathematical Alphanumeric digits
/// (`U+1D7CE..U+1D7FF`), and Arabic-Indic digits; strip URLs, DOIs, genuine hex SHA-256 digests, bounded version
/// strings, SI unit exponents, letter-attached superscripts, and page trim dimension specs (`W × H pt`).
pub fn cleanProseText(alloc: std.mem.Allocator, raw_in: []const u8, page_w: f64, page_h: f64) ![]u8 {
    // Pass 1: UTF-8 codepoint normalization & invisible format-char stripping
    var norm: std.ArrayList(u8) = .empty;
    defer norm.deinit(alloc);
    try norm.ensureTotalCapacity(alloc, raw_in.len);
    var ni: usize = 0;
    while (ni < raw_in.len) {
        const b0 = raw_in[ni];
        if (b0 < 0x80) {
            try norm.append(alloc, b0);
            ni += 1;
            continue;
        }
        const seq_len = std.unicode.utf8ByteSequenceLength(b0) catch {
            try norm.append(alloc, b0);
            ni += 1;
            continue;
        };
        if (ni + seq_len > raw_in.len) {
            try norm.append(alloc, b0);
            ni += 1;
            continue;
        }
        const cp = std.unicode.utf8Decode(raw_in[ni .. ni + seq_len]) catch {
            try norm.append(alloc, b0);
            ni += 1;
            continue;
        };
        ni += seq_len;
        // Strip soft hyphen & zero-width format characters (defeats U+200B ZWSP digit-splitting)
        if (cp == 0x00AD or (cp >= 0x200B and cp <= 0x200F) or (cp >= 0x2060 and cp <= 0x2064) or cp == 0xFEFF) {
            continue;
        }
        // Normalize thin/narrow/NBSP spaces to ASCII space
        if (cp == 0x00A0 or cp == 0x2009 or cp == 0x202F or cp == 0x2007) {
            try norm.append(alloc, ' ');
            continue;
        }
        // Fullwidth ASCII digits & numeric punctuation
        if (cp >= 0xFF10 and cp <= 0xFF19) {
            try norm.append(alloc, @intCast('0' + (cp - 0xFF10)));
            continue;
        }
        if (cp == 0xFF0B) {
            try norm.append(alloc, '+');
            continue;
        }
        if (cp == 0xFF0D) {
            try norm.append(alloc, '-');
            continue;
        }
        if (cp == 0xFF0E) {
            try norm.append(alloc, '.');
            continue;
        }
        if (cp == 0xFF0C) {
            try norm.append(alloc, ',');
            continue;
        }
        if (cp == 0xFF05) {
            try norm.append(alloc, '%');
            continue;
        }
        // Unicode Mathematical Alphanumeric Digits U+1D7CE..U+1D7FF (Bold, Double-Struck, Sans, Sans-Bold, Mono)
        if (cp >= 0x1D7CE and cp <= 0x1D7FF) {
            try norm.append(alloc, @intCast('0' + ((cp - 0x1D7CE) % 10)));
            continue;
        }
        // Arabic-Indic digits U+0660..U+0669
        if (cp >= 0x0660 and cp <= 0x0669) {
            try norm.append(alloc, @intCast('0' + (cp - 0x0660)));
            continue;
        }
        try norm.appendSlice(alloc, raw_in[ni - seq_len .. ni]);
    }
    const raw = norm.items;

    var out: std.ArrayList(u8) = .empty;
    try out.ensureTotalCapacity(alloc, raw.len);
    var i: usize = 0;
    while (i < raw.len) {
        // Strip http:// or https://
        if (std.mem.startsWith(u8, raw[i..], "http://") or std.mem.startsWith(u8, raw[i..], "https://")) {
            while (i < raw.len and raw[i] > 32) : (i += 1) {}
            try out.append(alloc, ' ');
            continue;
        }
        // Strip doi: 10.xxxx/... or bare 10.xxxx/...
        if (i + 5 < raw.len and std.ascii.eqlIgnoreCase(raw[i .. i + 4], "doi:")) {
            i += 4;
            while (i < raw.len and (raw[i] == ' ' or raw[i] == '\t')) : (i += 1) {}
            while (i < raw.len and isUrlOrDoiChar(raw[i])) : (i += 1) {}
            try out.append(alloc, ' ');
            continue;
        }
        if (i + 7 < raw.len and std.mem.startsWith(u8, raw[i..], "10.") and raw[i + 3] >= '0' and raw[i + 3] <= '9') {
            var k = i + 3;
            while (k < raw.len and raw[k] >= '0' and raw[k] <= '9') : (k += 1) {}
            if (k - (i + 3) >= 4 and k < raw.len and raw[k] == '/') {
                while (k < raw.len and isUrlOrDoiChar(raw[k])) : (k += 1) {}
                i = k;
                try out.append(alloc, ' ');
                continue;
            }
        }
        // Strip SHA-256 / SHA256 / line-wrapped SHA-\n256 + optional hex digest (MUST contain [a-fA-F] so pure numbers aren't swallowed!)
        if (std.mem.startsWith(u8, raw[i..], "SHA")) {
            var k = i + 3;
            if (k < raw.len and raw[k] == '-') k += 1;
            while (k < raw.len and (raw[k] == ' ' or raw[k] == '\t' or raw[k] == '\n' or raw[k] == '\r')) : (k += 1) {}
            if (std.mem.startsWith(u8, raw[k..], "256")) {
                k += 3;
                var h_ws = k;
                while (h_ws < raw.len and (raw[h_ws] == ' ' or raw[h_ws] == '\t' or raw[h_ws] == ':')) : (h_ws += 1) {}
                var h = h_ws;
                var has_alpha = false;
                while (h < raw.len and isHexDigit(raw[h])) : (h += 1) {
                    if ((raw[h] >= 'a' and raw[h] <= 'f') or (raw[h] >= 'A' and raw[h] <= 'F')) has_alpha = true;
                }
                if (has_alpha and h - h_ws >= 6 and (h == raw.len or !isAsciiAlnum(raw[h]))) {
                    k = h;
                }
                i = k;
                try out.append(alloc, ' ');
                continue;
            }
        }
        // Strip standard/version tokens: PDF/UA-1, ISO 14289-1, WCAG 2.1, Typst 0.15.1, WeasyPrint 67.0, veraPDF 1.30
        const direct_prefixes = [_][]const u8{ "PDF/UA-", "term_id=" };
        var matched_pre = false;
        for (direct_prefixes) |pre| {
            if (std.mem.startsWith(u8, raw[i..], pre)) {
                var k = i + pre.len;
                while (k < raw.len and ((raw[k] >= '0' and raw[k] <= '9') or raw[k] == '.' or raw[k] == '-')) : (k += 1) {}
                if (k > i + pre.len) {
                    i = k;
                    try out.append(alloc, ' ');
                    matched_pre = true;
                    break;
                }
            }
        }
        if (!matched_pre) {
            const ws_prefixes = [_][]const u8{ "ISO", "WCAG", "Typst", "WeasyPrint", "veraPDF", "Zig", "vedit" };
            for (ws_prefixes) |pre| {
                if (std.mem.startsWith(u8, raw[i..], pre)) {
                    var k = i + pre.len;
                    const ws_start = k;
                    while (k < raw.len and (raw[k] == ' ' or raw[k] == '\t' or raw[k] == '\n' or raw[k] == '\r')) : (k += 1) {}
                    if (k > ws_start and k < raw.len) {
                        const is_iso = std.mem.eql(u8, pre, "ISO");
                        if (!is_iso and (raw[k] == 'v' or raw[k] == 'V') and k + 1 < raw.len and raw[k + 1] >= '0' and raw[k + 1] <= '9') {
                            k += 1;
                        }
                        if (raw[k] >= '0' and raw[k] <= '9') {
                            const vstart = k;
                            while (k < raw.len and raw[k] >= '0' and raw[k] <= '9') : (k += 1) {}
                            const major_digits = k - vstart;
                            const major_val = std.fmt.parseInt(usize, raw[vstart..k], 10) catch 999999;
                            // Reject inflated/fabricated decimals like `ISO 999999.99` (ISO standards are integer/hyphenated <= 99999; software versions have major <= 200)
                            const valid_ver = if (is_iso)
                                (major_digits >= 3 and major_digits <= 5 and major_val <= 99999 and (k >= raw.len or raw[k] != '.'))
                            else
                                (major_digits <= 3 and major_val <= 200);
                            if (valid_ver) {
                                while (k < raw.len and ((raw[k] >= '0' and raw[k] <= '9') or raw[k] == '.' or raw[k] == '-')) : (k += 1) {}
                                i = k;
                                try out.append(alloc, ' ');
                                matched_pre = true;
                                break;
                            }
                        }
                    }
                }
            }
        }
        if (matched_pre) continue;

        // Strip SI unit reciprocal/power exponents (e.g. yr⁻¹, yr −1, cm⁻³)
        if (matchSiUnitExp(raw, i)) |end_si| {
            i = end_si;
            try out.append(alloc, ' ');
            continue;
        }

        // Strip page trim spec matching `W × H pt`
        if (matchTrimDimPt(raw, i, page_w, page_h)) |end_trim| {
            i = end_trim;
            try out.append(alloc, ' ');
            continue;
        }

        // Strip Unicode superscripts attached directly to a letter/Greek/math symbol (e.g. m², Σ², cm³)
        if (isLetterOrMathAtEnd(out.items)) {
            if (decodeSupChar(raw[i..])) |sc| {
                var k = i + sc.len;
                while (k < raw.len) {
                    const nxt = decodeSupChar(raw[k..]) orelse break;
                    if (nxt.ch < '0' or nxt.ch > '9') break;
                    k += nxt.len;
                }
                i = k;
                try out.append(alloc, ' ');
                continue;
            }
        }

        // Strip lowercase 8..64 char hex hashes (must contain at least one [a-f] so pure digits never strip)
        const prev_bound = (i == 0) or !isAsciiAlnum(raw[i - 1]);
        if (prev_bound and ((raw[i] >= '0' and raw[i] <= '9') or (raw[i] >= 'a' and raw[i] <= 'f'))) {
            var k = i;
            var has_hex_alpha = false;
            while (k < raw.len and ((raw[k] >= '0' and raw[k] <= '9') or (raw[k] >= 'a' and raw[k] <= 'f'))) : (k += 1) {
                if (raw[k] >= 'a' and raw[k] <= 'f') has_hex_alpha = true;
            }
            const next_bound = (k == raw.len) or !isAsciiAlnum(raw[k]);
            if (next_bound and has_hex_alpha and (k - i) >= 8 and (k - i) <= 64) {
                i = k;
                try out.append(alloc, ' ');
                continue;
            }
        }
        try out.append(alloc, raw[i]);
        i += 1;
    }
    return out.toOwnedSlice(alloc);
}

fn isTokenPrevBlocked(ch: u8) bool {
    return isAsciiAlnum(ch) or ch == '_';
}

/// Smart hyphen guard before a number at `pos` (`cleaned[pos - 1] == '-'`):
/// Preserves ISO dates (`1958-03`, `2026-10`), year spans (`2020-25`), ISSNs (`0031-9007`), PRL article IDs
/// (`014101-1`), and identifier codes (`TOI-700`, `Yoshida-4`, `BY-4.0`, `X-1`), while UNBLOCKING
/// numeric ranges (`64,896-999999`) and percent/currency targets (`non-99%`, `pre-$50`).
fn isHyphenIdentifierBefore(cleaned: []const u8, pos: usize, num_end: usize, has_pct: bool) bool {
    if (pos == 0 or cleaned[pos - 1] != '-') return false;
    if (has_pct) return false; // `non-99%` MUST be checked!
    if (pos < 2) return false;
    const before_hyphen = cleaned[pos - 2];
    // Letter-hyphen-number identifier: `BY-4.0`, `TOI-700`, `Yoshida-4`, `X-1`, `K2-18`, `EM-3`, `OECD-5`, `degree-4`
    if ((before_hyphen >= 'A' and before_hyphen <= 'Z') or (before_hyphen >= 'a' and before_hyphen <= 'z')) {
        return true;
    }
    if (before_hyphen >= '0' and before_hyphen <= '9') {
        // Check left token before `-`
        var ls = pos - 1;
        var has_comma_left = false;
        while (ls > 0 and ((cleaned[ls - 1] >= '0' and cleaned[ls - 1] <= '9') or cleaned[ls - 1] == ',')) : (ls -= 1) {
            if (cleaned[ls - 1] == ',') has_comma_left = true;
        }
        // Also check alphanumeric model prefix like `K2-18` (letter immediately before digit)
        if (ls > 0 and ((cleaned[ls - 1] >= 'A' and cleaned[ls - 1] <= 'Z') or (cleaned[ls - 1] >= 'a' and cleaned[ls - 1] <= 'z'))) {
            return true;
        }
        if (has_comma_left) return false; // `64,896-999999` -> NOT an identifier!
        const left_tok = cleaned[ls .. pos - 1];
        const right_tok = cleaned[pos..num_end];
        if (std.mem.findScalar(u8, right_tok, '.') != null or std.mem.findScalar(u8, right_tok, ',') != null) return false;
        // ISO YYYY-MM or YYYY-YY (`1958-03`, `2026-10`, `2020-25`)
        if (left_tok.len == 4 and right_tok.len == 2) {
            const yr = std.fmt.parseInt(usize, left_tok, 10) catch 0;
            if (yr >= 1900 and yr <= 2100) return true;
        }
        // ISSN `NNNN-NNNN` (e.g. `0031-9007`) or 5-digit ISBN/ID block (`90088-9`)
        if (left_tok.len == 4 and right_tok.len == 4) return true;
        if (left_tok.len == 5 and right_tok.len == 1) return true;
        // PRL 6-digit article page suffix (`014101-1`)
        if (left_tok.len == 6 and right_tok.len <= 2) return true;
    }
    return false;
}

fn isIdentFollow(ch: u8) bool {
    return isAsciiAlnum(ch) or ch == '_';
}

const SuffixMatch = struct {
    len: usize,
    scale: f64,
};

/// Unit-aware suffix parser: checks numbers attached directly to editorial magnitude/SI units
/// (`$99.9B`, `4.21M`, `2.81x`, `450ppm`, `9.9e9m`, `100d`) while safely ignoring decades (`'60s`, `1960s`),
/// English ordinals (`17th`, `1st`, `2nd`, `3rd`), and alphanumeric catalog IDs (`67P`, `M87`, `CO2`, `J0740`).
fn matchAllowedNumericSuffix(cleaned: []const u8, pos: usize, num_start: usize, raw_num: []const u8) ?SuffixMatch {
    if (pos >= cleaned.len or !isIdentFollow(cleaned[pos])) return .{ .len = 0, .scale = 1.0 };
    // Never treat `'60s` or `1960s` decade suffixes as seconds
    if (cleaned[pos] == 's' and (pos + 1 == cleaned.len or !isIdentFollow(cleaned[pos + 1]))) {
        if (num_start > 0 and (cleaned[num_start - 1] == '\'' or (num_start >= 3 and cleaned[num_start - 3] == 0xE2 and cleaned[num_start - 2] == 0x80 and cleaned[num_start - 1] == 0x99))) {
            return null;
        }
        if (raw_num.len == 4 and raw_num[3] == '0') {
            const yr = std.fmt.parseInt(usize, raw_num, 10) catch 0;
            if (yr >= 1800 and yr <= 2100) return null;
        }
    }
    // Magnitude multipliers (check either raw or scaled value)
    const mag_table = [_]struct { s: []const u8, sc: f64 }{
        .{ .s = "T", .sc = 1e12 },
        .{ .s = "B", .sc = 1e9 },
        .{ .s = "M", .sc = 1e6 },
        .{ .s = "K", .sc = 1e3 },
        .{ .s = "k", .sc = 1e3 },
    };
    for (mag_table) |mt| {
        if (std.mem.startsWith(u8, cleaned[pos..], mt.s)) {
            const end = pos + mt.s.len;
            if (end == cleaned.len or !isIdentFollow(cleaned[end])) {
                return .{ .len = mt.s.len, .scale = mt.sc };
            }
        }
    }
    // Explicit SI & financial/editorial unit suffixes (longest first; deliberately excludes st/nd/rd/th ordinals & P/a/b/c IDs)
    const unit_table = [_][]const u8{
        "ppm", "ppb", "bps", "pct", "yrs", "hrs", "min", "kHz", "MHz", "GHz",
        "kPa", "MPa", "GPa", "keV", "MeV", "GeV", "TeV", "kpc", "Mpc", "km",
        "kg",  "cm",  "mm",  "um",  "nm",  "ms",  "us",  "ns",  "MW",  "GW",
        "TW",  "kW",  "Gt",  "Mt",  "kt",  "Hz",  "dB",  "yr",  "hr",  "bp",
        "pt",  "px",  "in",  "ft",  "mi",  "lb",  "oz",  "mL",  "Pa",  "eV",
        "AU",  "pc",  "ly",  "x",   "X",   "g",   "m",   "W",   "J",   "C",
        "F",   "d",   "s",   "L",
    };
    for (unit_table) |u| {
        if (std.mem.startsWith(u8, cleaned[pos..], u)) {
            const end = pos + u.len;
            if (end == cleaned.len or !isIdentFollow(cleaned[end])) {
                return .{ .len = u.len, .scale = 1.0 };
            }
        }
    }
    return null;
}

fn matchUnarySignAt(cleaned: []const u8, i: usize) ?struct { neg: bool, next_pos: usize } {
    if (i >= cleaned.len) return null;
    if (cleaned[i] == '+') {
        if (i + 1 < cleaned.len and ((cleaned[i + 1] >= '0' and cleaned[i + 1] <= '9') or
            (cleaned[i + 1] == '.' and i + 2 < cleaned.len and cleaned[i + 2] >= '0' and cleaned[i + 2] <= '9')))
        {
            return .{ .neg = false, .next_pos = i + 1 };
        }
        return null;
    }
    var sign_end: usize = 0;
    if (cleaned[i] == '-') {
        sign_end = i + 1;
    } else if (i + 2 < cleaned.len and cleaned[i] == 0xE2 and cleaned[i + 1] == 0x88 and cleaned[i + 2] == 0x92) {
        sign_end = i + 3; // U+2212 '−'
    } else if (i + 2 < cleaned.len and cleaned[i] == 0xE2 and cleaned[i + 1] == 0x80 and
        (cleaned[i + 2] == 0x90 or cleaned[i + 2] == 0x91 or cleaned[i + 2] == 0x92 or cleaned[i + 2] == 0x93))
    {
        sign_end = i + 3; // U+2010..U+2013 hyphens & en-dash '–'
    } else return null;

    // Directly adjacent digit or leading decimal `.5`
    if (sign_end < cleaned.len and ((cleaned[sign_end] >= '0' and cleaned[sign_end] <= '9') or
        (cleaned[sign_end] == '.' and sign_end + 1 < cleaned.len and cleaned[sign_end + 1] >= '0' and cleaned[sign_end + 1] <= '9')))
    {
        // Only treat en-dash '–' as unary negative sign when NOT a numeric range (`100–200` has digit immediately before)
        if (i > 0 and cleaned[i - 1] >= '0' and cleaned[i - 1] <= '9' and cleaned[i] == 0xE2 and cleaned[i + 1] == 0x80 and cleaned[i + 2] == 0x93) {
            return null;
        }
        return .{ .neg = true, .next_pos = sign_end };
    }
    // Single space after unary `−` / `-` ONLY at clause start / punctuation (NOT binary `x − 45` or `100 − 50`)
    if (sign_end + 1 < cleaned.len and cleaned[sign_end] == ' ' and !isMathItalicBefore(cleaned, i)) {
        const after_sp = sign_end + 1;
        const is_num_next = (cleaned[after_sp] >= '0' and cleaned[after_sp] <= '9') or
            (cleaned[after_sp] == '.' and after_sp + 1 < cleaned.len and cleaned[after_sp + 1] >= '0' and cleaned[after_sp + 1] <= '9');
        if (is_num_next) {
            // Check previous non-space character is NOT a digit or single-letter math variable
            var prev_k = i;
            while (prev_k > 0 and cleaned[prev_k - 1] == ' ') : (prev_k -= 1) {}
            const unary_ctx = (prev_k == 0) or (cleaned[prev_k - 1] == '\n' or cleaned[prev_k - 1] == ':' or
                cleaned[prev_k - 1] == '(' or cleaned[prev_k - 1] == '[' or cleaned[prev_k - 1] == '=' or
                cleaned[prev_k - 1] == '<' or cleaned[prev_k - 1] == '>' or cleaned[prev_k - 1] == ',');
            if (unary_ctx) return .{ .neg = true, .next_pos = after_sp };
        }
    }
    return null;
}

fn isLineStartKickerPos(cleaned: []const u8, tok_start: usize) bool {
    if (tok_start == 0) return true;
    var k = tok_start;
    while (k > 0 and (cleaned[k - 1] == ' ' or cleaned[k - 1] == '\t')) : (k -= 1) {}
    if (k == 0) return true;
    const ch = cleaned[k - 1];
    if (ch == '\n' or ch == '\r' or ch == '|' or ch == '/') return true;
    // Allow after middle dot `·` (0xC2 0xB7) or bullet `•` (0xE2 0x80 0xA2)
    if (k >= 2 and cleaned[k - 2] == 0xC2 and cleaned[k - 1] == 0xB7) return true;
    if (k >= 3 and cleaned[k - 3] == 0xE2 and cleaned[k - 2] == 0x80 and cleaned[k - 1] == 0xA2) return true;
    return false;
}

const ExpMatch = struct { exp: i32, end: usize };

/// Parse an exponent immediately at `pos`: either ASCII `^ [({]? [+-−]? digits [)}]?` OR Unicode `[⁺⁻]?[⁰..⁹]+`.
fn parseExponentAt(s: []const u8, pos: usize, allow_unicode_sup: bool) ?ExpMatch {
    if (pos >= s.len) return null;
    if (s[pos] == '^') {
        var k = pos + 1;
        while (k < s.len and (s[k] == ' ' or s[k] == '\t')) : (k += 1) {}
        var close_delim: u8 = 0;
        if (k < s.len and (s[k] == '(' or s[k] == '{')) {
            close_delim = if (s[k] == '(') ')' else '}';
            k += 1;
            while (k < s.len and (s[k] == ' ' or s[k] == '\t')) : (k += 1) {}
        }
        var neg = false;
        if (k < s.len and (s[k] == '+' or s[k] == '-')) {
            neg = (s[k] == '-');
            k += 1;
        } else if (k + 2 < s.len and s[k] == 0xE2 and s[k + 1] == 0x88 and s[k + 2] == 0x92) {
            neg = true;
            k += 3;
        }
        const dstart = k;
        while (k < s.len and s[k] >= '0' and s[k] <= '9') : (k += 1) {}
        if (k == dstart) return null;
        var ev = std.fmt.parseInt(i32, s[dstart..k], 10) catch return null;
        if (neg) ev = -ev;
        if (ev < -300 or ev > 300) return null;
        if (close_delim != 0) {
            while (k < s.len and (s[k] == ' ' or s[k] == '\t')) : (k += 1) {}
            if (k < s.len and s[k] == close_delim) k += 1 else return null;
        }
        if (k < s.len and isIdentFollow(s[k])) return null;
        return .{ .exp = ev, .end = k };
    }
    if (!allow_unicode_sup) return null;
    var k = pos;
    var neg = false;
    if (decodeSupChar(s[k..])) |sc| {
        if (sc.ch == '+' or sc.ch == '-') {
            neg = (sc.ch == '-');
            k += sc.len;
        }
    } else return null;
    var dbuf: [16]u8 = undefined;
    var dlen: usize = 0;
    while (k < s.len) {
        const sc = decodeSupChar(s[k..]) orelse break;
        if (sc.ch < '0' or sc.ch > '9') break;
        if (dlen < dbuf.len) {
            dbuf[dlen] = sc.ch;
            dlen += 1;
        }
        k += sc.len;
    }
    if (dlen == 0) return null;
    if (k < s.len and isIdentFollow(s[k])) return null;
    var ev = std.fmt.parseInt(i32, dbuf[0..dlen], 10) catch return null;
    if (neg) ev = -ev;
    if (ev < -300 or ev > 300) return null;
    return .{ .exp = ev, .end = k };
}

/// Match optional whitespace + multiplication operator (`×`, `·`, `⋅`, `∙`, `*`, `x`, `X`) + optional whitespace + `10`.
fn matchMul10(s: []const u8, pos: usize) ?usize {
    var k = pos;
    while (k < s.len and (s[k] == ' ' or s[k] == '\t')) : (k += 1) {}
    if (k >= s.len) return null;
    if (k + 1 < s.len and s[k] == 0xC3 and s[k + 1] == 0x97) {
        k += 2; // '×'
    } else if (k + 1 < s.len and s[k] == 0xC2 and s[k + 1] == 0xB7) {
        k += 2; // '·'
    } else if (k + 2 < s.len and s[k] == 0xE2 and s[k + 1] == 0x8B and s[k + 2] == 0x85) {
        k += 3; // '⋅' (U+22C5 DOT OPERATOR — Typst `$5.17 dot 10^(6)$`)
    } else if (k + 2 < s.len and s[k] == 0xE2 and s[k + 1] == 0x88 and s[k + 2] == 0x99) {
        k += 3; // '∙' (U+2219 BULLET OPERATOR)
    } else if (s[k] == '*' or s[k] == 'x' or s[k] == 'X') {
        k += 1;
    } else return null;
    while (k < s.len and (s[k] == ' ' or s[k] == '\t')) : (k += 1) {}
    if (std.mem.startsWith(u8, s[k..], "10")) return k + 2;
    return null;
}

/// Check if an unsigned bare integer (`1..99`) at `tok_start` is immediately preceded on the SAME LINE by an
/// explicit structural keyword (`Page`, `Figure`, `Fig.`, `Table`, `Plate`, `Section`, `Eq.`, `Rule`, `Gate`, `Slide`, `§`).
fn hasStructuralPrefix(cleaned: []const u8, tok_start: usize) bool {
    var end = tok_start;
    // NEVER cross newlines (`\n` / `\r`) — defeats cross-newline heading smuggling!
    while (end > 0 and (cleaned[end - 1] == ' ' or cleaned[end - 1] == '\t')) : (end -= 1) {}
    if (end > 0 and (cleaned[end - 1] == '#' or cleaned[end - 1] == '(' or cleaned[end - 1] == '[')) {
        end -= 1;
        while (end > 0 and (cleaned[end - 1] == ' ' or cleaned[end - 1] == '\t')) : (end -= 1) {}
    }
    if (end == 0) return false;
    // Check UTF-8 '§' (U+00A7 = 0xC2 0xA7)
    if (end >= 2 and cleaned[end - 2] == 0xC2 and cleaned[end - 1] == 0xA7) return true;
    // Removed ambiguous lowercase plural nouns ("figures", "tables", "issue") that appear in financial prose!
    const keywords = [_][]const u8{
        "equations", "equation", "appendix", "sections", "exhibits", "section", "chapter",
        "exhibit",   "figure",   "plates",   "slides",   "pillar",   "pages",   "table",
        "plate",     "slide",    "rules",    "gates",    "page",     "rule",    "gate",
        "figs.",     "eqs.",     "refs.",    "fig.",     "tab.",     "sec.",    "vol.",
        "ref.",      "ch.",      "eq.",      "no.",      "pp.",      "p.",
    };
    for (keywords) |kw| {
        if (end < kw.len) continue;
        const start = end - kw.len;
        if (!std.ascii.eqlIgnoreCase(cleaned[start..end], kw)) continue;
        if (start == 0) return true;
        const prev = cleaned[start - 1];
        if (!isAsciiAlnum(prev) and prev != '_') return true;
    }
    return false;
}

/// Allow explicit page-footer pagination `<page_num> / <page_count>` or `<page_num> of <page_count>`.
fn isPagePagination(cleaned: []const u8, tok_start: usize, tok_end: usize, int_val: usize, page_num: usize, page_count: usize) bool {
    if (int_val == page_num) {
        var k = tok_end;
        while (k < cleaned.len and (cleaned[k] == ' ' or cleaned[k] == '\t')) : (k += 1) {}
        var matched_sep = false;
        if (k < cleaned.len and cleaned[k] == '/') {
            k += 1;
            matched_sep = true;
        } else if (k + 2 <= cleaned.len and std.ascii.eqlIgnoreCase(cleaned[k .. k + 2], "of") and (k + 2 == cleaned.len or !isAsciiAlnum(cleaned[k + 2]))) {
            k += 2;
            matched_sep = true;
        }
        if (matched_sep) {
            while (k < cleaned.len and (cleaned[k] == ' ' or cleaned[k] == '\t')) : (k += 1) {}
            const ds = k;
            while (k < cleaned.len and cleaned[k] >= '0' and cleaned[k] <= '9') : (k += 1) {}
            if (k > ds and (k == cleaned.len or (!isAsciiAlnum(cleaned[k]) and cleaned[k] != '.' and cleaned[k] != '%'))) {
                const rhs = std.fmt.parseInt(usize, cleaned[ds..k], 10) catch 0;
                if (rhs == page_count) return true;
            }
        }
    }
    if (int_val == page_count) {
        var k = tok_start;
        while (k > 0 and (cleaned[k - 1] == ' ' or cleaned[k - 1] == '\t')) : (k -= 1) {}
        var matched_sep = false;
        if (k > 0 and cleaned[k - 1] == '/') {
            k -= 1;
            matched_sep = true;
        } else if (k >= 2 and std.ascii.eqlIgnoreCase(cleaned[k - 2 .. k], "of") and (k == 2 or !isAsciiAlnum(cleaned[k - 3]))) {
            k -= 2;
            matched_sep = true;
        }
        if (matched_sep) {
            while (k > 0 and (cleaned[k - 1] == ' ' or cleaned[k - 1] == '\t')) : (k -= 1) {}
            const de = k;
            while (k > 0 and cleaned[k - 1] >= '0' and cleaned[k - 1] <= '9') : (k -= 1) {}
            if (de > k and (k == 0 or (!isAsciiAlnum(cleaned[k - 1]) and cleaned[k - 1] != '.'))) {
                const lhs = std.fmt.parseInt(usize, cleaned[k..de], 10) catch 0;
                if (lhs == page_num) return true;
            }
        }
    }
    return false;
}

/// Return a UTF-8-boundary-safe, single-line context snippet around `[tok_start..tok_end]`.
fn utf8ContextSnippet(alloc: std.mem.Allocator, s: []const u8, tok_start: usize, tok_end: usize) ![]u8 {
    var c0: usize = if (tok_start > 28) tok_start - 28 else 0;
    while (c0 < tok_start and (s[c0] & 0xC0) == 0x80) : (c0 += 1) {}
    var c1: usize = @min(s.len, tok_end + 28);
    while (c1 > tok_end and c1 < s.len and (s[c1] & 0xC0) == 0x80) : (c1 -= 1) {}
    const out = try alloc.dupe(u8, s[c0..c1]);
    for (out) |*ch| {
        if (ch.* == '\n' or ch.* == '\r' or ch.* == '\t') ch.* = ' ';
    }
    return out;
}

/// Gate 3 (Rule 10): Post-render PDF prose-to-ledger grounding (full f64 half-ULP precision, zero blanket structurals).
pub fn auditProse(
    alloc: std.mem.Allocator,
    io: std.Io,
    pages: []const mupdf.PageData,
    ledger_path: ?[]const u8,
    summary_path: ?[]const u8,
    citations_path: ?[]const u8,
    manifest_path: ?[]const u8,
) !ProseReport {
    var seen = std.AutoHashMap(u64, void).init(alloc);
    var auth_list: std.ArrayList(f64) = .empty;

    if (ledger_path) |lp| {
        const raw = try std.Io.Dir.cwd().readFileAlloc(io, lp, alloc, .unlimited);
        const parsed = try std.json.parseFromSliceLeaky(std.json.Value, alloc, raw, .{});
        try collectJsonNumbers(alloc, parsed, &seen, &auth_list);
        switch (parsed) {
            .array => |a| try addExactFloat(alloc, &seen, &auth_list, @floatFromInt(a.items.len)),
            .object => |o| try addExactFloat(alloc, &seen, &auth_list, @floatFromInt(o.count())),
            else => {},
        }
    }
    if (summary_path) |sp| {
        const raw = try std.Io.Dir.cwd().readFileAlloc(io, sp, alloc, .unlimited);
        const parsed = try std.json.parseFromSliceLeaky(std.json.Value, alloc, raw, .{});
        try collectJsonNumbers(alloc, parsed, &seen, &auth_list);
        try deriveExactSpeciesRatios(alloc, parsed, &seen, &auth_list);
    }
    if (citations_path) |cp| {
        const raw = try std.Io.Dir.cwd().readFileAlloc(io, cp, alloc, .unlimited);
        const parsed = try std.json.parseFromSliceLeaky(std.json.Value, alloc, raw, .{});
        try collectCitationNumbers(alloc, parsed, &seen, &auth_list);
    }
    if (manifest_path) |mp| {
        const raw = try std.Io.Dir.cwd().readFileAlloc(io, mp, alloc, .unlimited);
        var cnt: usize = 0;
        var it = std.mem.splitScalar(u8, raw, '\n');
        while (it.next()) |ln| {
            if (std.mem.trim(u8, ln, " \t\r").len > 0) cnt += 1;
        }
        try addExactFloat(alloc, &seen, &auth_list, @floatFromInt(cnt));
    }

    const auth_slice = auth_list.items;
    var ungrounded: std.ArrayList(UngroundedToken) = .empty;
    var total_checked: usize = 0;

    for (pages) |pg| {
        // Surface any /ToUnicode glyph-width spoofing anomalies detected directly on this page
        for (pg.tounicode_anomalies) |anom| {
            try ungrounded.append(alloc, .{
                .page = pg.page_num,
                .token = "TOUNICODE_SPOOF",
                .value = 0.0,
                .context = anom,
            });
        }
        const cleaned = try cleanProseText(alloc, pg.prose_text, pg.width, pg.height);
        var i: usize = 0;
        while (i < cleaned.len) {
            var sign_neg = false;
            var has_sign = false;
            const tok_start = i;
            var num_start = i;

            const prev_ok = (i == 0) or !isTokenPrevBlocked(cleaned[i - 1]);
            if (!prev_ok) {
                i += 1;
                continue;
            }
            if (matchUnarySignAt(cleaned, i)) |sm| {
                has_sign = true;
                sign_neg = sm.neg;
                num_start = sm.next_pos;
            } else if (cleaned[i] == '.' and i + 1 < cleaned.len and cleaned[i + 1] >= '0' and cleaned[i + 1] <= '9') {
                // Leading decimal `.05`, `.001` (unsigned)
                num_start = i;
            } else if (cleaned[i] < '0' or cleaned[i] > '9') {
                i += 1;
                continue;
            }

            var j = num_start;
            var digits_buf: [64]u8 = undefined;
            var dlen: usize = 0;
            var seen_dot = false;
            var seen_comma = false;
            var decs: u8 = 0;
            if (j < cleaned.len and cleaned[j] == '.' and j + 1 < cleaned.len and cleaned[j + 1] >= '0' and cleaned[j + 1] <= '9') {
                digits_buf[0] = '0';
                digits_buf[1] = '.';
                dlen = 2;
                seen_dot = true;
                j += 1;
            }
            while (j < cleaned.len) {
                const ch = cleaned[j];
                if (ch >= '0' and ch <= '9') {
                    if (dlen < digits_buf.len) {
                        digits_buf[dlen] = ch;
                        dlen += 1;
                    }
                    if (seen_dot and decs < 20) decs += 1;
                    j += 1;
                } else if (ch == ',' and !seen_dot and j + 3 < cleaned.len and
                    cleaned[j + 1] >= '0' and cleaned[j + 1] <= '9' and
                    cleaned[j + 2] >= '0' and cleaned[j + 2] <= '9' and
                    cleaned[j + 3] >= '0' and cleaned[j + 3] <= '9')
                {
                    seen_comma = true;
                    j += 1;
                } else if (ch == '.' and !seen_dot and j + 1 < cleaned.len and cleaned[j + 1] >= '0' and cleaned[j + 1] <= '9') {
                    seen_dot = true;
                    if (dlen < digits_buf.len) {
                        digits_buf[dlen] = '.';
                        dlen += 1;
                    }
                    j += 1;
                } else break;
            }
            if (dlen == 0) {
                i = j;
                continue;
            }
            const raw_num = cleaned[num_start..j];

            // Branch 1: mantissa × 10^exp (caret or Unicode superscript; also checks attached unit suffix!)
            if (matchMul10(cleaned, j)) |after10| {
                if (parseExponentAt(cleaned, after10, true)) |em| {
                    const tok_end = em.end;
                    i = tok_end;
                    var mv = std.fmt.parseFloat(f64, digits_buf[0..dlen]) catch continue;
                    if (sign_neg) mv = -mv;
                    const val = mv * std.math.pow(f64, 10.0, @floatFromInt(em.exp));
                    total_checked += 1;
                    if (!rule10IsGrounded(val, decs, em.exp, false, auth_slice)) {
                        try ungrounded.append(alloc, .{
                            .page = pg.page_num,
                            .token = try alloc.dupe(u8, cleaned[tok_start..tok_end]),
                            .value = val,
                            .context = try utf8ContextSnippet(alloc, cleaned, tok_start, tok_end),
                        });
                    }
                    continue;
                }
            }

            // Branch 2: bare 10^exp (caret or Unicode superscript)
            if (std.mem.eql(u8, raw_num, "10")) {
                if (parseExponentAt(cleaned, j, true)) |em| {
                    const tok_end = em.end;
                    i = tok_end;
                    var val = std.math.pow(f64, 10.0, @floatFromInt(em.exp));
                    if (sign_neg) val = -val;
                    total_checked += 1;
                    if (!rule10IsGrounded(val, 0, em.exp, true, auth_slice)) {
                        try ungrounded.append(alloc, .{
                            .page = pg.page_num,
                            .token = try alloc.dupe(u8, cleaned[tok_start..tok_end]),
                            .value = val,
                            .context = try utf8ContextSnippet(alloc, cleaned, tok_start, tok_end),
                        });
                    }
                    continue;
                }
            }

            // Branch 3: explicit ASCII caret base^exp (e.g. 2^10, 2^9)
            if (!seen_comma and j < cleaned.len and cleaned[j] == '^') {
                if (parseExponentAt(cleaned, j, false)) |em| {
                    const tok_end = em.end;
                    i = tok_end;
                    const bv = std.fmt.parseFloat(f64, digits_buf[0..dlen]) catch continue;
                    var val = std.math.pow(f64, bv, @floatFromInt(em.exp));
                    if (sign_neg) val = -val;
                    total_checked += 1;
                    if (!rule10IsGrounded(val, 0, null, true, auth_slice)) {
                        try ungrounded.append(alloc, .{
                            .page = pg.page_num,
                            .token = try alloc.dupe(u8, cleaned[tok_start..tok_end]),
                            .value = val,
                            .context = try utf8ContextSnippet(alloc, cleaned, tok_start, tok_end),
                        });
                    }
                    continue;
                }
            }

            // Branch 4: standard ASCII scientific notation mantissa[eE][+-−]?exp (e.g. 1.25e-15, 9.9e9m, 1,000e9J)
            if (j + 1 < cleaned.len and (cleaned[j] == 'e' or cleaned[j] == 'E')) {
                var ek = j + 1;
                var eneg = false;
                if (ek < cleaned.len and (cleaned[ek] == '+' or cleaned[ek] == '-')) {
                    eneg = (cleaned[ek] == '-');
                    ek += 1;
                } else if (ek + 2 < cleaned.len and cleaned[ek] == 0xE2 and cleaned[ek + 1] == 0x88 and cleaned[ek + 2] == 0x92) {
                    eneg = true;
                    ek += 3;
                }
                const eds = ek;
                while (ek < cleaned.len and cleaned[ek] >= '0' and cleaned[ek] <= '9') : (ek += 1) {}
                if (ek > eds) {
                    if (matchAllowedNumericSuffix(cleaned, ek, num_start, raw_num)) |suf| {
                        var ev = std.fmt.parseInt(i32, cleaned[eds..ek], 10) catch 9999;
                        if (eneg) ev = -ev;
                        if (ev >= -300 and ev <= 300) {
                            const tok_end = ek + suf.len;
                            i = tok_end;
                            var mv = std.fmt.parseFloat(f64, digits_buf[0..dlen]) catch continue;
                            if (sign_neg) mv = -mv;
                            const val = mv * std.math.pow(f64, 10.0, @floatFromInt(ev));
                            total_checked += 1;
                            const ok = rule10IsGrounded(val, decs, ev, false, auth_slice) or
                                (suf.scale != 1.0 and rule10IsGrounded(val * suf.scale, decs, ev, false, auth_slice));
                            if (!ok) {
                                try ungrounded.append(alloc, .{
                                    .page = pg.page_num,
                                    .token = try alloc.dupe(u8, cleaned[tok_start..tok_end]),
                                    .value = val,
                                    .context = try utf8ContextSnippet(alloc, cleaned, tok_start, tok_end),
                                });
                            }
                            continue;
                        }
                    }
                }
            }

            // Branch 5: plain signed/unsigned number (with unit-aware suffix parsing!)
            var tok_end = j;
            var has_pct = false;
            var suf_scale: f64 = 1.0;
            if (tok_end < cleaned.len and cleaned[tok_end] == '%') {
                tok_end += 1;
                has_pct = true;
            }
            const suf_opt = if (has_pct) SuffixMatch{ .len = 0, .scale = 1.0 } else matchAllowedNumericSuffix(cleaned, tok_end, num_start, raw_num);
            if (suf_opt) |suf| {
                tok_end += suf.len;
                suf_scale = suf.scale;
                i = tok_end;
            } else {
                i = tok_end;
                continue;
            }

            // Skip hyphen-attached identifiers/dates/ISSNs (`1958-03`, `2026-10`, `BY-4.0`, `TOI-700`, `Yoshida-4`, `0031-9007`)
            // while auditing numeric ranges (`64,896-999999`) and percent targets (`non-99%`)
            if (!has_sign and isHyphenIdentifierBefore(cleaned, tok_start, j, has_pct)) continue;

            // Unicode math-italic variable directly before +/− (e.g. 𝑖−1, 𝑘−1) is binary subtraction, not unary sign
            var disp_start = tok_start;
            if (has_sign and isMathItalicBefore(cleaned, tok_start)) {
                has_sign = false;
                sign_neg = false;
                disp_start = num_start;
            }

            // Leading-zero 2-digit plate/card kicker ordinals "01".."12" (ONLY unsigned, no %, no decimal, at line-start / kicker boundary)
            if (!has_sign and !has_pct and !seen_dot and raw_num.len == 2 and raw_num[0] == '0' and isLineStartKickerPos(cleaned, tok_start)) continue;

            // Contextual structural ordinals: ONLY bare unsigned integers 1..99 on same line after unambiguous structural keyword
            if (!has_sign and !has_pct and !seen_dot and !seen_comma and suf_scale == 1.0 and tok_end == j) {
                const iv = std.fmt.parseInt(usize, raw_num, 10) catch 0;
                if (iv >= 1 and iv <= 99 and hasStructuralPrefix(cleaned, tok_start)) continue;
                if (iv >= 1 and isPagePagination(cleaned, tok_start, tok_end, iv, pg.page_num, pages.len)) continue;
            }

            var parsed_v = std.fmt.parseFloat(f64, digits_buf[0..dlen]) catch continue;
            if (sign_neg) parsed_v = -parsed_v;

            total_checked += 1;
            const grounded = rule10IsGrounded(parsed_v, decs, null, false, auth_slice) or
                (suf_scale != 1.0 and rule10IsGrounded(parsed_v * suf_scale, 0, null, false, auth_slice));
            if (!grounded) {
                try ungrounded.append(alloc, .{
                    .page = pg.page_num,
                    .token = try alloc.dupe(u8, cleaned[disp_start..tok_end]),
                    .value = parsed_v,
                    .context = try utf8ContextSnippet(alloc, cleaned, tok_start, tok_end),
                });
            }
        }
    }

    const u_slice = try ungrounded.toOwnedSlice(alloc);
    return .{
        .pages = pages.len,
        .authorized_pool = auth_slice.len,
        .numbers_checked = total_checked,
        .ungrounded_count = u_slice.len,
        .passed = u_slice.len == 0,
        .ungrounded = u_slice,
    };
}

fn runVeraPdf(alloc: std.mem.Allocator, io: std.Io, pdf_path: []const u8) VeraPdfResult {
    const vp_bin = mupdf.whichTool(alloc, io, "verapdf") orelse return .{
        .available = false,
        .compliant = false,
        .passed_rules = 0,
        .failed_rules = 0,
    };
    const res = mupdf.runCmd(alloc, io, &.{ vp_bin, "--flavour", "ua1", "--format", "json", pdf_path }, null) catch {
        return .{ .available = true, .compliant = false, .passed_rules = 0, .failed_rules = 1 };
    };
    const parsed = std.json.parseFromSliceLeaky(std.json.Value, alloc, res.stdout, .{}) catch {
        return .{ .available = true, .compliant = false, .passed_rules = 0, .failed_rules = 1 };
    };
    const rep = parsed.object.get("report") orelse return .{ .available = true, .compliant = false, .passed_rules = 0, .failed_rules = 1 };
    const jobs = rep.object.get("jobs") orelse return .{ .available = true, .compliant = false, .passed_rules = 0, .failed_rules = 1 };
    if (jobs != .array or jobs.array.items.len == 0) return .{ .available = true, .compliant = false, .passed_rules = 0, .failed_rules = 1 };
    const vr_arr = jobs.array.items[0].object.get("validationResult") orelse return .{ .available = true, .compliant = false, .passed_rules = 0, .failed_rules = 1 };
    if (vr_arr != .array or vr_arr.array.items.len == 0) return .{ .available = true, .compliant = false, .passed_rules = 0, .failed_rules = 1 };
    const vr = vr_arr.array.items[0].object;
    const comp = if (vr.get("compliant")) |cv| (cv == .bool and cv.bool) else false;
    var pr: i64 = 0;
    var fr: i64 = 0;
    if (vr.get("details")) |det| {
        if (det == .object) {
            if (det.object.get("passedRules")) |pv| if (pv == .integer) {
                pr = pv.integer;
            };
            if (det.object.get("failedRules")) |fv| if (fv == .integer) {
                fr = fv.integer;
            };
        }
    }
    return .{ .available = true, .compliant = comp, .passed_rules = pr, .failed_rules = fr };
}

/// Gate 4: Print Pre-Press & ISO 14289-1 (`PDF/UA-1`) certification audit (true 72-DPI MuPDF CMYK PAM TAC,
/// checked bounds, fail-closed `--require-ua`, and dereferenced font/bleed enforcement).
pub fn auditPrepress(
    alloc: std.mem.Allocator,
    io: std.Io,
    pdf_path: []const u8,
    pages: []const mupdf.PageData,
    cat: mupdf.CatalogInfo,
    min_dpi: f64,
    max_tac_pct: f64,
    require_bleed: bool,
    require_ua: bool,
    enable_verapdf: bool,
    tmp_tag: []const u8,
) !PrepressReport {
    var failures: std.ArrayList([]const u8) = .empty;
    var img_count: usize = 0;
    var min_eff_dpi_x10: i64 = 9999999;
    const min_dpi_x10 = try mupdf.checkedRoundInt(i64, min_dpi * 10.0, 0.0, 1.0e8);
    const max_tac_x10 = try mupdf.checkedRoundInt(i64, max_tac_pct * 10.0, 0.0, 4000.0);

    var peak_tac_x10: i64 = 0;
    var p99_tac_x10: i64 = 0;
    var tacs: std.ArrayList(i64) = .empty;

    for (pages) |pg| {
        for (pg.images) |im| {
            img_count += 1;
            if (im.eff_dpi_x10 < min_eff_dpi_x10) min_eff_dpi_x10 = im.eff_dpi_x10;
            if (im.eff_dpi_x10 < min_dpi_x10) {
                try failures.append(alloc, try std.fmt.allocPrint(alloc, "Page {d} image effective DPI {d:.1} < {d:.0}", .{
                    pg.page_num,
                    @as(f64, @floatFromInt(im.eff_dpi_x10)) / 10.0,
                    min_dpi,
                }));
            }
        }
        // True DeviceCMYK 4-channel TAC (0..400%) directly from MuPDF CMYK PAM render at 72 DPI
        const pam = try mupdf.renderPageCmykPam(alloc, io, pdf_path, pg.page_num, 72, tmp_tag);
        tacs.clearRetainingCapacity();
        var off: usize = 0;
        while (off + 3 < pam.pixels.len) : (off += 4) {
            const sum_cmyk: i64 = @as(i64, pam.pixels[off]) + @as(i64, pam.pixels[off + 1]) +
                @as(i64, pam.pixels[off + 2]) + @as(i64, pam.pixels[off + 3]);
            const tac_x10: i64 = @divTrunc(sum_cmyk * 1000 + 127, 255);
            try tacs.append(alloc, tac_x10);
        }
        if (tacs.items.len > 0) {
            std.mem.sort(i64, tacs.items, {}, std.sort.asc(i64));
            const pmax = tacs.items[tacs.items.len - 1];
            const p99_idx = (tacs.items.len - 1) * 99 / 100;
            const p99 = tacs.items[p99_idx];
            if (pmax > peak_tac_x10) peak_tac_x10 = pmax;
            if (p99 > p99_tac_x10) p99_tac_x10 = p99;
        }
    }

    if (cat.unembedded_fonts.len > 0) {
        try failures.append(alloc, try std.fmt.allocPrint(alloc, "Unembedded font(s): {d} found (first: {s})", .{
            cat.unembedded_fonts.len,
            cat.unembedded_fonts[0],
        }));
    }
    if (require_bleed and !cat.bleed_all_pages) {
        try failures.append(alloc, try std.fmt.allocPrint(alloc, "Missing prepress bleed box (min margin {d:.1}pt < 5pt)", .{cat.min_bleed_margin_pt}));
    }
    if (p99_tac_x10 > max_tac_x10) {
        try failures.append(alloc, try std.fmt.allocPrint(alloc, "CMYK p99 TAC {d:.1}% > {d:.0}%", .{
            @as(f64, @floatFromInt(p99_tac_x10)) / 10.0,
            max_tac_pct,
        }));
    }
    // Also reject localized registration-black ink violations (peak > max_tac + 20%, e.g. 400% patches > 320%)
    if (peak_tac_x10 > max_tac_x10 + 200) {
        try failures.append(alloc, try std.fmt.allocPrint(alloc, "CMYK peak TAC {d:.1}% > {d:.0}% (+20% spot ceiling)", .{
            @as(f64, @floatFromInt(peak_tac_x10)) / 10.0,
            max_tac_pct + 20.0,
        }));
    }

    const ua_struct_pass = cat.marked and cat.has_struct_tree and cat.has_lang and cat.has_title and cat.has_pdfua_xmp;
    if (require_ua and !ua_struct_pass) {
        try failures.append(alloc, "PDF/UA structure incomplete (requires /MarkInfo, non-empty /StructTreeRoot /K, /Lang, Title, pdfuaid:part XMP)");
    }

    const vp = if (enable_verapdf) runVeraPdf(alloc, io, pdf_path) else VeraPdfResult{
        .available = false,
        .compliant = false,
        .passed_rules = 0,
        .failed_rules = 0,
    };
    if (require_ua and enable_verapdf and !vp.available) {
        try failures.append(alloc, "PDF/UA-1 certification requires 'verapdf' on PATH (fail-closed; pass --no-verapdf only for structural-only check)");
    }
    if (require_ua and vp.available and !vp.compliant) {
        try failures.append(alloc, try std.fmt.allocPrint(alloc, "veraPDF ISO 14289-1 non-compliant ({d} failed rules)", .{vp.failed_rules}));
    }

    const flist = try failures.toOwnedSlice(alloc);
    return .{
        .pages = pages.len,
        .image_count = img_count,
        .min_eff_dpi_x10 = if (img_count > 0) min_eff_dpi_x10 else -1,
        .unembedded_fonts = cat.unembedded_fonts,
        .bleed_all_pages = cat.bleed_all_pages,
        .min_bleed_margin_pt = cat.min_bleed_margin_pt,
        .cmyk_p99_tac_x10 = p99_tac_x10,
        .cmyk_peak_tac_x10 = peak_tac_x10,
        .ua_struct_pass = ua_struct_pass,
        .verapdf = vp,
        .failures = flist,
        .passed = flist.len == 0,
    };
}

pub fn sha256HexFile(alloc: std.mem.Allocator, io: std.Io, path: []const u8) ![64]u8 {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .unlimited);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    const hex_chars = "0123456789abcdef";
    var out: [64]u8 = undefined;
    for (digest, 0..) |byte, idx| {
        out[idx * 2] = hex_chars[byte >> 4];
        out[idx * 2 + 1] = hex_chars[byte & 0x0f];
    }
    return out;
}

fn isValidSha256Hex(s: []const u8) bool {
    if (s.len != 64) return false;
    for (s) |ch| {
        if (!isHexDigit(ch)) return false;
    }
    return true;
}

fn hasPathTraversal(rel: []const u8) bool {
    if (rel.len == 0 or rel[0] == '/' or rel[0] == '\\') return true;
    var it = std.mem.splitAny(u8, rel, "/\\");
    while (it.next()) |seg| {
        if (std.mem.eql(u8, seg, "..")) return true;
    }
    return false;
}

fn lookupManifestSha(manifest_map: *const std.StringHashMap([64]u8), manifest_basenames: *const std.StringHashMap([64]u8), doc_path: []const u8) ?[64]u8 {
    if (manifest_map.get(doc_path)) |h| return h;
    if (std.mem.startsWith(u8, doc_path, "data/raw/")) {
        if (manifest_map.get(doc_path["data/raw/".len..])) |h| return h;
    }
    const base = std.fs.path.basename(doc_path);
    return manifest_basenames.get(base);
}

fn ledgerValueMatches(lval: ?f64, sval: std.json.Value) bool {
    const sf = jsonToFloat(sval) orelse return true; // non-numeric summary fields checked by key existence
    const lf = lval orelse return false;
    const tol = @max(@as(f64, 1e-6), @abs(sf) * 1e-6);
    return @abs(lf - sf) <= tol;
}

/// Gate 5 (Pure-Zig Cryptographic Rule 4 + Rule 6 Compilation Latch):
/// Verifies non-empty `data/manifest.sha256` + all files under `data/raw/*`, cryptographically binds EVERY
/// provenance ledger tuple (`source_document`/`source_file`, `source_locator`/`locator`, `raw_file_sha256`/`source_sha256`)
/// against `manifest_map`, fails closed on corrupt JSON, and enforces 1:1 coverage & value equality against `summary_metrics.json`.
pub fn auditLatch(alloc: std.mem.Allocator, io: std.Io, project_dir: []const u8) !LatchReport {
    var failures: std.ArrayList([]const u8) = .empty;
    const manifest_path = try std.fmt.allocPrint(alloc, "{s}/data/manifest.sha256", .{project_dir});
    const ledger_path = try std.fmt.allocPrint(alloc, "{s}/data/provenance_ledger.json", .{project_dir});
    const summary_path = try std.fmt.allocPrint(alloc, "{s}/data/summary_metrics.json", .{project_dir});

    const manifest_raw = std.Io.Dir.cwd().readFileAlloc(io, manifest_path, alloc, .unlimited) catch {
        try failures.append(alloc, "Missing data/manifest.sha256");
        return .{ .manifest_files = 0, .manifest_verified = 0, .ledger_records = 0, .metrics_verified = 0, .failures = try failures.toOwnedSlice(alloc), .passed = false };
    };

    var manifest_map = std.StringHashMap([64]u8).init(alloc);
    var manifest_basenames = std.StringHashMap([64]u8).init(alloc);
    var m_files: usize = 0;
    var m_ok: usize = 0;
    var ln_it = std.mem.splitScalar(u8, manifest_raw, '\n');
    while (ln_it.next()) |ln| {
        const trimmed = std.mem.trim(u8, ln, " \t\r");
        if (trimmed.len == 0) continue;
        var sp = std.mem.tokenizeAny(u8, trimmed, " \t");
        const expected_hex = sp.next() orelse {
            try failures.append(alloc, "Malformed line in data/manifest.sha256");
            continue;
        };
        const rel_file = sp.next() orelse {
            try failures.append(alloc, try std.fmt.allocPrint(alloc, "Malformed manifest line missing file path: '{s}'", .{trimmed[0..@min(trimmed.len, 48)]}));
            continue;
        };
        if (!isValidSha256Hex(expected_hex)) {
            try failures.append(alloc, try std.fmt.allocPrint(alloc, "Invalid 64-hex SHA-256 digest in manifest for '{s}'", .{rel_file}));
            continue;
        }
        if (hasPathTraversal(rel_file)) {
            try failures.append(alloc, try std.fmt.allocPrint(alloc, "Unsafe path traversal or absolute path in manifest: '{s}'", .{rel_file}));
            continue;
        }
        m_files += 1;
        // Canonical path resolution: prefer `{project_dir}/{rel_file}` (fixes `report/assets/...` in botanica), fallback to `{project_dir}/data/raw/{rel_file}`
        const direct_path = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ project_dir, rel_file });
        const raw_fallback = try std.fmt.allocPrint(alloc, "{s}/data/raw/{s}", .{ project_dir, rel_file });
        const actual = sha256HexFile(alloc, io, direct_path) catch
            (sha256HexFile(alloc, io, raw_fallback) catch {
                try failures.append(alloc, try std.fmt.allocPrint(alloc, "Missing raw file listed in manifest: {s}", .{rel_file}));
                continue;
            });
        if (std.ascii.eqlIgnoreCase(expected_hex, &actual)) {
            m_ok += 1;
            try manifest_map.put(try alloc.dupe(u8, rel_file), actual);
            const base = std.fs.path.basename(rel_file);
            try manifest_basenames.put(try alloc.dupe(u8, base), actual);
        } else {
            try failures.append(alloc, try std.fmt.allocPrint(alloc, "SHA-256 mismatch on {s}", .{rel_file}));
        }
    }
    if (m_files == 0) {
        try failures.append(alloc, "Empty data/manifest.sha256 (0 verified raw files)");
    }

    // Fail closed if any regular file inside `data/raw/` is unmonitored by `manifest.sha256`
    const raw_dir_path = try std.fmt.allocPrint(alloc, "{s}/data/raw", .{project_dir});
    if (std.Io.Dir.cwd().openDir(io, raw_dir_path, .{ .iterate = true })) |d| {
        var rdir = d;
        defer rdir.close(io);
        var rit = rdir.iterate();
        while (try rit.next(io)) |ent| {
            if (ent.kind != .file or ent.name.len == 0 or ent.name[0] == '.') continue;
            const rel_cand = try std.fmt.allocPrint(alloc, "data/raw/{s}", .{ent.name});
            if (lookupManifestSha(&manifest_map, &manifest_basenames, rel_cand) == null) {
                try failures.append(alloc, try std.fmt.allocPrint(alloc, "Unmonitored raw file in data/raw/ missing from manifest.sha256: {s}", .{ent.name}));
            }
        }
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => try failures.append(alloc, try std.fmt.allocPrint(alloc, "Unable to inspect data/raw directory: {s}", .{@errorName(err)})),
    }

    // Verify Rule 4 provenance ledger: fail closed on corrupt JSON AND verify EVERY record's cryptographic binding to manifest_map
    var ledger_keys = std.StringHashMap(?f64).init(alloc);
    var ledger_count: usize = 0;
    if (std.Io.Dir.cwd().readFileAlloc(io, ledger_path, alloc, .unlimited)) |lraw| {
        if (std.json.parseFromSliceLeaky(std.json.Value, alloc, lraw, .{})) |lv| {
            switch (lv) {
                .array => |arr| {
                    ledger_count = arr.items.len;
                    for (arr.items, 0..) |item, ridx| {
                        if (item != .object) {
                            try failures.append(alloc, try std.fmt.allocPrint(alloc, "Rule 4: ledger record[{d}] is not a JSON object", .{ridx}));
                            continue;
                        }
                        const obj = item.object;
                        const mid = if (obj.get("metric_id")) |v| (if (v == .string and v.string.len > 0) v.string else null) else null;
                        if (mid == null) {
                            try failures.append(alloc, try std.fmt.allocPrint(alloc, "Rule 4: ledger record[{d}] missing metric_id", .{ridx}));
                            continue;
                        }
                        const sdoc = if (obj.get("source_document")) |v| (if (v == .string and v.string.len > 0) v.string else null) else if (obj.get("source_file")) |v| (if (v == .string and v.string.len > 0) v.string else null) else null;
                        const sloc = if (obj.get("source_locator")) |v| (if (v == .string and v.string.len > 0) v.string else null) else if (obj.get("locator")) |v| (if (v == .string and v.string.len > 0) v.string else null) else null;
                        const ssha = if (obj.get("raw_file_sha256")) |v| (if (v == .string and v.string.len > 0) v.string else null) else if (obj.get("source_sha256")) |v| (if (v == .string and v.string.len > 0) v.string else null) else null;
                        if (ssha == null) {
                            try failures.append(alloc, try std.fmt.allocPrint(alloc, "Rule 4: ledger '{s}' missing raw_file_sha256", .{mid.?}));
                        } else if (!isValidSha256Hex(ssha.?)) {
                            try failures.append(alloc, try std.fmt.allocPrint(alloc, "Rule 4: ledger '{s}' has invalid raw_file_sha256 '{s}'", .{ mid.?, ssha.? }));
                        } else if (sdoc != null) {
                            if (sloc == null) {
                                try failures.append(alloc, try std.fmt.allocPrint(alloc, "Rule 4: ledger '{s}' missing source_locator", .{mid.?}));
                            } else {
                                const mf_sha = lookupManifestSha(&manifest_map, &manifest_basenames, sdoc.?);
                                if (mf_sha == null) {
                                    try failures.append(alloc, try std.fmt.allocPrint(alloc, "Rule 4: ledger '{s}' references unverified source '{s}' not in manifest.sha256", .{ mid.?, sdoc.? }));
                                } else if (!std.ascii.eqlIgnoreCase(ssha.?, &mf_sha.?)) {
                                    try failures.append(alloc, try std.fmt.allocPrint(alloc, "Rule 4: ledger '{s}' SHA-256 mismatch against manifest for '{s}'", .{ mid.?, sdoc.? }));
                                }
                            }
                        } else if (manifest_map.count() == 1) {
                            var mit_only = manifest_map.valueIterator();
                            const only_sha = mit_only.next().?.*;
                            if (!std.ascii.eqlIgnoreCase(ssha.?, &only_sha)) {
                                try failures.append(alloc, try std.fmt.allocPrint(alloc, "Rule 4: ledger '{s}' raw_file_sha256 does not match verified manifest digest", .{mid.?}));
                            }
                        } else {
                            try failures.append(alloc, try std.fmt.allocPrint(alloc, "Rule 4: ledger '{s}' missing source_document and source_locator", .{mid.?}));
                        }
                        const fval: ?f64 = if (obj.get("value")) |vv| jsonToFloat(vv) else null;
                        try ledger_keys.put(try alloc.dupe(u8, mid.?), fval);
                    }
                },
                .object => |obj| {
                    // Object-keyed ledger schema (e.g. botanica-veridica `<slug>.<metric>`)
                    ledger_count = obj.count();
                    var oit = obj.iterator();
                    while (oit.next()) |ent| {
                        const mid = ent.key_ptr.*;
                        if (ent.value_ptr.* != .object) {
                            try failures.append(alloc, try std.fmt.allocPrint(alloc, "Rule 4: ledger entry '{s}' is not an object", .{mid}));
                            continue;
                        }
                        const rec = ent.value_ptr.*.object;
                        const sdoc = if (rec.get("source_file")) |v| (if (v == .string and v.string.len > 0) v.string else null) else if (rec.get("source_document")) |v| (if (v == .string and v.string.len > 0) v.string else null) else null;
                        const sloc = if (rec.get("locator")) |v| (if (v == .string and v.string.len > 0) v.string else null) else if (rec.get("source_locator")) |v| (if (v == .string and v.string.len > 0) v.string else null) else null;
                        const ssha = if (rec.get("source_sha256")) |v| (if (v == .string and v.string.len > 0) v.string else null) else if (rec.get("raw_file_sha256")) |v| (if (v == .string and v.string.len > 0) v.string else null) else null;
                        if (sdoc == null or sloc == null or ssha == null) {
                            try failures.append(alloc, try std.fmt.allocPrint(alloc, "Rule 4: ledger '{s}' missing source_file, locator, or source_sha256", .{mid}));
                        } else if (!isValidSha256Hex(ssha.?)) {
                            try failures.append(alloc, try std.fmt.allocPrint(alloc, "Rule 4: ledger '{s}' has invalid source_sha256", .{mid}));
                        } else {
                            const mf_sha = lookupManifestSha(&manifest_map, &manifest_basenames, sdoc.?);
                            if (mf_sha == null) {
                                try failures.append(alloc, try std.fmt.allocPrint(alloc, "Rule 4: ledger '{s}' references unverified source '{s}'", .{ mid, sdoc.? }));
                            } else if (!std.ascii.eqlIgnoreCase(ssha.?, &mf_sha.?)) {
                                try failures.append(alloc, try std.fmt.allocPrint(alloc, "Rule 4: ledger '{s}' SHA-256 mismatch against manifest for '{s}'", .{ mid, sdoc.? }));
                            }
                        }
                        const fval: ?f64 = if (rec.get("value")) |vv| jsonToFloat(vv) else null;
                        try ledger_keys.put(try alloc.dupe(u8, mid), fval);
                    }
                },
                else => {
                    try failures.append(alloc, "Invalid data/provenance_ledger.json root type (must be array or object)");
                },
            }
        } else |_| {
            try failures.append(alloc, "Corrupt/unparseable JSON in data/provenance_ledger.json");
        }
    } else |_| {
        try failures.append(alloc, "Missing data/provenance_ledger.json");
    }
    if (ledger_count == 0) {
        try failures.append(alloc, "Empty data/provenance_ledger.json (0 provenance records)");
    }

    var metrics_ok: usize = 0;
    if (std.Io.Dir.cwd().readFileAlloc(io, summary_path, alloc, .unlimited)) |sraw| {
        if (std.json.parseFromSliceLeaky(std.json.Value, alloc, sraw, .{})) |sv| {
            if (sv != .object) {
                try failures.append(alloc, "Invalid data/summary_metrics.json root type (must be JSON object)");
            } else if (sv.object.get("metrics")) |mv| {
                // Canonical nested `"metrics": {...}` schema
                if (mv == .object) {
                    var mit = mv.object.iterator();
                    while (mit.next()) |ent| {
                        if (ledger_keys.get(ent.key_ptr.*)) |lval| {
                            if (ledgerValueMatches(lval, ent.value_ptr.*)) {
                                metrics_ok += 1;
                            } else {
                                try failures.append(alloc, try std.fmt.allocPrint(alloc, "Rule 4: metric '{s}' value in summary_metrics.json disagrees with provenance_ledger.json", .{ent.key_ptr.*}));
                            }
                        } else {
                            try failures.append(alloc, try std.fmt.allocPrint(alloc, "Rule 4: metric '{s}' missing from provenance_ledger.json", .{ent.key_ptr.*}));
                        }
                    }
                } else {
                    try failures.append(alloc, "Invalid 'metrics' field in data/summary_metrics.json (must be object)");
                }
            } else if (sv.object.get("species")) |spv| {
                // Structured species monograph schema (e.g. botanica-veridica: `<slug>.<metric>`)
                if (spv == .array) {
                    for (spv.array.items) |sp| {
                        if (sp != .object) continue;
                        const slug = if (sp.object.get("slug")) |v| (if (v == .string) v.string else continue) else continue;
                        var sit = sp.object.iterator();
                        while (sit.next()) |ent| {
                            const fkey = try std.fmt.allocPrint(alloc, "{s}.{s}", .{ slug, ent.key_ptr.* });
                            if (ledger_keys.get(fkey)) |lval| {
                                if (ledgerValueMatches(lval, ent.value_ptr.*)) {
                                    metrics_ok += 1;
                                } else {
                                    try failures.append(alloc, try std.fmt.allocPrint(alloc, "Rule 4: metric '{s}' disagrees with provenance_ledger.json", .{fkey}));
                                }
                            }
                        }
                    }
                }
            } else {
                // Flat schema (e.g. cosmos-mobile-primer): enforce 1:1 coverage & value match on ALL top-level numeric scalars!
                var sit = sv.object.iterator();
                while (sit.next()) |ent| {
                    if (jsonToFloat(ent.value_ptr.*) == null) continue;
                    if (ledger_keys.get(ent.key_ptr.*)) |lval| {
                        if (ledgerValueMatches(lval, ent.value_ptr.*)) {
                            metrics_ok += 1;
                        } else {
                            try failures.append(alloc, try std.fmt.allocPrint(alloc, "Rule 4: flat metric '{s}' value disagrees with provenance_ledger.json", .{ent.key_ptr.*}));
                        }
                    } else {
                        try failures.append(alloc, try std.fmt.allocPrint(alloc, "Rule 4: flat metric '{s}' missing from provenance_ledger.json", .{ent.key_ptr.*}));
                    }
                }
            }
        } else |_| {
            try failures.append(alloc, "Corrupt/unparseable JSON in data/summary_metrics.json");
        }
    } else |_| {
        try failures.append(alloc, "Missing data/summary_metrics.json");
    }

    if (metrics_ok == 0) {
        try failures.append(alloc, "Rule 4: 0 metrics verified between summary_metrics.json and provenance_ledger.json (metrics_covered=0 fails closed)");
    }

    const flist = try failures.toOwnedSlice(alloc);
    return .{
        .manifest_files = m_files,
        .manifest_verified = m_ok,
        .ledger_records = ledger_count,
        .metrics_verified = metrics_ok,
        .failures = flist,
        .passed = flist.len == 0,
    };
}

test "cleanProseText strips soft-hyphenated SHA-256, normalizes fullwidth digits, and strips trim specs" {
    const alloc = std.testing.allocator;
    const raw = "Verified via SHA\xc2\xad256 and SHA-\n256 48988322b9e7946a with 91.8% count \xef\xbc\x99\xef\xbc\x99 (612 \xc3\x97 792 pt)";
    const cleaned = try cleanProseText(alloc, raw, 612.0, 792.0);
    defer alloc.free(cleaned);
    try std.testing.expect(std.mem.find(u8, cleaned, "256") == null);
    try std.testing.expect(std.mem.find(u8, cleaned, "48988322") == null);
    try std.testing.expect(std.mem.find(u8, cleaned, "91.8%") != null);
    try std.testing.expect(std.mem.find(u8, cleaned, "99") != null);
    try std.testing.expect(std.mem.find(u8, cleaned, "612") == null);
}

test "collectCitationNumbers registers only exact cited f64 values without pairwise sums" {
    const alloc = std.testing.allocator;
    const raw =
        \\{"citations":[{"id":"c1","values":[1977, 1984, 0.5307]}]}
    ;
    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, raw, .{});
    defer parsed.deinit();
    var seen = std.AutoHashMap(u64, void).init(alloc);
    defer seen.deinit();
    var list: std.ArrayList(f64) = .empty;
    defer list.deinit(alloc);
    try collectCitationNumbers(alloc, parsed.value, &seen, &list);
    try std.testing.expectEqual(@as(usize, 3), list.items.len);
    try std.testing.expect(rule10IsGrounded(0.5307, 4, null, false, list.items));
    try std.testing.expect(!rule10IsGrounded(0.5312, 4, null, false, list.items));
    try std.testing.expect(!rule10IsGrounded(3961.0, 0, null, false, list.items));
}

test "rule10IsGrounded enforces half-ULP precision and rejects Issue #2 tolerance & exponent escapes" {
    const auth = [_]f64{ 0.5255, 64896.0, 1_000_000.0 };
    // Exact and true rounding PASS
    try std.testing.expect(rule10IsGrounded(0.5255, 4, null, false, &auth));
    try std.testing.expect(rule10IsGrounded(0.526, 3, null, false, &auth));
    try std.testing.expect(rule10IsGrounded(0.53, 2, null, false, &auth));
    try std.testing.expect(rule10IsGrounded(1e6, 0, 6, true, &auth));
    // Fabricated neighbors, p-values, and wrong exponents FAIL
    try std.testing.expect(!rule10IsGrounded(0.57, 2, null, false, &auth));
    try std.testing.expect(!rule10IsGrounded(0.5262, 4, null, false, &auth));
    try std.testing.expect(!rule10IsGrounded(0.5260, 4, null, false, &auth));
    try std.testing.expect(!rule10IsGrounded(0.049, 3, null, false, &auth));
    try std.testing.expect(!rule10IsGrounded(0.001, 3, null, false, &auth));
    try std.testing.expect(!rule10IsGrounded(1e7, 0, 7, true, &auth));
    try std.testing.expect(!rule10IsGrounded(9.7e9, 1, 9, false, &auth));
}
