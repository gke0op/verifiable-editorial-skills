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
    value_x100: i64,
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

fn isSpanCheckable(txt: []const u8) bool {
    if (txt.len == 0) return false;
    if (txt.len == 1) return isAsciiAlnum(txt[0]);
    for (txt) |ch| {
        if (isAsciiAlnum(ch) or ch >= 0x80) return true;
    }
    return false;
}

/// Gate 1: Background-sampled WCAG 2.1 AA contrast across every span.
pub fn auditContrast(
    alloc: std.mem.Allocator,
    io: std.Io,
    pdf_path: []const u8,
    pages: []const mupdf.PageData,
    tmp_tag: []const u8,
) !ContrastReport {
    const bg_pdf = try mupdf.makeBackgroundOnlyPdf(alloc, io, pdf_path, tmp_tag);
    defer std.Io.Dir.cwd().deleteFile(io, bg_pdf) catch {};

    var violations: std.ArrayList(ContrastViolation) = .empty;
    var total_spans: usize = 0;
    var worst_cr: i64 = 2100;

    var rs_buf: std.ArrayList(u8) = .empty;
    var gs_buf: std.ArrayList(u8) = .empty;
    var bs_buf: std.ArrayList(u8) = .empty;

    for (pages) |pg| {
        const bg_ppm = try mupdf.renderPagePpm(alloc, io, bg_pdf, pg.page_num, 72, tmp_tag);
        const w = bg_ppm.width;
        const h = bg_ppm.height;
        if (w == 0 or h == 0) continue;

        for (pg.spans) |sp| {
            if (!isSpanCheckable(sp.text)) continue;
            const ix0: usize = @intFromFloat(std.math.clamp(@round(sp.x0), 0.0, @as(f64, @floatFromInt(w - 1))));
            const ix1: usize = @max(ix0 + 1, @as(usize, @intFromFloat(std.math.clamp(@round(sp.x1), 0.0, @as(f64, @floatFromInt(w))))));
            const iy0: usize = @intFromFloat(std.math.clamp(@round(sp.y0), 0.0, @as(f64, @floatFromInt(h - 1))));
            const iy1: usize = @max(iy0 + 1, @as(usize, @intFromFloat(std.math.clamp(@round(sp.y1), 0.0, @as(f64, @floatFromInt(h))))));

            rs_buf.clearRetainingCapacity();
            gs_buf.clearRetainingCapacity();
            bs_buf.clearRetainingCapacity();
            const sx = @max(@as(usize, 1), (ix1 - ix0) / 12);
            const sy = @max(@as(usize, 1), (iy1 - iy0) / 6);
            var py = iy0;
            while (py < iy1) : (py += sy) {
                var px = ix0;
                while (px < ix1) : (px += sx) {
                    const pix = bg_ppm.pixelAt(px, py);
                    try rs_buf.append(alloc, pix.r);
                    try gs_buf.append(alloc, pix.g);
                    try bs_buf.append(alloc, pix.b);
                }
            }
            if (rs_buf.items.len == 0) continue;
            std.mem.sort(u8, rs_buf.items, {}, std.sort.asc(u8));
            std.mem.sort(u8, gs_buf.items, {}, std.sort.asc(u8));
            std.mem.sort(u8, bs_buf.items, {}, std.sort.asc(u8));
            const mid = rs_buf.items.len / 2;
            const bg_rgb = mupdf.Rgb{ .r = rs_buf.items[mid], .g = gs_buf.items[mid], .b = bs_buf.items[mid] };

            const cr = kernels.wcag_contrast_x100(sp.fg.r, sp.fg.g, sp.fg.b, bg_rgb.r, bg_rgb.g, bg_rgb.b);
            const size_x10: i64 = @intFromFloat(@round(sp.size * 10.0));
            total_spans += 1;
            if (cr < worst_cr) worst_cr = cr;

            if (!kernels.wcag_passes_aa(cr, size_x10, sp.is_bold)) {
                var fg_h: [7]u8 = undefined;
                var bg_h: [7]u8 = undefined;
                _ = sp.fg.formatHex(&fg_h);
                _ = bg_rgb.formatHex(&bg_h);
                const req: i64 = if (size_x10 >= 180 or (size_x10 >= 140 and sp.is_bold)) 300 else 450;
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

/// Gate 2: Deterministic geometric collision, trim overflow, orphan-headline & texture-energy audit.
pub fn auditGeometry(
    alloc: std.mem.Allocator,
    io: std.Io,
    pdf_path: []const u8,
    pages: []const mupdf.PageData,
    max_bg_rms: f64,
    tmp_tag: []const u8,
) !GeometryReport {
    const bg_pdf = try mupdf.makeBackgroundOnlyPdf(alloc, io, pdf_path, tmp_tag);
    defer std.Io.Dir.cwd().deleteFile(io, bg_pdf) catch {};
    const unclip_pdf = mupdf.makeUnclippedPdf(alloc, io, pdf_path, tmp_tag) catch null;
    defer if (unclip_pdf) |up| std.Io.Dir.cwd().deleteFile(io, up) catch {};
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

        // 0. PDF `W n` / `W* n` clip-path character slicing check:
        //    Combines version-independent `trace` `<clip_path>` stack glyph auditing (works on mutool 1.23+)
        //    with `stext` unclipped-vs-clipped differential frequency checking (mutool 1.24+).
        var missing_chars: usize = pg.trace_clipped_chars;
        if (unclip_pages) |upgs| {
            if (pg_idx < upgs.len) {
                var vis_freq: [128]usize = @splat(0);
                var raw_freq: [128]usize = @splat(0);
                for (pg.spans) |sp| {
                    for (sp.text) |ch| {
                        if (ch < 128 and isAsciiAlnum(ch)) vis_freq[ch] += 1;
                    }
                }
                for (upgs[pg_idx].spans) |sp| {
                    // Only count spans intersecting the visible trim box
                    if (sp.x1 < 0.0 or sp.y1 < 0.0 or sp.x0 > pg.width or sp.y0 > pg.height) continue;
                    for (sp.text) |ch| {
                        if (ch < 128 and isAsciiAlnum(ch)) raw_freq[ch] += 1;
                    }
                }
                var stext_missing: usize = 0;
                for (0..128) |ci| {
                    if (raw_freq[ci] > vis_freq[ci]) stext_missing += (raw_freq[ci] - vis_freq[ci]);
                }
                if (stext_missing > missing_chars) missing_chars = stext_missing;
            }
        }
        if (missing_chars > 0) {
            tot_clipped += 1;
            try issues.append(alloc, .{
                .page = pg.page_num,
                .kind = "clip_path_sliced_text",
                .detail = try std.fmt.allocPrint(alloc, "{d} alphanumeric character(s) sliced by W/W* clip path", .{missing_chars}),
            });
        }

        // 1. Pairwise AABB collisions via p2zig kernel
        for (pg.spans, 0..) |a, i| {
            const ax0: i64 = @intFromFloat(@round(a.x0 * 10.0));
            const ay0: i64 = @intFromFloat(@round(a.y0 * 10.0));
            const ax1: i64 = @intFromFloat(@round(a.x1 * 10.0));
            const ay1: i64 = @intFromFloat(@round(a.y1 * 10.0));
            var j: usize = i + 1;
            while (j < pg.spans.len) : (j += 1) {
                const b = pg.spans[j];
                if (@abs(a.dir_x - b.dir_x) > 0.05 or @abs(a.dir_y - b.dir_y) > 0.05) continue;
                const same_line = (a.block_idx == b.block_idx and a.line_idx == b.line_idx);
                const bx0: i64 = @intFromFloat(@round(b.x0 * 10.0));
                const by0: i64 = @intFromFloat(@round(b.y0 * 10.0));
                const bx1: i64 = @intFromFloat(@round(b.x1 * 10.0));
                const by1: i64 = @intFromFloat(@round(b.y1 * 10.0));
                const kind = kernels.span_collision_kind(ax0, ay0, ax1, ay1, bx0, by0, bx1, by1, same_line);
                if (kind != 0) {
                    tot_coll += 1;
                    const d = try std.fmt.allocPrint(alloc, "'{s}' vs '{s}'", .{
                        a.text[0..@min(a.text.len, 28)],
                        b.text[0..@min(b.text.len, 28)],
                    });
                    try issues.append(alloc, .{
                        .page = pg.page_num,
                        .kind = if (kind == 1) "same_line_overlap" else "cross_line_overlap",
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

        // 3. Wide-headline 1-word orphan wrap via p2zig kernel
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
                if (v_gap >= -4.0 and v_gap <= prev.size * 0.65 and @abs(cur.x0 - prev.x0) < 45.0 and @abs(cur.size - prev.size) < 2.0) {
                    continue;
                }
                break;
            }
            if (blk_end - hl_i >= 2) {
                const first_ln = h_lines.items[hl_i];
                const last_ln = h_lines.items[blk_end - 1];
                const w0_x10: i64 = @intFromFloat(@round((first_ln.x1 - first_ln.x0) * 10.0));
                const wl_x10: i64 = @intFromFloat(@round((last_ln.x1 - last_ln.x0) * 10.0));
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
pub fn parsePageSpec(alloc: std.mem.Allocator, spec: ?[]const u8, page_count: usize) ![]bool {
    const mask = try alloc.alloc(bool, page_count + 1);
    if (spec == null or spec.?.len == 0) {
        @memset(mask, true);
        mask[0] = false;
        return mask;
    }
    @memset(mask, false);
    var it = std.mem.splitScalar(u8, spec.?, ',');
    while (it.next()) |raw_part| {
        const part = std.mem.trim(u8, raw_part, " \t");
        if (part.len == 0) continue;
        if (std.mem.findScalar(u8, part, '-')) |dash| {
            const a = std.fmt.parseInt(usize, part[0..dash], 10) catch continue;
            const b = std.fmt.parseInt(usize, part[dash + 1 ..], 10) catch continue;
            var p = @max(@as(usize, 1), a);
            const hi = @min(page_count, b);
            while (p <= hi) : (p += 1) mask[p] = true;
        } else {
            const p = std.fmt.parseInt(usize, part, 10) catch continue;
            if (p >= 1 and p <= page_count) mask[p] = true;
        }
    }
    return mask;
}

/// Gate 3B: Exact clip-aware dual-key pixel-diff visible photography coverage (defeats raw rect inflation).
/// Uses pure-Zig image XObject rewriting + `p2zig --strict` bleed & coverage kernels.
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
    const mask = try parsePageSpec(alloc, page_spec, page_count);
    const dk = try mupdf.makeDualKeyPdfs(alloc, io, pdf_path, tmp_tag);
    defer std.Io.Dir.cwd().deleteFile(io, dk.pdf_a) catch {};
    defer std.Io.Dir.cwd().deleteFile(io, dk.pdf_b) catch {};

    var reports: std.ArrayList(PageCoverage) = .empty;
    var failures: std.ArrayList([]const u8) = .empty;
    const min_pct_x10: i64 = @intFromFloat(@round(min_pct * 10.0));

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
            const tag_a = try std.fmt.allocPrint(alloc, "{s}_ca", .{tmp_tag});
            const tag_b = try std.fmt.allocPrint(alloc, "{s}_cb", .{tmp_tag});
            const pa = try mupdf.renderPagePpm(alloc, io, dk.pdf_a, pg, 72, tag_a);
            const pb = try mupdf.renderPagePpm(alloc, io, dk.pdf_b, pg, 72, tag_b);
            const w = @min(pa.width, pb.width);
            const h = @min(pa.height, pb.height);
            const total_px: i64 = @intCast(w * h);
            var changed: i64 = 0;
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
                    if (ca.r != cb.r or ca.g != cb.g or ca.b != cb.b) {
                        changed += 1;
                        if (x <= 1) l_px += 1;
                        if (x + 2 >= w) r_px += 1;
                        if (y <= 1) t_px += 1;
                        if (y + 2 >= h) b_px += 1;
                    }
                }
            }
            if (total_px > 0) {
                pct = (@as(f64, @floatFromInt(changed)) / @as(f64, @floatFromInt(total_px))) * 100.0;
            }
            b_edges = kernels.bleed_edge_count(l_px, r_px, t_px, b_px, @intCast(w), @intCast(h));
            if (enforced) {
                ok = kernels.coverage_passes(changed, total_px, min_pct_x10, b_edges, min_bleed_edges);
            }
        } else if (enforced) {
            ok = (min_pct <= 0.0 and min_bleed_edges <= 0);
        }

        if (enforced) {
            enf_cnt += 1;
            if (pct < min_vis) min_vis = pct;
            sum_vis += pct;
            if (!ok) {
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

fn addExactScaledNum(alloc: std.mem.Allocator, seen: *std.AutoHashMap(i64, void), out: *std.ArrayList(i64), val: f64) !void {
    if (!std.math.isFinite(val) or @abs(val) > 1e14) return;
    const scaled: i64 = @intFromFloat(@round(val * 100.0));
    if (!seen.contains(scaled)) {
        try seen.put(scaled, {});
        try out.append(alloc, scaled);
    }
}

fn jsonToFloat(v: std.json.Value) ?f64 {
    return switch (v) {
        .integer => |iv| @floatFromInt(iv),
        .float => |fv| fv,
        else => null,
    };
}

/// Mirror Python `_derive_exact_ratios`: register exact percentages derived from species/country counts.
fn deriveExactSpeciesRatios(alloc: std.mem.Allocator, summary: std.json.Value, seen: *std.AutoHashMap(i64, void), out: *std.ArrayList(i64)) !void {
    if (summary != .object) return;
    const sp_val = summary.object.get("species") orelse return;
    if (sp_val != .array) return;
    for (sp_val.array.items) |sp| {
        if (sp != .object) continue;
        const tot = jsonToFloat(sp.object.get("gbif_total_occurrences") orelse continue) orelse continue;
        if (tot <= 0.0) continue;
        const tc_val = sp.object.get("top_countries") orelse continue;
        if (tc_val != .array) continue;
        for (tc_val.array.items) |c| {
            if (c != .object) continue;
            const cnt = jsonToFloat(c.object.get("count") orelse continue) orelse continue;
            const pct = (cnt / tot) * 100.0;
            try addScaledNum(alloc, seen, out, pct);
        }
    }
}

/// Mirror Python `_load_authorized_numbers` for `background_citations.json`: register ONLY explicit
/// `citations[].values[]` / `citations[].value` scalars (never synthetic pairwise sums of citation years).
fn collectCitationNumbers(alloc: std.mem.Allocator, parsed: std.json.Value, seen: *std.AutoHashMap(i64, void), out: *std.ArrayList(i64)) !void {
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
                    if (jsonToFloat(item)) |fv| try addExactScaledNum(alloc, seen, out, fv);
                }
            }
        }
        if (entry.object.get("value")) |v1| {
            if (jsonToFloat(v1)) |fv| try addExactScaledNum(alloc, seen, out, fv);
        }
    }
}

fn addScaledNum(alloc: std.mem.Allocator, seen: *std.AutoHashMap(i64, void), out: *std.ArrayList(i64), val: f64) !void {
    if (!std.math.isFinite(val) or @abs(val) > 1e14) return;
    const candidates = [_]f64{
        val,
        @round(val * 10.0) / 10.0,
        @round(val * 100.0) / 100.0,
        @round(val),
    };
    for (candidates) |cv| {
        const scaled: i64 = @intFromFloat(@round(cv * 100.0));
        if (!seen.contains(scaled)) {
            try seen.put(scaled, {});
            try out.append(alloc, scaled);
        }
    }
}

fn collectJsonNumbers(alloc: std.mem.Allocator, val: std.json.Value, seen: *std.AutoHashMap(i64, void), out: *std.ArrayList(i64)) !void {
    switch (val) {
        .integer => |iv| try addScaledNum(alloc, seen, out, @floatFromInt(iv)),
        .float => |fv| try addScaledNum(alloc, seen, out, fv),
        .object => |obj| {
            var it = obj.iterator();
            while (it.next()) |entry| {
                if (isSkipJsonKey(entry.key_ptr.*)) continue;
                try collectJsonNumbers(alloc, entry.value_ptr.*, seen, out);
            }
        },
        .array => |arr| {
            var all_num = arr.items.len > 0;
            var sum_v: f64 = 0.0;
            for (arr.items) |it| {
                switch (it) {
                    .integer => |iv| sum_v += @floatFromInt(iv),
                    .float => |fv| sum_v += fv,
                    else => all_num = false,
                }
            }
            if (all_num) {
                try addScaledNum(alloc, seen, out, sum_v);
                if (arr.items.len >= 2) {
                    var i: usize = 0;
                    while (i + 1 < arr.items.len) : (i += 1) {
                        const a_v: f64 = switch (arr.items[i]) {
                            .integer => |iv| @floatFromInt(iv),
                            .float => |fv| fv,
                            else => 0.0,
                        };
                        const b_v: f64 = switch (arr.items[i + 1]) {
                            .integer => |iv| @floatFromInt(iv),
                            .float => |fv| fv,
                            else => 0.0,
                        };
                        const pair = a_v + b_v;
                        try addScaledNum(alloc, seen, out, pair);
                        if (sum_v > 0.0) try addScaledNum(alloc, seen, out, (pair / sum_v) * 100.0);
                    }
                }
            }
            for (arr.items) |it| {
                try collectJsonNumbers(alloc, it, seen, out);
            }
        },
        else => {},
    }
}

fn isHexDigit(ch: u8) bool {
    return (ch >= '0' and ch <= '9') or (ch >= 'a' and ch <= 'f') or (ch >= 'A' and ch <= 'F');
}

fn isUrlOrDoiChar(ch: u8) bool {
    return ch > 32 and ch != ')' and ch != ']' and ch != ',' and ch != ';';
}

/// Strip soft hyphens (U+00AD), URLs, DOIs, long SHA-256 hex digests, and version strings (`PDF/UA-1`, `ISO 14289-1`, `Typst 0.15.1`).
pub fn cleanProseText(alloc: std.mem.Allocator, raw_in: []const u8) ![]u8 {
    // First remove UTF-8 soft hyphens (U+00AD = 0xC2 0xAD) so hyphenated tokens like "SHA\u00AD256" stay intact
    var norm: std.ArrayList(u8) = .empty;
    defer norm.deinit(alloc);
    try norm.ensureTotalCapacity(alloc, raw_in.len);
    var ni: usize = 0;
    while (ni < raw_in.len) {
        if (ni + 1 < raw_in.len and raw_in[ni] == 0xC2 and raw_in[ni + 1] == 0xAD) {
            ni += 2;
            continue;
        }
        try norm.append(alloc, raw_in[ni]);
        ni += 1;
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
        // Strip SHA-256 / SHA256 / line-wrapped SHA-\n256 + optional hex digest
        if (std.mem.startsWith(u8, raw[i..], "SHA")) {
            var k = i + 3;
            if (k < raw.len and raw[k] == '-') k += 1;
            while (k < raw.len and (raw[k] == ' ' or raw[k] == '\t' or raw[k] == '\n' or raw[k] == '\r')) : (k += 1) {}
            if (std.mem.startsWith(u8, raw[k..], "256")) {
                k += 3;
                while (k < raw.len and (raw[k] == ' ' or raw[k] == '\t' or raw[k] == ':')) : (k += 1) {}
                var h = k;
                while (h < raw.len and isHexDigit(raw[h])) : (h += 1) {}
                if (h - k >= 6) k = h;
                i = k;
                try out.append(alloc, ' ');
                continue;
            }
        }
        // Strip standard/version tokens: PDF/UA-1, ISO 14289-1, WCAG 2.1, Typst 0.15.1, WeasyPrint 67.0, veraPDF 1.30
        const prefixes = [_][]const u8{ "PDF/UA-", "ISO ", "WCAG ", "Typst ", "WeasyPrint ", "veraPDF ", "term_id=" };
        var matched_pre = false;
        for (prefixes) |pre| {
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
        if (matched_pre) continue;

        // Strip lowercase 8..64 char hex hashes (e.g., 163cadae3baa...)
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
    return isAsciiAlnum(ch) or ch == '_' or ch == '#' or ch == '-';
}

/// Gate 3 (Rule 10): Post-render PDF prose-to-ledger grounding via p2zig kernel.
pub fn auditProse(
    alloc: std.mem.Allocator,
    io: std.Io,
    pages: []const mupdf.PageData,
    ledger_path: ?[]const u8,
    summary_path: ?[]const u8,
    citations_path: ?[]const u8,
    manifest_path: ?[]const u8,
) !ProseReport {
    var seen = std.AutoHashMap(i64, void).init(alloc);
    var auth_list: std.ArrayList(i64) = .empty;

    if (ledger_path) |lp| {
        const raw = try std.Io.Dir.cwd().readFileAlloc(io, lp, alloc, .unlimited);
        const parsed = try std.json.parseFromSliceLeaky(std.json.Value, alloc, raw, .{});
        try collectJsonNumbers(alloc, parsed, &seen, &auth_list);
        switch (parsed) {
            .array => |a| try addScaledNum(alloc, &seen, &auth_list, @floatFromInt(a.items.len)),
            .object => |o| try addScaledNum(alloc, &seen, &auth_list, @floatFromInt(o.count())),
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
        try addScaledNum(alloc, &seen, &auth_list, @floatFromInt(cnt));
    }

    // Structural metadata ordinals: -1, 0..max(12, page_count), standard print specs
    try addScaledNum(alloc, &seen, &auth_list, -1.0);
    const max_ord = @max(@as(usize, 12), pages.len);
    var ord: usize = 0;
    while (ord <= max_ord) : (ord += 1) {
        try addScaledNum(alloc, &seen, &auth_list, @floatFromInt(ord));
    }
    const structurals = [_]f64{ 612, 792, 960, 540, 300, 180, 72, 50, 52, 67.0, 2.1, 2026, 2025, 2024 };
    for (structurals) |sv| try addScaledNum(alloc, &seen, &auth_list, sv);

    const auth_slice = auth_list.items;
    var ungrounded: std.ArrayList(UngroundedToken) = .empty;
    var total_checked: usize = 0;

    for (pages) |pg| {
        const cleaned = try cleanProseText(alloc, pg.prose_text);
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
            if (cleaned[i] == '+' or cleaned[i] == '-') {
                if (i + 1 < cleaned.len and cleaned[i + 1] >= '0' and cleaned[i + 1] <= '9') {
                    has_sign = true;
                    sign_neg = (cleaned[i] == '-');
                    num_start = i + 1;
                } else {
                    i += 1;
                    continue;
                }
            } else if (i + 3 < cleaned.len and cleaned[i] == 0xE2 and cleaned[i + 1] == 0x88 and cleaned[i + 2] == 0x92) {
                // UTF-8 Unicode minus '−' (U+2212)
                if (cleaned[i + 3] >= '0' and cleaned[i + 3] <= '9') {
                    has_sign = true;
                    sign_neg = true;
                    num_start = i + 3;
                } else {
                    i += 3;
                    continue;
                }
            } else if (cleaned[i] < '0' or cleaned[i] > '9') {
                i += 1;
                continue;
            }

            var j = num_start;
            var digits_buf: [64]u8 = undefined;
            var dlen: usize = 0;
            var seen_dot = false;
            while (j < cleaned.len) {
                const ch = cleaned[j];
                if (ch >= '0' and ch <= '9') {
                    if (dlen < digits_buf.len) {
                        digits_buf[dlen] = ch;
                        dlen += 1;
                    }
                    j += 1;
                } else if (ch == ',' and !seen_dot and j + 3 < cleaned.len and
                    cleaned[j + 1] >= '0' and cleaned[j + 1] <= '9' and
                    cleaned[j + 2] >= '0' and cleaned[j + 2] <= '9' and
                    cleaned[j + 3] >= '0' and cleaned[j + 3] <= '9')
                {
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
            const raw_num = cleaned[num_start..j];
            var tok_end = j;
            if (tok_end < cleaned.len and cleaned[tok_end] == '%') tok_end += 1;
            const next_ok = (tok_end == cleaned.len) or !(isAsciiAlnum(cleaned[tok_end]) or cleaned[tok_end] == '_');
            i = tok_end;
            if (!next_ok or dlen == 0) continue;

            // Ignore leading-zero 2-digit plate/page ordinals "01".."12"
            if (!has_sign and raw_num.len == 2 and raw_num[0] == '0') continue;

            var parsed_v = std.fmt.parseFloat(f64, digits_buf[0..dlen]) catch continue;
            if (sign_neg) parsed_v = -parsed_v;
            if (@abs(parsed_v) > 1e14) continue;
            const val_x100: i64 = @intFromFloat(@round(parsed_v * 100.0));

            total_checked += 1;
            if (!kernels.rule10_is_grounded_x100(val_x100, auth_slice)) {
                const c0 = if (tok_start > 28) tok_start - 28 else 0;
                const c1 = @min(cleaned.len, tok_end + 28);
                try ungrounded.append(alloc, .{
                    .page = pg.page_num,
                    .token = try alloc.dupe(u8, cleaned[tok_start..tok_end]),
                    .value_x100 = val_x100,
                    .context = try alloc.dupe(u8, cleaned[c0..c1]),
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

/// Gate 4: Print Pre-Press & ISO 14289-1 (`PDF/UA-1`) certification audit.
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
    const min_dpi_x10: i64 = @intFromFloat(@round(min_dpi * 10.0));

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
        // Simulated CMYK GCR TAC via p2zig kernel at 36 DPI
        const ppm = try mupdf.renderPagePpm(alloc, io, pdf_path, pg.page_num, 36, tmp_tag);
        tacs.clearRetainingCapacity();
        var off: usize = 0;
        while (off + 2 < ppm.pixels.len) : (off += 12) {
            const tac = kernels.cmyk_gcr_tac_x10(ppm.pixels[off], ppm.pixels[off + 1], ppm.pixels[off + 2]);
            try tacs.append(alloc, tac);
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
    const max_tac_x10: i64 = @intFromFloat(@round(max_tac_pct * 10.0));
    if (p99_tac_x10 > max_tac_x10) {
        try failures.append(alloc, try std.fmt.allocPrint(alloc, "Simulated CMYK p99 TAC {d:.1}% > {d:.0}%", .{
            @as(f64, @floatFromInt(p99_tac_x10)) / 10.0,
            max_tac_pct,
        }));
    }

    const ua_struct_pass = cat.marked and cat.has_struct_tree and cat.has_lang and cat.has_title;
    if (require_ua and !ua_struct_pass) {
        try failures.append(alloc, "PDF/UA structure incomplete (requires /MarkInfo, /StructTreeRoot, /Lang, Title)");
    }

    const vp = if (enable_verapdf) runVeraPdf(alloc, io, pdf_path) else VeraPdfResult{
        .available = false,
        .compliant = false,
        .passed_rules = 0,
        .failed_rules = 0,
    };
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

/// Gate 5 (Pure-Zig Rule 4 + Rule 6 Compilation Latch): verifies SHA-256 manifest of `data/raw/*`
/// and 1:1 coverage of `data/summary_metrics.json["metrics"]` inside `data/provenance_ledger.json`.
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
    var m_files: usize = 0;
    var m_ok: usize = 0;
    var ln_it = std.mem.splitScalar(u8, manifest_raw, '\n');
    while (ln_it.next()) |ln| {
        const trimmed = std.mem.trim(u8, ln, " \t\r");
        if (trimmed.len == 0) continue;
        var sp = std.mem.tokenizeAny(u8, trimmed, " \t");
        const expected_hex = sp.next() orelse continue;
        const rel_file = sp.next() orelse continue;
        m_files += 1;
        const full_path = if (std.mem.startsWith(u8, rel_file, "data/"))
            try std.fmt.allocPrint(alloc, "{s}/{s}", .{ project_dir, rel_file })
        else
            try std.fmt.allocPrint(alloc, "{s}/data/raw/{s}", .{ project_dir, rel_file });

        const actual = sha256HexFile(alloc, io, full_path) catch {
            try failures.append(alloc, try std.fmt.allocPrint(alloc, "Missing raw file listed in manifest: {s}", .{rel_file}));
            continue;
        };
        if (std.mem.eql(u8, expected_hex, &actual)) {
            m_ok += 1;
            const key_owned = try alloc.dupe(u8, rel_file);
            try manifest_map.put(key_owned, actual);
        } else {
            try failures.append(alloc, try std.fmt.allocPrint(alloc, "SHA-256 mismatch on {s}", .{rel_file}));
        }
    }

    // Verify Rule 4 provenance ledger coverage
    var ledger_keys = std.StringHashMap(void).init(alloc);
    var ledger_count: usize = 0;
    if (std.Io.Dir.cwd().readFileAlloc(io, ledger_path, alloc, .unlimited)) |lraw| {
        const lval = std.json.parseFromSliceLeaky(std.json.Value, alloc, lraw, .{}) catch null;
        if (lval) |lv| {
            switch (lv) {
                .array => |arr| {
                    ledger_count = arr.items.len;
                    for (arr.items) |item| {
                        if (item == .object) {
                            if (item.object.get("metric_id")) |mk| {
                                if (mk == .string) try ledger_keys.put(try alloc.dupe(u8, mk.string), {});
                            }
                        }
                    }
                },
                .object => |obj| {
                    ledger_count = obj.count();
                    var oit = obj.iterator();
                    while (oit.next()) |ent| {
                        try ledger_keys.put(try alloc.dupe(u8, ent.key_ptr.*), {});
                    }
                },
                else => {},
            }
        }
    } else |_| {
        try failures.append(alloc, "Missing data/provenance_ledger.json");
    }

    var metrics_ok: usize = 0;
    if (std.Io.Dir.cwd().readFileAlloc(io, summary_path, alloc, .unlimited)) |sraw| {
        const sval = std.json.parseFromSliceLeaky(std.json.Value, alloc, sraw, .{}) catch null;
        if (sval) |sv| {
            if (sv == .object) {
                if (sv.object.get("metrics")) |mv| {
                    if (mv == .object) {
                        var mit = mv.object.iterator();
                        while (mit.next()) |ent| {
                            if (ledger_keys.contains(ent.key_ptr.*)) {
                                metrics_ok += 1;
                            } else {
                                try failures.append(alloc, try std.fmt.allocPrint(alloc, "Rule 4: metric '{s}' missing from provenance_ledger.json", .{ent.key_ptr.*}));
                            }
                        }
                    }
                }
            }
        }
    } else |_| {
        try failures.append(alloc, "Missing data/summary_metrics.json");
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

test "cleanProseText strips soft-hyphenated SHA-256 and line-wrapped SHA-256" {
    const alloc = std.testing.allocator;
    const raw = "Verified via SHA\xc2\xad256 and SHA-\n256 48988322b9e7946a with 91.8%";
    const cleaned = try cleanProseText(alloc, raw);
    defer alloc.free(cleaned);
    try std.testing.expect(std.mem.find(u8, cleaned, "256") == null);
    try std.testing.expect(std.mem.find(u8, cleaned, "48988322") == null);
    try std.testing.expect(std.mem.find(u8, cleaned, "91.8%") != null);
}

test "collectCitationNumbers registers only explicit cited values without pairwise sums" {
    const alloc = std.testing.allocator;
    const raw =
        \\{"citations":[{"id":"c1","values":[1977, 1984, 0.5307]}]}
    ;
    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, raw, .{});
    defer parsed.deinit();
    var seen = std.AutoHashMap(i64, void).init(alloc);
    defer seen.deinit();
    var list: std.ArrayList(i64) = .empty;
    defer list.deinit(alloc);
    try collectCitationNumbers(alloc, parsed.value, &seen, &list);
    // Exactly 3 explicit values (no 1977+1984=3961 pairwise sum bloat!)
    try std.testing.expectEqual(@as(usize, 3), list.items.len);
    try std.testing.expect(seen.contains(197700));
    try std.testing.expect(seen.contains(198400));
    try std.testing.expect(seen.contains(53));
    try std.testing.expect(!seen.contains(396100));
}
