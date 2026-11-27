//! Pillar #6 — PDF Sample Dissector & Archetype Injector (`vedit inject <sample.pdf> --name <slug>`).
//! Dissects any external reference PDF into machine-readable Design DNA:
//!   • Trim dimensions, aspect class, and live margins
//!   • Measured 60-30-10 chromatic palette + auto-verified WCAG contrast ratios (via p2zig)
//!   • Typographic scale ladder & cross-platform SIL-OFL font mapping
//!   • Page-by-page column grid, vertical fill %, photo coverage %, and archetype cadence (via p2zig)
//! Emits `archetypes/<slug>/{blueprint.json, skeleton.typ, AGENT_CARD.md}` and updates `archetypes/registry.json`.

const std = @import("std");
const kernels = @import("kernels_p2zig.zig");
const mupdf = @import("mupdf.zig");

pub const PageDNA = struct {
    page_num: usize,
    width_pt: f64,
    height_pt: f64,
    text_spans: usize,
    image_count: usize,
    stroke_count: usize,
    columns: i64,
    vertical_fill_pct: f64,
    photo_coverage_pct: f64,
    max_font_pt: f64,
    archetype_code: i64,
    archetype_name: []const u8,
};

pub const FontRole = struct {
    role: []const u8,
    source_font: []const u8,
    sil_ofl_map: []const u8,
    size_pt: f64,
};

pub const Blueprint = struct {
    slug: []const u8,
    source_pdf: []const u8,
    source_sha256: [64]u8,
    page_count: usize,
    trim_w_pt: f64,
    trim_h_pt: f64,
    format_class: []const u8,
    polarity: []const u8, // "light" or "dark"
    margin_top_pt: f64,
    margin_bottom_pt: f64,
    margin_left_pt: f64,
    margin_right_pt: f64,
    canvas_bg: mupdf.Rgb,
    surface_tint: mupdf.Rgb,
    primary_ink: mupdf.Rgb,
    muted_ink: mupdf.Rgb,
    accent_primary: mupdf.Rgb,
    accent_secondary: mupdf.Rgb,
    ink_contrast_x100: i64,
    accent_contrast_x100: i64,
    display_font: FontRole,
    body_font: FontRole,
    ui_sans_font: FontRole,
    mono_font: FontRole,
    avg_fill_pct: f64,
    avg_photo_pct: f64,
    pages: []const PageDNA,
};

pub fn archetypeName(code: i64) []const u8 {
    return switch (code) {
        0 => "cover_hero",
        1 => "full_bleed_plate",
        2 => "split_photo_editorial",
        3 => "data_exhibit_ledger",
        4 => "asymmetric_monograph",
        5 => "colophon_references",
        else => "narrative_spread",
    };
}

fn containsFold(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}

/// Map any dissected commercial/OS font family to our bundled SHA-256 verified SIL-OFL font stack.
pub fn mapToSilOfl(font_name: []const u8, role: []const u8) []const u8 {
    if (containsFold(font_name, "mono") or containsFold(font_name, "courier") or containsFold(font_name, "menlo") or containsFold(font_name, "consolas") or std.mem.eql(u8, role, "mono")) {
        return "IBM Plex Mono";
    }
    if (containsFold(font_name, "didot") or containsFold(font_name, "bodoni") or containsFold(font_name, "cormorant") or containsFold(font_name, "garamond") or containsFold(font_name, "playfair")) {
        return "Cormorant Garamond";
    }
    if (containsFold(font_name, "charter") or containsFold(font_name, "georgia") or containsFold(font_name, "serif") or containsFold(font_name, "baskerville") or containsFold(font_name, "times") or containsFold(font_name, "palatino")) {
        return if (std.mem.eql(u8, role, "display")) "Cormorant Garamond" else "Source Serif 4";
    }
    if (containsFold(font_name, "inter") or containsFold(font_name, "helvetica") or containsFold(font_name, "arial") or containsFold(font_name, "sans") or containsFold(font_name, "futura") or containsFold(font_name, "avenir") or containsFold(font_name, "neue")) {
        return "Inter";
    }
    if (std.mem.eql(u8, role, "display")) return "Cormorant Garamond";
    if (std.mem.eql(u8, role, "body")) return "Source Serif 4";
    return "Inter";
}

fn rgbSat(rgb: mupdf.Rgb) u16 {
    const mx = @max(rgb.r, @max(rgb.g, rgb.b));
    const mn = @min(rgb.r, @min(rgb.g, rgb.b));
    return @as(u16, mx) - @as(u16, mn);
}

fn rgbLuma(rgb: mupdf.Rgb) f64 {
    return 0.299 * @as(f64, @floatFromInt(rgb.r)) +
        0.587 * @as(f64, @floatFromInt(rgb.g)) +
        0.114 * @as(f64, @floatFromInt(rgb.b));
}

fn colorDistSq(a: mupdf.Rgb, b: mupdf.Rgb) i32 {
    const dr: i32 = @as(i32, a.r) - @as(i32, b.r);
    const dg: i32 = @as(i32, a.g) - @as(i32, b.g);
    const db: i32 = @as(i32, a.b) - @as(i32, b.b);
    return dr * dr + dg * dg + db * db;
}

fn quantKey(rgb: mupdf.Rgb) u24 {
    const rq: u24 = (rgb.r / 8) * 8;
    const gq: u24 = (rgb.g / 8) * 8;
    const bq: u24 = (rgb.b / 8) * 8;
    return (rq << 16) | (gq << 8) | bq;
}

fn unpackKey(k: u24) mupdf.Rgb {
    return .{
        .r = @intCast((k >> 16) & 0xff),
        .g = @intCast((k >> 8) & 0xff),
        .b = @intCast(k & 0xff),
    };
}

/// Dissect any reference PDF into a complete structural Blueprint (Design DNA).
pub fn dissectPdf(
    alloc: std.mem.Allocator,
    io: std.Io,
    pdf_path: []const u8,
    slug: []const u8,
    tmp_tag: []const u8,
) !Blueprint {
    const audit = @import("audit.zig");
    const pages = try mupdf.extractPages(alloc, io, pdf_path);
    if (pages.len == 0) return error.EmptyPdf;
    const src_sha = try audit.sha256HexFile(alloc, io, pdf_path);

    const trim_w = pages[0].width;
    const trim_h = pages[0].height;
    const aspect = trim_w / @max(1.0, trim_h);
    const fmt_class: []const u8 = if (aspect >= 1.55)
        "widescreen_16x9"
    else if (aspect >= 1.15)
        "landscape_spread"
    else if (trim_w <= 430.0 and aspect <= 0.68)
        "mobile_portrait_9x16"
    else if (@abs(trim_w - 595.0) <= 6.0 and @abs(trim_h - 842.0) <= 6.0)
        "a4_portrait"
    else
        "letter_portrait";

    // 1. Sample true rendered pixels across up to 4 representative pages to measure 60-30-10 background & polarity
    var bg_hist = std.AutoHashMap(u24, u64).init(alloc);
    var acc_hist = std.AutoHashMap(u24, u64).init(alloc);
    const sample_limit = @min(pages.len, 4);
    var pi: usize = 0;
    while (pi < sample_limit) : (pi += 1) {
        const ppm = try mupdf.renderPagePpm(alloc, io, pdf_path, pages[pi].page_num, 36, tmp_tag);
        var off: usize = 0;
        while (off + 2 < ppm.pixels.len) : (off += 12) {
            const px = mupdf.Rgb{ .r = ppm.pixels[off], .g = ppm.pixels[off + 1], .b = ppm.pixels[off + 2] };
            const qk = quantKey(px);
            const gop = try bg_hist.getOrPut(qk);
            if (gop.found_existing) gop.value_ptr.* += 1 else gop.value_ptr.* = 1;
            if (rgbSat(px) >= 42) {
                const ag = try acc_hist.getOrPut(qk);
                if (ag.found_existing) ag.value_ptr.* += 1 else ag.value_ptr.* = 1;
            }
        }
    }

    // Dominant canvas background (exact 60% bucket)
    var canvas_bg = mupdf.Rgb{ .r = 250, .g = 249, .b = 246 };
    var best_bg_cnt: u64 = 0;
    var bg_it = bg_hist.iterator();
    while (bg_it.next()) |ent| {
        if (ent.value_ptr.* > best_bg_cnt) {
            best_bg_cnt = ent.value_ptr.*;
            canvas_bg = unpackKey(ent.key_ptr.*);
        }
    }
    const is_dark = rgbLuma(canvas_bg) < 110.0;
    const polarity: []const u8 = if (is_dark) "dark" else "light";

    // Surface tint: subtle contrast step from canvas_bg
    const surface_tint = if (is_dark)
        mupdf.Rgb{
            .r = @min(@as(u16, 255), @as(u16, canvas_bg.r) + 14),
            .g = @min(@as(u16, 255), @as(u16, canvas_bg.g) + 18),
            .b = @min(@as(u16, 255), @as(u16, canvas_bg.b) + 24),
        }
    else
        mupdf.Rgb{
            .r = if (canvas_bg.r > 12) canvas_bg.r - 10 else 240,
            .g = if (canvas_bg.g > 14) canvas_bg.g - 12 else 236,
            .b = if (canvas_bg.b > 18) canvas_bg.b - 16 else 228,
        };

    // Primary & muted inks measured from text spans
    var ink_hist = std.AutoHashMap(u24, u64).init(alloc);
    for (pages) |pg| {
        for (pg.spans) |sp| {
            const k = quantKey(sp.fg);
            const gop = try ink_hist.getOrPut(k);
            const w: u64 = @intCast(sp.text.len);
            if (gop.found_existing) gop.value_ptr.* += w else gop.value_ptr.* = w;
            if (rgbSat(sp.fg) >= 42) {
                const ag = try acc_hist.getOrPut(k);
                if (ag.found_existing) ag.value_ptr.* += w * 4 else ag.value_ptr.* = w * 4;
            }
        }
        for (pg.graphics) |gr| {
            if (rgbSat(gr.rgb) >= 42) {
                const k = quantKey(gr.rgb);
                const ag = try acc_hist.getOrPut(k);
                if (ag.found_existing) ag.value_ptr.* += 20 else ag.value_ptr.* = 20;
            }
        }
    }

    var primary_ink = if (is_dark) mupdf.Rgb{ .r = 244, .g = 246, .b = 248 } else mupdf.Rgb{ .r = 22, .g = 26, .b = 32 };
    var best_ink_w: u64 = 0;
    var ink_it = ink_hist.iterator();
    while (ink_it.next()) |ent| {
        const cand = unpackKey(ent.key_ptr.*);
        const cr = kernels.wcag_contrast_x100(cand.r, cand.g, cand.b, canvas_bg.r, canvas_bg.g, canvas_bg.b);
        if (cr >= 450 and ent.value_ptr.* > best_ink_w) {
            best_ink_w = ent.value_ptr.*;
            primary_ink = cand;
        }
    }
    const muted_ink = if (is_dark)
        mupdf.Rgb{ .r = 196, .g = 206, .b = 218 }
    else
        mupdf.Rgb{ .r = 68, .g = 80, .b = 92 };

    // Top 2 distinct saturated signal accents that clear WCAG AA on canvas_bg
    var acc1 = if (is_dark) mupdf.Rgb{ .r = 56, .g = 189, .b = 248 } else mupdf.Rgb{ .r = 3, .g = 94, .b = 158 };
    var acc2 = if (is_dark) mupdf.Rgb{ .r = 52, .g = 211, .b = 153 } else mupdf.Rgb{ .r = 20, .g = 99, .b = 70 };
    var best_a1: u64 = 0;
    var acc_it1 = acc_hist.iterator();
    while (acc_it1.next()) |ent| {
        const cand = unpackKey(ent.key_ptr.*);
        const cr = kernels.wcag_contrast_x100(cand.r, cand.g, cand.b, canvas_bg.r, canvas_bg.g, canvas_bg.b);
        if (cr >= 450 and ent.value_ptr.* > best_a1) {
            best_a1 = ent.value_ptr.*;
            acc1 = cand;
        }
    }
    var best_a2: u64 = 0;
    var acc_it2 = acc_hist.iterator();
    while (acc_it2.next()) |ent| {
        const cand = unpackKey(ent.key_ptr.*);
        const cr = kernels.wcag_contrast_x100(cand.r, cand.g, cand.b, canvas_bg.r, canvas_bg.g, canvas_bg.b);
        if (cr >= 450 and colorDistSq(cand, acc1) >= 2400 and ent.value_ptr.* > best_a2) {
            best_a2 = ent.value_ptr.*;
            acc2 = cand;
        }
    }

    // 2. Typography ladder & live margins across all pages
    var disp_font: []const u8 = "Cormorant Garamond";
    var disp_size: f64 = 24.0;
    var body_font: []const u8 = "Source Serif 4";
    var body_size: f64 = 9.2;
    var sans_font: []const u8 = "Inter";
    var sans_size: f64 = 7.5;
    var mono_font: []const u8 = "IBM Plex Mono";
    var mono_size: f64 = 7.2;

    var max_disp_seen: f64 = 0.0;
    var body_chars_by_font = std.StringHashMap(u64).init(alloc);
    var body_size_sum: f64 = 0.0;
    var body_size_w: f64 = 0.0;
    var found_mono = false;
    var found_sans = false;

    var min_left: f64 = trim_w;
    var max_right: f64 = 0.0;
    var min_top: f64 = trim_h;
    var max_bot: f64 = 0.0;

    var page_dnas: std.ArrayList(PageDNA) = .empty;
    var fill_sum: f64 = 0.0;
    var photo_sum: f64 = 0.0;
    var col_x0s: std.ArrayList(i64) = .empty;
    var col_x1s: std.ArrayList(i64) = .empty;
    const YInterval = struct { y0: f64, y1: f64 };
    var y_intervals: std.ArrayList(YInterval) = .empty;

    for (pages) |pg| {
        col_x0s.clearRetainingCapacity();
        col_x1s.clearRetainingCapacity();
        y_intervals.clearRetainingCapacity();
        var pg_max_font: f64 = 0.0;

        for (pg.spans) |sp| {
            if (sp.size > pg_max_font) pg_max_font = sp.size;
            if (sp.y0 >= 18.0 and sp.y1 <= pg.height - 18.0 and sp.y1 > sp.y0) {
                const pad = @min(6.0, sp.size * 0.35);
                try y_intervals.append(alloc, .{
                    .y0 = @max(18.0, sp.y0 - pad),
                    .y1 = @min(pg.height - 18.0, sp.y1 + pad),
                });
                min_left = @min(min_left, sp.x0);
                max_right = @max(max_right, sp.x1);
                min_top = @min(min_top, sp.y0);
                max_bot = @max(max_bot, sp.y1);
            }
            if (sp.size >= 16.0 and sp.size > max_disp_seen and sp.text.len >= 4) {
                max_disp_seen = sp.size;
                disp_font = sp.font;
                disp_size = @min(34.0, sp.size);
            }
            if (sp.size >= 7.5 and sp.size <= 12.5 and sp.text.len >= 12) {
                const gop = try body_chars_by_font.getOrPut(sp.font);
                const w: u64 = @intCast(sp.text.len);
                if (gop.found_existing) gop.value_ptr.* += w else gop.value_ptr.* = w;
                body_size_sum += sp.size * @as(f64, @floatFromInt(w));
                body_size_w += @as(f64, @floatFromInt(w));
                const rx0 = mupdf.checkedRoundInt(i64, sp.x0, -1e6, 1e6) catch continue;
                const rx1 = mupdf.checkedRoundInt(i64, sp.x1, -1e6, 1e6) catch continue;
                try col_x0s.append(alloc, rx0);
                try col_x1s.append(alloc, rx1);
            }
            if (!found_mono and (containsFold(sp.font, "mono") or containsFold(sp.font, "courier"))) {
                found_mono = true;
                mono_font = sp.font;
                mono_size = std.math.clamp(sp.size, 6.4, 8.5);
            }
            if (!found_sans and (containsFold(sp.font, "inter") or containsFold(sp.font, "helvetica") or containsFold(sp.font, "sans"))) {
                found_sans = true;
                sans_font = sp.font;
                sans_size = std.math.clamp(sp.size, 6.5, 9.0);
            }
        }

        // Deduplicated union photo coverage on a 100x100 grid (immune to overlapping/stacked image inflation)
        var photo_grid: [100 * 100]bool = @splat(false);
        for (pg.images) |im| {
            const cx0 = std.math.clamp(im.x0, 0.0, pg.width);
            const cx1 = std.math.clamp(im.x1, 0.0, pg.width);
            const cy0 = std.math.clamp(im.y0, 0.0, pg.height);
            const cy1 = std.math.clamp(im.y1, 0.0, pg.height);
            if (cx1 > cx0 and cy1 > cy0 and pg.width > 0.0 and pg.height > 0.0) {
                try y_intervals.append(alloc, .{ .y0 = cy0, .y1 = cy1 });
                const gx0: usize = @min(@as(usize, 99), @as(usize, @intFromFloat(@floor((cx0 / pg.width) * 100.0))));
                const gx1: usize = @min(@as(usize, 100), @max(gx0 + 1, @as(usize, @intFromFloat(@ceil((cx1 / pg.width) * 100.0)))));
                const gy0: usize = @min(@as(usize, 99), @as(usize, @intFromFloat(@floor((cy0 / pg.height) * 100.0))));
                const gy1: usize = @min(@as(usize, 100), @max(gy0 + 1, @as(usize, @intFromFloat(@ceil((cy1 / pg.height) * 100.0)))));
                for (gy0..gy1) |gy| {
                    for (gx0..gx1) |gx| {
                        photo_grid[gy * 100 + gx] = true;
                    }
                }
            }
        }
        var photo_cells: usize = 0;
        for (photo_grid) |cov| {
            if (cov) photo_cells += 1;
        }
        const photo_pct = (@as(f64, @floatFromInt(photo_cells)) / 10000.0) * 100.0;

        // True vertical fill via merged union of occupied vertical bands (immune to top+bottom sparse void spoofing)
        const live_h = @max(1.0, pg.height - 72.0);
        var occupied_y: f64 = 0.0;
        if (y_intervals.items.len > 0) {
            std.mem.sort(YInterval, y_intervals.items, {}, struct {
                fn lessThan(_: void, a: YInterval, b: YInterval) bool {
                    return a.y0 < b.y0;
                }
            }.lessThan);
            var cur_y0 = y_intervals.items[0].y0;
            var cur_y1 = y_intervals.items[0].y1;
            for (y_intervals.items[1..]) |iv| {
                if (iv.y0 <= cur_y1) {
                    if (iv.y1 > cur_y1) cur_y1 = iv.y1;
                } else {
                    occupied_y += (cur_y1 - cur_y0);
                    cur_y0 = iv.y0;
                    cur_y1 = iv.y1;
                }
            }
            occupied_y += (cur_y1 - cur_y0);
        }
        const fill_pct = @min(100.0, (occupied_y / live_h) * 100.0);

        const pg_w_i = mupdf.checkedRoundInt(i64, pg.width, 1.0, 1e6) catch 612;
        const max_f_x10 = mupdf.checkedRoundInt(i64, pg_max_font * 10.0, 0.0, 1e6) catch 0;
        const cols = kernels.detect_grid_columns(col_x0s.items, col_x1s.items, pg_w_i);
        const arch_code = kernels.classify_page_archetype(
            @intFromFloat(@round(photo_pct * 10.0)),
            @intCast(pg.spans.len),
            max_f_x10,
            cols,
            @intCast(pg.page_num),
            @intCast(pages.len),
        );

        fill_sum += fill_pct;
        photo_sum += photo_pct;
        try page_dnas.append(alloc, .{
            .page_num = pg.page_num,
            .width_pt = pg.width,
            .height_pt = pg.height,
            .text_spans = pg.spans.len,
            .image_count = pg.images.len,
            .stroke_count = pg.stroke_count,
            .columns = cols,
            .vertical_fill_pct = fill_pct,
            .photo_coverage_pct = photo_pct,
            .max_font_pt = pg_max_font,
            .archetype_code = arch_code,
            .archetype_name = archetypeName(arch_code),
        });
    }

    var best_body_w: u64 = 0;
    var bf_it = body_chars_by_font.iterator();
    while (bf_it.next()) |ent| {
        if (ent.value_ptr.* > best_body_w) {
            best_body_w = ent.value_ptr.*;
            body_font = ent.key_ptr.*;
        }
    }
    if (body_size_w > 0.0) {
        body_size = std.math.clamp(body_size_sum / body_size_w, 8.2, 11.0);
    }

    const m_left = std.math.clamp(if (min_left < trim_w) min_left else 48.0, 28.0, 72.0);
    const m_right = std.math.clamp(if (max_right > 0.0) trim_w - max_right else 48.0, 28.0, 72.0);
    const m_top = std.math.clamp(if (min_top < trim_h) min_top else 42.0, 28.0, 68.0);
    const m_bot = std.math.clamp(if (max_bot > 0.0) trim_h - max_bot else 42.0, 28.0, 68.0);

    const ink_cr = kernels.wcag_contrast_x100(primary_ink.r, primary_ink.g, primary_ink.b, canvas_bg.r, canvas_bg.g, canvas_bg.b);
    const acc_cr = kernels.wcag_contrast_x100(acc1.r, acc1.g, acc1.b, canvas_bg.r, canvas_bg.g, canvas_bg.b);
    const n_pg_f: f64 = @floatFromInt(pages.len);

    return .{
        .slug = try alloc.dupe(u8, slug),
        .source_pdf = try alloc.dupe(u8, std.fs.path.basename(pdf_path)),
        .source_sha256 = src_sha,
        .page_count = pages.len,
        .trim_w_pt = trim_w,
        .trim_h_pt = trim_h,
        .format_class = fmt_class,
        .polarity = polarity,
        .margin_top_pt = m_top,
        .margin_bottom_pt = m_bot,
        .margin_left_pt = m_left,
        .margin_right_pt = m_right,
        .canvas_bg = canvas_bg,
        .surface_tint = surface_tint,
        .primary_ink = primary_ink,
        .muted_ink = muted_ink,
        .accent_primary = acc1,
        .accent_secondary = acc2,
        .ink_contrast_x100 = ink_cr,
        .accent_contrast_x100 = acc_cr,
        .display_font = .{ .role = "display", .source_font = try alloc.dupe(u8, disp_font), .sil_ofl_map = mapToSilOfl(disp_font, "display"), .size_pt = disp_size },
        .body_font = .{ .role = "body", .source_font = try alloc.dupe(u8, body_font), .sil_ofl_map = mapToSilOfl(body_font, "body"), .size_pt = body_size },
        .ui_sans_font = .{ .role = "ui_sans", .source_font = try alloc.dupe(u8, sans_font), .sil_ofl_map = mapToSilOfl(sans_font, "ui_sans"), .size_pt = sans_size },
        .mono_font = .{ .role = "mono", .source_font = try alloc.dupe(u8, mono_font), .sil_ofl_map = mapToSilOfl(mono_font, "mono"), .size_pt = mono_size },
        .avg_fill_pct = fill_sum / n_pg_f,
        .avg_photo_pct = photo_sum / n_pg_f,
        .pages = try page_dnas.toOwnedSlice(alloc),
    };
}

/// Format Blueprint as clean deterministic JSON for agents & `archetypes/<slug>/blueprint.json`.
pub fn formatBlueprintJson(alloc: std.mem.Allocator, bp: Blueprint) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    var h_bg: [7]u8 = undefined;
    var h_tint: [7]u8 = undefined;
    var h_ink: [7]u8 = undefined;
    var h_muted: [7]u8 = undefined;
    var h_a1: [7]u8 = undefined;
    var h_a2: [7]u8 = undefined;

    const j_slug = try mupdf.jsonString(alloc, bp.slug);
    const j_src = try mupdf.jsonString(alloc, bp.source_pdf);
    const j_fmt = try mupdf.jsonString(alloc, bp.format_class);
    const j_pol = try mupdf.jsonString(alloc, bp.polarity);
    try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\{{
        \\  "schema_version": "vedit.blueprint.v1",
        \\  "slug": {s},
        \\  "source_pdf": {s},
        \\  "source_sha256": "{s}",
        \\  "page_count": {d},
        \\  "format_class": {s},
        \\  "polarity": {s},
        \\  "trim_pt": [{d:.1}, {d:.1}],
        \\  "margins_pt": {{ "top": {d:.1}, "bottom": {d:.1}, "left": {d:.1}, "right": {d:.1} }},
        \\  "palette_60_30_10": {{
        \\    "canvas_bg": "{s}",
        \\    "surface_tint": "{s}",
        \\    "primary_ink": "{s}",
        \\    "muted_ink": "{s}",
        \\    "accent_primary": "{s}",
        \\    "accent_secondary": "{s}",
        \\    "wcag_ink_cr": {d:.2},
        \\    "wcag_accent_cr": {d:.2}
        \\  }},
        \\
    , .{
        j_slug,
        j_src,
        bp.source_sha256[0..64],
        bp.page_count,
        j_fmt,
        j_pol,
        bp.trim_w_pt,
        bp.trim_h_pt,
        bp.margin_top_pt,
        bp.margin_bottom_pt,
        bp.margin_left_pt,
        bp.margin_right_pt,
        bp.canvas_bg.formatHex(&h_bg),
        bp.surface_tint.formatHex(&h_tint),
        bp.primary_ink.formatHex(&h_ink),
        bp.muted_ink.formatHex(&h_muted),
        bp.accent_primary.formatHex(&h_a1),
        bp.accent_secondary.formatHex(&h_a2),
        @as(f64, @floatFromInt(bp.ink_contrast_x100)) / 100.0,
        @as(f64, @floatFromInt(bp.accent_contrast_x100)) / 100.0,
    }));

    try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\  "typography": {{
        \\    "display": {{ "source": {s}, "sil_ofl": {s}, "size_pt": {d:.1} }},
        \\    "body":    {{ "source": {s}, "sil_ofl": {s}, "size_pt": {d:.1} }},
        \\    "ui_sans": {{ "source": {s}, "sil_ofl": {s}, "size_pt": {d:.1} }},
        \\    "mono":    {{ "source": {s}, "sil_ofl": {s}, "size_pt": {d:.1} }}
        \\  }},
        \\  "cadence_summary": {{
        \\    "avg_vertical_fill_pct": {d:.1},
        \\    "avg_photo_coverage_pct": {d:.1}
        \\  }},
        \\  "pages": [
        \\
    , .{
        try mupdf.jsonString(alloc, bp.display_font.source_font),
        try mupdf.jsonString(alloc, bp.display_font.sil_ofl_map),
        bp.display_font.size_pt,
        try mupdf.jsonString(alloc, bp.body_font.source_font),
        try mupdf.jsonString(alloc, bp.body_font.sil_ofl_map),
        bp.body_font.size_pt,
        try mupdf.jsonString(alloc, bp.ui_sans_font.source_font),
        try mupdf.jsonString(alloc, bp.ui_sans_font.sil_ofl_map),
        bp.ui_sans_font.size_pt,
        try mupdf.jsonString(alloc, bp.mono_font.source_font),
        try mupdf.jsonString(alloc, bp.mono_font.sil_ofl_map),
        bp.mono_font.size_pt,
        bp.avg_fill_pct,
        bp.avg_photo_pct,
    }));

    for (bp.pages, 0..) |pg, idx| {
        const comma: []const u8 = if (idx + 1 < bp.pages.len) "," else "";
        try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\    {{ "page": {d}, "archetype": {s}, "columns": {d}, "fill_pct": {d:.1}, "photo_pct": {d:.1}, "spans": {d}, "images": {d}, "strokes": {d}, "max_font_pt": {d:.1} }}{s}
            \\
        , .{
            pg.page_num,
            try mupdf.jsonString(alloc, pg.archetype_name),
            pg.columns,
            pg.vertical_fill_pct,
            pg.photo_coverage_pct,
            pg.text_spans,
            pg.image_count,
            pg.stroke_count,
            pg.max_font_pt,
            comma,
        }));
    }
    try out.appendSlice(alloc, "  ]\n}\n");
    return out.toOwnedSlice(alloc);
}

/// Emit an immediately compilable Rust-native Typst 0.15.1 (`--pdf-standard ua-1`) starter skeleton
/// reproducing the dissected sample's trim, margins, 60-30-10 palette, SIL-OFL font mapping, and cadence.
pub fn generateTypstSkeleton(alloc: std.mem.Allocator, bp: Blueprint) ![]u8 {
    var h_bg: [7]u8 = undefined;
    var h_tint: [7]u8 = undefined;
    var h_ink: [7]u8 = undefined;
    var h_muted: [7]u8 = undefined;
    var h_a1: [7]u8 = undefined;
    var h_a2: [7]u8 = undefined;
    const is_wide = std.mem.eql(u8, bp.format_class, "widescreen_16x9");
    const rule_hex: []const u8 = if (std.mem.eql(u8, bp.polarity, "dark")) "#2A394A" else "#CFC8B8";

    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\// Auto-dissected Typst 0.15.1 PDF/UA-1 Archetype Skeleton
        \\// Source Sample: {s} (SHA-256: {s})
        \\// Archetype Slug: {s} ({s}, {s} polarity)
        \\
        \\#let data = json("../data/summary_metrics.json")
        \\#let ledger = json("../data/provenance_ledger.json")
        \\#let m = data.metrics
        \\
        \\#let c-bg     = rgb("{s}")
        \\#let c-tint   = rgb("{s}")
        \\#let c-ink    = rgb("{s}")
        \\#let c-muted  = rgb("{s}")
        \\#let c-acc1   = rgb("{s}")
        \\#let c-acc2   = rgb("{s}")
        \\#let c-rule   = rgb("{s}")
        \\
        \\#set document(
        \\  title: data.metadata.title,
        \\  author: data.metadata.author,
        \\)
        \\
    , .{
        bp.source_pdf,
        bp.source_sha256[0..16],
        bp.slug,
        bp.format_class,
        bp.polarity,
        bp.canvas_bg.formatHex(&h_bg),
        bp.surface_tint.formatHex(&h_tint),
        bp.primary_ink.formatHex(&h_ink),
        bp.muted_ink.formatHex(&h_muted),
        bp.accent_primary.formatHex(&h_a1),
        bp.accent_secondary.formatHex(&h_a2),
        rule_hex,
    }));

    try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\#set page(
        \\  width: {d:.1}pt,
        \\  height: {d:.1}pt,
        \\  fill: c-bg,
        \\  margin: (top: {d:.1}pt, bottom: {d:.1}pt, left: {d:.1}pt, right: {d:.1}pt),
        \\  footer: context {{
        \\    let pg = counter(page).get().first()
        \\    let tot = counter(page).final().first()
        \\    line(length: 100%, stroke: 0.5pt + c-rule)
        \\    v(3pt)
        \\    grid(
        \\      columns: (1fr, auto),
        \\      align: (left, right),
        \\      text(font: "{s}", size: 6.8pt, fill: c-muted, tracking: 0.08em)[#upper(data.metadata.kicker)],
        \\      text(font: "{s}", size: 10.5pt, weight: "bold", fill: c-ink, number-type: "lining")[#pg / #tot],
        \\    )
        \\  }},
        \\)
        \\
        \\#set text(font: "{s}", size: {d:.1}pt, fill: c-ink, lang: "en", region: "US")
        \\#set par(leading: 0.6em, spacing: 0.8em, justify: false)
        \\
    , .{
        bp.trim_w_pt,
        bp.trim_h_pt,
        bp.margin_top_pt,
        bp.margin_bottom_pt,
        bp.margin_left_pt,
        bp.margin_right_pt,
        bp.ui_sans_font.sil_ofl_map,
        bp.display_font.sil_ofl_map,
        bp.body_font.sil_ofl_map,
        bp.body_font.size_pt,
    }));

    // Page 1: Cover Hero + KPI Ribbon
    try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\// === PAGE 1: COVER HERO (Dissected Archetype: {s}) ===
        \\#line(length: 100%, stroke: 2.2pt + c-acc1)
        \\#v(6pt)
        \\#text(font: "{s}", size: 7.2pt, weight: "bold", fill: c-acc1, tracking: 0.14em)[#upper(data.metadata.kicker)]
        \\#v(4pt)
        \\#text(font: "{s}", size: {d:.1}pt, weight: "bold", fill: c-ink, number-type: "lining")[#data.metadata.title]
        \\#v(4pt)
        \\#text(size: 10.2pt, style: "italic", fill: c-muted)[#data.metadata.subtitle]
        \\#v(12pt)
        \\
        \\#grid(
        \\  columns: (1fr, 1fr, 1fr),
        \\  gutter: 10pt,
        \\  ..for kpi in data.kpis {{
        \\    (box(
        \\      width: 100%,
        \\      fill: c-tint,
        \\      inset: 10pt,
        \\      stroke: (top: 1.5pt + c-acc1),
        \\      [
        \\        #text(font: "{s}", size: 6.5pt, weight: "bold", fill: c-acc1, tracking: 0.12em)[#upper(kpi.label)]
        \\        #v(4pt)
        \\        #text(font: "{s}", size: 19pt, weight: "bold", fill: c-ink, number-type: "lining")[#kpi.display_value]
        \\        #v(3pt)
        \\        #text(font: "{s}", size: 6.6pt, fill: c-muted)[#kpi.note]
        \\      ],
        \\    ),)
        \\  }}
        \\)
        \\#v(14pt)
        \\#grid(
        \\  columns: ({s}),
        \\  gutter: 16pt,
        \\  [
        \\    #text(font: "{s}", size: 7.5pt, weight: "bold", fill: c-acc2, tracking: 0.1em)[AUDITED EXECUTIVE BRIEF]
        \\    #v(4pt)
        \\    Every quantitative figure on this canvas binds natively to `data/summary_metrics.json` across *#ledger.len()* cryptographic provenance tuples verified by `vedit latch`.
        \\  ],
        \\  box(
        \\    fill: c-tint,
        \\    inset: 10pt,
        \\    stroke: (left: 2pt + c-acc2),
        \\    [
        \\      #text(font: "{s}", size: 6.8pt, weight: "bold", fill: c-acc2, tracking: 0.12em)[DESIGN DNA PROVENANCE]
        \\      #v(4pt)
        \\      Cloned from dissected archetype `{s}` ({d:.0}×{d:.0} pt, {s} polarity, verified WCAG contrast) via #link("https://github.com/gke0op/verifiable-editorial-skills")[verifiable-editorial-skills].
        \\    ],
        \\  ),
        \\)
        \\
        \\#pagebreak()
        \\
        \\// === PAGE 2: AUDITED DATA LEDGER & SHA-256 PROVENANCE ===
        \\#text(font: "{s}", size: 17pt, weight: "bold", fill: c-acc1, number-type: "lining")[Audited Metrics & Cryptographic Ledger]
        \\#v(3pt)
        \\#line(length: 100%, stroke: 0.8pt + c-acc1)
        \\#v(10pt)
        \\#figure(
        \\  table(
        \\    columns: (1.6fr, 0.9fr, 1.4fr, 0.9fr),
        \\    inset: (x: 5pt, y: 5pt),
        \\    align: (left, right, left, left),
        \\    stroke: (x, y) => (
        \\      top: if y == 0 {{ 1.1pt + c-ink }} else if y == 1 {{ 0.75pt + c-ink }} else {{ 0.3pt + c-rule }},
        \\      bottom: if y == ledger.len() {{ 1.1pt + c-ink }} else {{ none }},
        \\    ),
        \\    table.header(
        \\      text(font: "{s}", size: 6.6pt, weight: "bold", fill: c-acc1)[METRIC ID],
        \\      text(font: "{s}", size: 6.6pt, weight: "bold", fill: c-acc1)[VALUE],
        \\      text(font: "{s}", size: 6.6pt, weight: "bold", fill: c-acc1)[RAW SOURCE],
        \\      text(font: "{s}", size: 6.6pt, weight: "bold", fill: c-acc1)[SHA-256 (12)],
        \\    ),
        \\    ..for r in ledger {{
        \\      (
        \\        text(font: "{s}", size: 6.8pt, fill: c-ink)[#r.metric_id],
        \\        text(font: "{s}", size: 6.8pt, weight: "semibold", fill: c-acc1)[#r.value],
        \\        text(font: "{s}", size: 6.8pt, fill: c-muted)[#r.source_document],
        \\        text(font: "{s}", size: 6.8pt, fill: c-acc2)[#r.raw_file_sha256.slice(0, 12)],
        \\      )
        \\    }}
        \\  ),
        \\  caption: text(size: 7.6pt, style: "italic", fill: c-muted)[Rule 4 atomic provenance ledger rendered natively from `data/provenance_ledger.json`.],
        \\)
        \\
    , .{
        bp.pages[0].archetype_name,
        bp.ui_sans_font.sil_ofl_map,
        bp.display_font.sil_ofl_map,
        @min(28.0, bp.display_font.size_pt),
        bp.ui_sans_font.sil_ofl_map,
        bp.display_font.sil_ofl_map,
        bp.ui_sans_font.sil_ofl_map,
        if (is_wide) "1.4fr, 1fr" else "1.55fr, 1fr",
        bp.ui_sans_font.sil_ofl_map,
        bp.ui_sans_font.sil_ofl_map,
        bp.slug,
        bp.trim_w_pt,
        bp.trim_h_pt,
        bp.polarity,
        bp.display_font.sil_ofl_map,
        bp.ui_sans_font.sil_ofl_map,
        bp.ui_sans_font.sil_ofl_map,
        bp.ui_sans_font.sil_ofl_map,
        bp.ui_sans_font.sil_ofl_map,
        bp.mono_font.sil_ofl_map,
        bp.mono_font.sil_ofl_map,
        bp.mono_font.sil_ofl_map,
        bp.mono_font.sil_ofl_map,
    }));

    return out.toOwnedSlice(alloc);
}

/// Emit compact token-budgeted AGENT_CARD.md so AI agents can load dissected Design DNA in ~250 tokens.
pub fn generateAgentCard(alloc: std.mem.Allocator, bp: Blueprint) ![]u8 {
    var h_bg: [7]u8 = undefined;
    var h_tint: [7]u8 = undefined;
    var h_ink: [7]u8 = undefined;
    var h_muted: [7]u8 = undefined;
    var h_a1: [7]u8 = undefined;
    var h_a2: [7]u8 = undefined;

    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\# Archetype Harness Card: `{s}`
        \\
        \\- **Dissected From:** `{s}` (`SHA-256: {s}`)
        \\- **Format:** `{s}` (`{d:.1} × {d:.1} pt`), **{s}** polarity, `{d}` pages
        \\- **Margins (T/B/L/R):** `{d:.1} / {d:.1} / {d:.1} / {d:.1} pt`
        \\- **Measured Density:** avg vertical fill `{d:.1}%` · avg photography coverage `{d:.1}%`
        \\
        \\## 60-30-10 Chromatic DNA (WCAG Verified)
        \\- Canvas (`60%`): `{s}` · Surface Tint: `{s}`
        \\- Primary Ink: `{s}` (`{d:.2}:1` CR) · Muted Ink: `{s}`
        \\- Signal Accent 1: `{s}` (`{d:.2}:1` CR) · Signal Accent 2: `{s}`
        \\
    , .{
        bp.slug,
        bp.source_pdf,
        bp.source_sha256[0..16],
        bp.format_class,
        bp.trim_w_pt,
        bp.trim_h_pt,
        bp.polarity,
        bp.page_count,
        bp.margin_top_pt,
        bp.margin_bottom_pt,
        bp.margin_left_pt,
        bp.margin_right_pt,
        bp.avg_fill_pct,
        bp.avg_photo_pct,
        bp.canvas_bg.formatHex(&h_bg),
        bp.surface_tint.formatHex(&h_tint),
        bp.primary_ink.formatHex(&h_ink),
        @as(f64, @floatFromInt(bp.ink_contrast_x100)) / 100.0,
        bp.muted_ink.formatHex(&h_muted),
        bp.accent_primary.formatHex(&h_a1),
        @as(f64, @floatFromInt(bp.accent_contrast_x100)) / 100.0,
        bp.accent_secondary.formatHex(&h_a2),
    }));

    try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\## Typography Ladder (Source -> Cross-Platform SIL-OFL)
        \\- Display (`{d:.1} pt`): `{s}` -> **`{s}`**
        \\- Body (`{d:.1} pt`): `{s}` -> **`{s}`**
        \\- UI Sans (`{d:.1} pt`): `{s}` -> **`{s}`**
        \\- Mono (`{d:.1} pt`): `{s}` -> **`{s}`**
        \\
        \\## Dissected Page Archetype Sequence
        \\
    , .{
        bp.display_font.size_pt,
        bp.display_font.source_font,
        bp.display_font.sil_ofl_map,
        bp.body_font.size_pt,
        bp.body_font.source_font,
        bp.body_font.sil_ofl_map,
        bp.ui_sans_font.size_pt,
        bp.ui_sans_font.source_font,
        bp.ui_sans_font.sil_ofl_map,
        bp.mono_font.size_pt,
        bp.mono_font.source_font,
        bp.mono_font.sil_ofl_map,
    }));

    for (bp.pages) |pg| {
        try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\- **Page {d}:** `{s}` ({d}-col, fill `{d:.0}%`, photo `{d:.0}%`, max font `{d:.1} pt`, spans `{d}`, strokes `{d}`)
            \\
        , .{ pg.page_num, pg.archetype_name, pg.columns, pg.vertical_fill_pct, pg.photo_coverage_pct, pg.max_font_pt, pg.text_spans, pg.stroke_count }));
    }

    try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\
        \\## Instant Reuse (Zero Python)
        \\```bash
        \\vedit init ./my-new-publication --archetype {s}
        \\```
        \\
    , .{bp.slug}));
    return out.toOwnedSlice(alloc);
}

/// Write `blueprint.json`, `skeleton.typ`, and `AGENT_CARD.md` under `<out_dir>/<slug>/`.
pub fn writeInjectedArchetype(
    alloc: std.mem.Allocator,
    io: std.Io,
    bp: Blueprint,
    out_dir: []const u8,
) ![]const u8 {
    const target_dir = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ out_dir, bp.slug });
    try std.Io.Dir.cwd().createDirPath(io, target_dir);

    const bp_json = try formatBlueprintJson(alloc, bp);
    const typ_skel = try generateTypstSkeleton(alloc, bp);
    const card_md = try generateAgentCard(alloc, bp);

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = try std.fmt.allocPrint(alloc, "{s}/blueprint.json", .{target_dir}), .data = bp_json });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = try std.fmt.allocPrint(alloc, "{s}/skeleton.typ", .{target_dir}), .data = typ_skel });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = try std.fmt.allocPrint(alloc, "{s}/AGENT_CARD.md", .{target_dir}), .data = card_md });
    return target_dir;
}
