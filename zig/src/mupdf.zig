//! Native Zero-Python PDF extraction & stream-rewriting engine for Zig 0.17.0.
//! Uses pure-C `mutool` (MuPDF) for CID-accurate font/layout/trace/PPM extraction,
//! plus a pure-Zig ISO 32000 BT...ET content-stream stripper for background-only contrast rendering.

const std = @import("std");
const kernels = @import("kernels_p2zig.zig");

pub const Rgb = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn formatHex(self: Rgb, buf: *[7]u8) []const u8 {
        _ = std.fmt.bufPrint(buf, "#{x:0>2}{x:0>2}{x:0>2}", .{ self.r, self.g, self.b }) catch unreachable;
        return buf[0..7];
    }
};

pub const PageSpan = struct {
    page: usize,
    block_idx: usize,
    line_idx: usize,
    text: []const u8,
    font: []const u8,
    size: f64,
    fg: Rgb,
    x0: f64,
    y0: f64,
    x1: f64,
    y1: f64,
    dir_x: f64,
    dir_y: f64,
    is_bold: bool,
    is_italic: bool,
};

pub const PlacedImage = struct {
    page: usize,
    native_w: i64,
    native_h: i64,
    x0: f64,
    y0: f64,
    x1: f64,
    y1: f64,
    eff_dpi_x10: i64,
    colorspace: []const u8,
};

pub const FillSample = struct {
    rgb: Rgb,
    is_stroke: bool,
    linewidth: f64,
};

pub const PageData = struct {
    page_num: usize,
    width: f64,
    height: f64,
    spans: []const PageSpan,
    images: []const PlacedImage,
    graphics: []const FillSample,
    stroke_count: usize,
    /// Full page text with whitespace breaks inserted at >=1.5pt font-size (superscript/subscript) boundaries.
    prose_text: []const u8,
};

pub const PpmImage = struct {
    width: usize,
    height: usize,
    pixels: []const u8, // RGBRGB... len == width * height * 3

    pub fn pixelAt(self: PpmImage, px: usize, py: usize) Rgb {
        const cx = @min(px, self.width - 1);
        const cy = @min(py, self.height - 1);
        const off = (cy * self.width + cx) * 3;
        return .{ .r = self.pixels[off], .g = self.pixels[off + 1], .b = self.pixels[off + 2] };
    }
};

pub const CatalogInfo = struct {
    page_count: usize,
    marked: bool,
    has_struct_tree: bool,
    has_lang: bool,
    lang: []const u8,
    has_title: bool,
    has_outlines: bool,
    has_pdfua_xmp: bool,
    bleed_all_pages: bool,
    min_bleed_margin_pt: f64,
    unembedded_fonts: []const []const u8,
    embedded_fonts: []const []const u8,
    media_w: f64,
    media_h: f64,
};

pub const RunResult = struct {
    stdout: []u8,
    stderr: []u8,
    exit_code: u8,
};

pub fn runCmd(alloc: std.mem.Allocator, io: std.Io, argv: []const []const u8, cwd: ?[]const u8) !RunResult {
    const res = try std.process.run(alloc, io, .{
        .argv = argv,
        .cwd = if (cwd) |p| .{ .path = p } else .inherit,
        .stdout_limit = .unlimited,
        .stderr_limit = .unlimited,
    });
    const code: u8 = switch (res.term) {
        .exited => |c| c,
        else => 255,
    };
    return .{ .stdout = res.stdout, .stderr = res.stderr, .exit_code = code };
}

pub fn whichTool(alloc: std.mem.Allocator, io: std.Io, name: []const u8) ?[]const u8 {
    const res = runCmd(alloc, io, &.{ "which", name }, null) catch return null;
    if (res.exit_code != 0) return null;
    const trimmed = std.mem.trim(u8, res.stdout, " \t\r\n");
    if (trimmed.len == 0) return null;
    return trimmed;
}

/// Extract XML attribute `key="..."` from a tag slice.
fn extractAttr(tag: []const u8, key: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i + key.len + 2 < tag.len) : (i += 1) {
        if (i > 0 and tag[i - 1] != ' ' and tag[i - 1] != '\t' and tag[i - 1] != '\n') continue;
        if (std.mem.startsWith(u8, tag[i..], key) and tag[i + key.len] == '=' and tag[i + key.len + 1] == '"') {
            const vstart = i + key.len + 2;
            if (std.mem.findScalarPos(u8, tag, vstart, '"')) |vend| {
                return tag[vstart..vend];
            }
        }
    }
    return null;
}

fn parseFloatSlice(s: []const u8, out: []f64) usize {
    var count: usize = 0;
    var it = std.mem.tokenizeAny(u8, s, " \t\r\n");
    while (it.next()) |tok| {
        if (count >= out.len) break;
        out[count] = std.fmt.parseFloat(f64, tok) catch 0.0;
        count += 1;
    }
    return count;
}

fn parseHexColor(s: []const u8) Rgb {
    if (s.len == 7 and s[0] == '#') {
        const r = std.fmt.parseInt(u8, s[1..3], 16) catch 0;
        const g = std.fmt.parseInt(u8, s[3..5], 16) catch 0;
        const b = std.fmt.parseInt(u8, s[5..7], 16) catch 0;
        return .{ .r = r, .g = g, .b = b };
    }
    return .{ .r = 0, .g = 0, .b = 0 };
}

fn decodeXmlChar(alloc: std.mem.Allocator, raw: []const u8, out: *std.ArrayList(u8)) !void {
    if (raw.len == 0) return;
    if (std.mem.eql(u8, raw, "&amp;")) {
        try out.append(alloc, '&');
    } else if (std.mem.eql(u8, raw, "&lt;")) {
        try out.append(alloc, '<');
    } else if (std.mem.eql(u8, raw, "&gt;")) {
        try out.append(alloc, '>');
    } else if (std.mem.eql(u8, raw, "&quot;")) {
        try out.append(alloc, '"');
    } else if (std.mem.eql(u8, raw, "&apos;")) {
        try out.append(alloc, '\'');
    } else if (raw.len > 4 and std.mem.startsWith(u8, raw, "&#x") and raw[raw.len - 1] == ';') {
        const cp = std.fmt.parseInt(u21, raw[3 .. raw.len - 1], 16) catch return;
        var ubuf: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(cp, &ubuf) catch return;
        try out.appendSlice(alloc, ubuf[0..n]);
    } else if (raw.len > 3 and std.mem.startsWith(u8, raw, "&#") and raw[raw.len - 1] == ';') {
        const cp = std.fmt.parseInt(u21, raw[2 .. raw.len - 1], 10) catch return;
        var ubuf: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(cp, &ubuf) catch return;
        try out.appendSlice(alloc, ubuf[0..n]);
    } else {
        try out.appendSlice(alloc, raw);
    }
}

fn stripSubsetPrefix(name: []const u8) []const u8 {
    if (name.len > 7 and name[6] == '+') {
        var all_upper = true;
        for (name[0..6]) |ch| {
            if (ch < 'A' or ch > 'Z') {
                all_upper = false;
                break;
            }
        }
        if (all_upper) return name[7..];
    }
    return name;
}

fn containsFold(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}

/// Extract structured spans, typography, images, and graphics for all pages of a PDF using `mutool`.
pub fn extractPages(alloc: std.mem.Allocator, io: std.Io, pdf_path: []const u8) ![]PageData {
    const stext_res = try runCmd(alloc, io, &.{ "mutool", "draw", "-F", "stext", pdf_path }, null);
    if (stext_res.exit_code != 0) return error.MutoolStextFailed;
    const trace_res = try runCmd(alloc, io, &.{ "mutool", "draw", "-F", "trace", pdf_path }, null);
    if (trace_res.exit_code != 0) return error.MutoolTraceFailed;

    var pages: std.ArrayList(PageData) = .empty;
    var spans: std.ArrayList(PageSpan) = .empty;
    var prose: std.ArrayList(u8) = .empty;

    var cur_page: usize = 0;
    var cur_w: f64 = 612.0;
    var cur_h: f64 = 792.0;
    var block_idx: usize = 0;
    var line_idx: usize = 0;
    var line_dir_x: f64 = 1.0;
    var line_dir_y: f64 = 0.0;
    var prev_line_span_size: f64 = -1.0;

    var in_font = false;
    var cur_font: []const u8 = "";
    var cur_size: f64 = 10.0;
    var cur_fg: Rgb = .{ .r = 0, .g = 0, .b = 0 };
    var cur_bold = false;
    var cur_italic = false;
    var cur_chars: std.ArrayList(u8) = .empty;
    var sx0: f64 = 1e9;
    var sy0: f64 = 1e9;
    var sx1: f64 = -1e9;
    var sy1: f64 = -1e9;
    var prev_cx1: f64 = -1e9;
    var prev_cy: f64 = -1e9;
    var has_glyph = false;

    const xml = stext_res.stdout;
    var pos: usize = 0;
    while (std.mem.findScalarPos(u8, xml, pos, '<')) |lt| {
        const gt = std.mem.findScalarPos(u8, xml, lt + 1, '>') orelse break;
        const tag = xml[lt + 1 .. gt];
        pos = gt + 1;

        if (std.mem.startsWith(u8, tag, "page ")) {
            cur_page += 1;
            cur_w = if (extractAttr(tag, "width")) |v| std.fmt.parseFloat(f64, v) catch 612.0 else 612.0;
            cur_h = if (extractAttr(tag, "height")) |v| std.fmt.parseFloat(f64, v) catch 792.0 else 792.0;
            spans = .empty;
            prose = .empty;
            block_idx = 0;
            line_idx = 0;
        } else if (std.mem.eql(u8, tag, "/page")) {
            try pages.append(alloc, .{
                .page_num = cur_page,
                .width = cur_w,
                .height = cur_h,
                .spans = try spans.toOwnedSlice(alloc),
                .images = &.{},
                .graphics = &.{},
                .stroke_count = 0,
                .prose_text = try prose.toOwnedSlice(alloc),
            });
        } else if (std.mem.startsWith(u8, tag, "block ")) {
            block_idx += 1;
            line_idx = 0;
        } else if (std.mem.startsWith(u8, tag, "line ")) {
            line_idx += 1;
            prev_line_span_size = -1.0;
            if (extractAttr(tag, "dir")) |dv| {
                var dnums: [2]f64 = .{ 1.0, 0.0 };
                _ = parseFloatSlice(dv, &dnums);
                line_dir_x = dnums[0];
                line_dir_y = dnums[1];
            } else {
                line_dir_x = 1.0;
                line_dir_y = 0.0;
            }
        } else if (std.mem.eql(u8, tag, "/line")) {
            try prose.append(alloc, '\n');
        } else if (std.mem.startsWith(u8, tag, "font ")) {
            in_font = true;
            cur_font = stripSubsetPrefix(extractAttr(tag, "name") orelse "Unknown");
            cur_size = if (extractAttr(tag, "size")) |v| std.fmt.parseFloat(f64, v) catch 10.0 else 10.0;
            cur_fg = .{ .r = 0, .g = 0, .b = 0 };
            cur_bold = containsFold(cur_font, "bold") or containsFold(cur_font, "semibold") or containsFold(cur_font, "demi");
            cur_italic = containsFold(cur_font, "italic") or containsFold(cur_font, "oblique");
            cur_chars.clearRetainingCapacity();
            sx0 = 1e9;
            sy0 = 1e9;
            sx1 = -1e9;
            sy1 = -1e9;
            prev_cx1 = -1e9;
            prev_cy = -1e9;
            has_glyph = false;
        } else if (std.mem.startsWith(u8, tag, "char ") and in_font) {
            if (extractAttr(tag, "quad")) |qv| {
                var q: [8]f64 = .{ 0, 0, 0, 0, 0, 0, 0, 0 };
                if (parseFloatSlice(qv, &q) == 8) {
                    const qx0 = @min(@min(q[0], q[2]), @min(q[4], q[6]));
                    const qx1 = @max(@max(q[0], q[2]), @max(q[4], q[6]));
                    var qy0 = @min(@min(q[1], q[3]), @min(q[5], q[7]));
                    var qy1 = @max(@max(q[1], q[3]), @max(q[5], q[7]));
                    // mutool 1.23 quads use font-wide ascender/descender (NewCMMath: ~6.6x size tall);
                    // clamp horizontal glyphs to an em box around the baseline, like PyMuPDF TEXT_ACCURATE_BBOXES.
                    if (@abs(line_dir_y) < 0.05) {
                        if (extractAttr(tag, "y")) |yv| {
                            const base = std.fmt.parseFloat(f64, yv) catch qy1;
                            qy0 = @max(qy0, base - cur_size * 1.0);
                            qy1 = @min(qy1, base + cur_size * 0.3);
                        }
                    }
                    const qcy = (qy0 + qy1) * 0.5;
                    // Split into a new span if MuPDF merged spatially distant glyphs (e.g. math fractions / table cols)
                    if (has_glyph and ((qx0 - prev_cx1) > cur_size * 1.8 or (prev_cx1 - qx1) > cur_size * 1.8 or @abs(qcy - prev_cy) > cur_size * 0.45)) {
                        const prev_trim = std.mem.trim(u8, cur_chars.items, " \t\r\n");
                        if (prev_trim.len > 0 and sx1 > sx0 and sy1 > sy0) {
                            try spans.append(alloc, .{
                                .page = cur_page,
                                .block_idx = block_idx,
                                .line_idx = line_idx,
                                .text = try alloc.dupe(u8, prev_trim),
                                .font = try alloc.dupe(u8, cur_font),
                                .size = cur_size,
                                .fg = cur_fg,
                                .x0 = sx0,
                                .y0 = sy0,
                                .x1 = sx1,
                                .y1 = sy1,
                                .dir_x = line_dir_x,
                                .dir_y = line_dir_y,
                                .is_bold = cur_bold,
                                .is_italic = cur_italic,
                            });
                        }
                        if (cur_chars.items.len > 0) {
                            try prose.appendSlice(alloc, cur_chars.items);
                            try prose.append(alloc, ' ');
                        }
                        cur_chars.clearRetainingCapacity();
                        sx0 = 1e9;
                        sy0 = 1e9;
                        sx1 = -1e9;
                        sy1 = -1e9;
                        has_glyph = false;
                    }
                    if (qx1 > qx0 or qy1 > qy0) {
                        sx0 = @min(sx0, qx0);
                        sy0 = @min(sy0, qy0);
                        sx1 = @max(sx1, qx1);
                        sy1 = @max(sy1, qy1);
                        prev_cx1 = qx1;
                        prev_cy = qcy;
                        has_glyph = true;
                    }
                }
            }
            if (extractAttr(tag, "c")) |cv| {
                try decodeXmlChar(alloc, cv, &cur_chars);
            }
            if (extractAttr(tag, "color")) |col| {
                cur_fg = parseHexColor(col);
            }
            if (extractAttr(tag, "flags")) |fl| {
                const fval = std.fmt.parseInt(u32, fl, 10) catch 0;
                if ((fval & 16) != 0) cur_bold = true;
            }
        } else if (std.mem.eql(u8, tag, "/font") and in_font) {
            in_font = false;
            const raw_txt = cur_chars.items;
            // Append to prose text with superscript/subscript font-size break detection (>=1.5pt jump)
            if (raw_txt.len > 0) {
                if (prev_line_span_size > 0.0 and @abs(cur_size - prev_line_span_size) >= 1.5) {
                    if (prose.items.len > 0 and prose.items[prose.items.len - 1] != ' ' and prose.items[prose.items.len - 1] != '\n' and raw_txt[0] != ' ') {
                        try prose.append(alloc, ' ');
                    }
                }
                try prose.appendSlice(alloc, raw_txt);
                prev_line_span_size = cur_size;
            }
            const trimmed = std.mem.trim(u8, raw_txt, " \t\r\n");
            if (trimmed.len > 0 and has_glyph and sx1 > sx0 and sy1 > sy0) {
                try spans.append(alloc, .{
                    .page = cur_page,
                    .block_idx = block_idx,
                    .line_idx = line_idx,
                    .text = try alloc.dupe(u8, trimmed),
                    .font = try alloc.dupe(u8, cur_font),
                    .size = cur_size,
                    .fg = cur_fg,
                    .x0 = sx0,
                    .y0 = sy0,
                    .x1 = sx1,
                    .y1 = sy1,
                    .dir_x = line_dir_x,
                    .dir_y = line_dir_y,
                    .is_bold = cur_bold,
                    .is_italic = cur_italic,
                });
            }
        }
    }

    // Parse trace XML to attach placed images, fill colors, and vector stroke counts per page
    const txml = trace_res.stdout;
    var tpos: usize = 0;
    var tpage_idx: usize = 0;
    var imgs: std.ArrayList(PlacedImage) = .empty;
    var gfx: std.ArrayList(FillSample) = .empty;
    var strokes: usize = 0;

    while (std.mem.findScalarPos(u8, txml, tpos, '<')) |lt| {
        const gt = std.mem.findScalarPos(u8, txml, lt + 1, '>') orelse break;
        const tag = txml[lt + 1 .. gt];
        tpos = gt + 1;

        if (std.mem.startsWith(u8, tag, "page ")) {
            tpage_idx = if (extractAttr(tag, "number")) |v| std.fmt.parseInt(usize, v, 10) catch (tpage_idx + 1) else (tpage_idx + 1);
            imgs = .empty;
            gfx = .empty;
            strokes = 0;
        } else if (std.mem.eql(u8, tag, "/page")) {
            if (tpage_idx >= 1 and tpage_idx <= pages.items.len) {
                pages.items[tpage_idx - 1].images = try imgs.toOwnedSlice(alloc);
                pages.items[tpage_idx - 1].graphics = try gfx.toOwnedSlice(alloc);
                pages.items[tpage_idx - 1].stroke_count = strokes;
            }
        } else if (std.mem.startsWith(u8, tag, "fill_image ")) {
            const nw = if (extractAttr(tag, "width")) |v| std.fmt.parseInt(i64, v, 10) catch 0 else 0;
            const nh = if (extractAttr(tag, "height")) |v| std.fmt.parseInt(i64, v, 10) catch 0 else 0;
            const cs = extractAttr(tag, "colorspace") orelse "DeviceRGB";
            var tf: [6]f64 = .{ 0, 0, 0, 0, 0, 0 };
            if (extractAttr(tag, "transform")) |tv| {
                _ = parseFloatSlice(tv, &tf);
            }
            // Transform maps unit square [0,1]x[0,1] via affine matrix [a b c d e f]
            const pw = @sqrt(tf[0] * tf[0] + tf[1] * tf[1]);
            const ph = @sqrt(tf[2] * tf[2] + tf[3] * tf[3]);
            // Skip tiny synthetic 1px/mask artifacts or zero-size transforms
            if (nw >= 8 and nh >= 8 and pw >= 8.0 and ph >= 8.0) {
                const ix0 = @min(@min(tf[4], tf[4] + tf[0]), @min(tf[4] + tf[2], tf[4] + tf[0] + tf[2]));
                const ix1 = @max(@max(tf[4], tf[4] + tf[0]), @max(tf[4] + tf[2], tf[4] + tf[0] + tf[2]));
                const iy0 = @min(@min(tf[5], tf[5] + tf[1]), @min(tf[5] + tf[3], tf[5] + tf[1] + tf[3]));
                const iy1 = @max(@max(tf[5], tf[5] + tf[1]), @max(tf[5] + tf[3], tf[5] + tf[1] + tf[3]));
                const pw_x10: i64 = @intFromFloat(@round(pw * 10.0));
                const ph_x10: i64 = @intFromFloat(@round(ph * 10.0));
                const eff = kernels.effective_dpi_x10(nw, nh, pw_x10, ph_x10);
                try imgs.append(alloc, .{
                    .page = tpage_idx,
                    .native_w = nw,
                    .native_h = nh,
                    .x0 = ix0,
                    .y0 = iy0,
                    .x1 = ix1,
                    .y1 = iy1,
                    .eff_dpi_x10 = eff,
                    .colorspace = try alloc.dupe(u8, cs),
                });
            }
        } else if (std.mem.startsWith(u8, tag, "fill_path ") or std.mem.startsWith(u8, tag, "stroke_path ")) {
            const is_st = std.mem.startsWith(u8, tag, "stroke_path ");
            if (is_st) strokes += 1;
            const lw = if (extractAttr(tag, "linewidth")) |v| std.fmt.parseFloat(f64, v) catch 0.0 else 0.0;
            if (extractAttr(tag, "color")) |cv| {
                const cs = extractAttr(tag, "colorspace") orelse "";
                var comps: [4]f64 = .{ 0, 0, 0, 0 };
                const n = parseFloatSlice(cv, &comps);
                if (n == 3 and (std.mem.find(u8, cs, "RGB") != null or cs.len == 0)) {
                    try gfx.append(alloc, .{
                        .rgb = .{
                            .r = @intFromFloat(@round(std.math.clamp(comps[0], 0.0, 1.0) * 255.0)),
                            .g = @intFromFloat(@round(std.math.clamp(comps[1], 0.0, 1.0) * 255.0)),
                            .b = @intFromFloat(@round(std.math.clamp(comps[2], 0.0, 1.0) * 255.0)),
                        },
                        .is_stroke = is_st,
                        .linewidth = lw,
                    });
                } else if (n == 1) {
                    const gv: u8 = @intFromFloat(@round(std.math.clamp(comps[0], 0.0, 1.0) * 255.0));
                    try gfx.append(alloc, .{ .rgb = .{ .r = gv, .g = gv, .b = gv }, .is_stroke = is_st, .linewidth = lw });
                }
            }
        }
    }

    return pages.toOwnedSlice(alloc);
}

fn isPdfIdentChar(ch: u8) bool {
    return (ch >= 'A' and ch <= 'Z') or (ch >= 'a' and ch <= 'z') or
        (ch >= '0' and ch <= '9') or ch == '_' or ch == '/' or ch == '+' or ch == '.' or ch == '-';
}

fn isPdfDelimiter(ch: u8) bool {
    return ch == ' ' or ch == '\t' or ch == '\r' or ch == '\n' or
        ch == '/' or ch == '<' or ch == '(' or ch == '[' or ch == '{' or ch == '%';
}

fn isNonContentStream(raw: []const u8, st_idx: usize) bool {
    const win_start = if (st_idx > 400) st_idx - 400 else 0;
    const hdr = raw[win_start..st_idx];
    return std.mem.find(u8, hdr, "/Subtype /Image") != null or
        std.mem.find(u8, hdr, "/Subtype/Image") != null or
        std.mem.find(u8, hdr, "/FontFile") != null or
        std.mem.find(u8, hdr, "/Filter /DCTDecode") != null or
        std.mem.find(u8, hdr, "/Filter/DCTDecode") != null or
        std.mem.find(u8, hdr, "/Subtype /XML") != null or
        std.mem.find(u8, hdr, "/Type /Metadata") != null;
}

fn blankBtEtInPlace(buf: []u8) void {
    var i: usize = 0;
    while (i < buf.len) {
        if (i + 2 < buf.len and buf[i] == 'B' and buf[i + 1] == 'T') {
            const prev_ok = (i == 0) or !isPdfIdentChar(buf[i - 1]);
            const next_ok = isPdfDelimiter(buf[i + 2]);
            if (prev_ok and next_ok) {
                var j: usize = i + 2;
                var found_et: ?usize = null;
                while (j + 1 < buf.len) : (j += 1) {
                    if (buf[j] == 'E' and buf[j + 1] == 'T') {
                        const et_prev_ok = !isPdfIdentChar(buf[j - 1]);
                        const et_next_ok = (j + 2 == buf.len) or isPdfDelimiter(buf[j + 2]);
                        if (et_prev_ok and et_next_ok) {
                            found_et = j + 2;
                            break;
                        }
                    }
                }
                if (found_et) |end_pos| {
                    var k: usize = i;
                    while (k < end_pos) : (k += 1) {
                        if (buf[k] != '\n') buf[k] = ' ';
                    }
                    i = end_pos;
                    continue;
                }
            }
        }
        i += 1;
    }
}

/// Pure-Zig ISO 32000 delimiter-safe BT...ET text-block stripper (handles Typst `BT/Span` tagged streams
/// while skipping binary Image/Font/Metadata streams so photo-heavy PDFs stay 100% intact).
pub fn stripBtEtStreams(alloc: std.mem.Allocator, raw: []const u8) ![]u8 {
    const out = try alloc.dupe(u8, raw);
    // If input is a raw content-stream snippet without `stream...endstream` wrapper (e.g. unit test), process directly
    if (std.mem.find(u8, out, "stream\n") == null and std.mem.find(u8, out, "stream\r\n") == null) {
        blankBtEtInPlace(out);
        return out;
    }
    var pos: usize = 0;
    while (std.mem.findPos(u8, out, pos, "stream")) |st_idx| {
        if (st_idx >= 3 and std.mem.eql(u8, out[st_idx - 3 .. st_idx], "end")) {
            pos = st_idx + 6;
            continue;
        }
        var body_start = st_idx + 6;
        if (body_start < out.len and out[body_start] == '\r') body_start += 1;
        if (body_start >= out.len or out[body_start] != '\n') {
            pos = st_idx + 6;
            continue;
        }
        body_start += 1;
        const body_end = std.mem.findPos(u8, out, body_start, "endstream") orelse break;
        if (isNonContentStream(out, st_idx)) {
            pos = body_end + 9;
            continue;
        }
        if (!isNonContentStream(out, st_idx)) {
            blankBtEtInPlace(out[body_start..body_end]);
        }
        pos = body_end + 9;
    }
    return out;
}

/// Build a temporary text-free PDF (decompressed via `mutool clean -d`, BT...ET blanked in-place in Zig)
/// so subsequent `renderPagePpm` calls return true text-free backgrounds for WCAG & texture audits.
pub fn makeBackgroundOnlyPdf(alloc: std.mem.Allocator, io: std.Io, pdf_path: []const u8, tmp_tag: []const u8) ![]const u8 {
    const clean_path = try std.fmt.allocPrint(alloc, "/tmp/vedit_clean_{s}.pdf", .{tmp_tag});
    const bg_path = try std.fmt.allocPrint(alloc, "/tmp/vedit_bg_{s}.pdf", .{tmp_tag});
    defer std.Io.Dir.cwd().deleteFile(io, clean_path) catch {};

    const clean_res = try runCmd(alloc, io, &.{ "mutool", "clean", "-d", pdf_path, clean_path }, null);
    if (clean_res.exit_code != 0) return error.MutoolCleanFailed;

    const raw = try std.Io.Dir.cwd().readFileAlloc(io, clean_path, alloc, .unlimited);
    const stripped = try stripBtEtStreams(alloc, raw);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = bg_path, .data = stripped });
    return bg_path;
}

fn isWs(ch: u8) bool {
    return ch == ' ' or ch == '\t' or ch == '\r' or ch == '\n';
}

/// Pure-Zig ISO 32000 PDF clip-path stripper: blanks `W` / `W*` clipping operators inside `stream...endstream`
/// payloads (preserving exact byte length so PDF xref offsets remain 100% valid).
pub fn stripClipPathStreams(alloc: std.mem.Allocator, raw: []const u8) ![]u8 {
    const out = try alloc.dupe(u8, raw);
    var pos: usize = 0;
    while (std.mem.findPos(u8, out, pos, "stream")) |st_idx| {
        var body_start = st_idx + 6;
        if (body_start < out.len and out[body_start] == '\r') body_start += 1;
        if (body_start >= out.len or out[body_start] != '\n') {
            pos = st_idx + 6;
            continue;
        }
        body_start += 1;
        // Skip "endstream" false match
        if (st_idx >= 3 and std.mem.eql(u8, out[st_idx - 3 .. st_idx], "end")) {
            pos = st_idx + 6;
            continue;
        }
        const body_end = std.mem.findPos(u8, out, body_start, "endstream") orelse break;
        if (isNonContentStream(out, st_idx)) {
            pos = body_end + 9;
            continue;
        }

        var i = body_start;
        var paren_depth: usize = 0;
        var in_hex = false;
        while (i < body_end) : (i += 1) {
            const ch = out[i];
            if (paren_depth > 0) {
                if (ch == '\\' and i + 1 < body_end) {
                    i += 1;
                } else if (ch == '(') {
                    paren_depth += 1;
                } else if (ch == ')') {
                    paren_depth -= 1;
                }
                continue;
            }
            if (in_hex) {
                if (ch == '>') in_hex = false;
                continue;
            }
            if (ch == '(') {
                paren_depth = 1;
                continue;
            }
            if (ch == '<' and (i + 1 >= body_end or out[i + 1] != '<')) {
                in_hex = true;
                continue;
            }
            if (ch == 'W') {
                const prev_ok = (i == body_start) or isWs(out[i - 1]);
                if (!prev_ok) continue;
                var op_len: usize = 1;
                if (i + 1 < body_end and out[i + 1] == '*') op_len = 2;
                const after = i + op_len;
                if (after >= body_end or !isWs(out[after])) continue;
                // Check next non-whitespace operator is a path terminator/painter (`n`, `f`, `F`, `S`, `s`, `B`, `b`)
                var k = after;
                while (k < body_end and isWs(out[k])) : (k += 1) {}
                if (k < body_end) {
                    const nxt = out[k];
                    const is_path_op = (nxt == 'n' or nxt == 'f' or nxt == 'F' or nxt == 'S' or nxt == 's' or nxt == 'B' or nxt == 'b');
                    const nxt_after = k + 1;
                    const nxt_delim = (nxt_after >= body_end) or isWs(out[nxt_after]) or out[nxt_after] == '*';
                    if (is_path_op and nxt_delim) {
                        out[i] = ' ';
                        if (op_len == 2) out[i + 1] = ' ';
                    }
                }
            }
        }
        pos = body_end + 9;
    }
    return out;
}

/// Create a temporary unclipped PDF (with all `W`/`W*` clip operators neutralised) for clip-slicing detection.
pub fn makeUnclippedPdf(alloc: std.mem.Allocator, io: std.Io, pdf_path: []const u8, tmp_tag: []const u8) ![]const u8 {
    const clean_path = try std.fmt.allocPrint(alloc, "/tmp/vedit_clipclean_{s}.pdf", .{tmp_tag});
    const out_path = try std.fmt.allocPrint(alloc, "/tmp/vedit_unclipped_{s}.pdf", .{tmp_tag});
    defer std.Io.Dir.cwd().deleteFile(io, clean_path) catch {};

    const clean_res = try runCmd(alloc, io, &.{ "mutool", "clean", "-d", pdf_path, clean_path }, null);
    if (clean_res.exit_code != 0) return error.MutoolCleanFailed;
    const raw = try std.Io.Dir.cwd().readFileAlloc(io, clean_path, alloc, .unlimited);
    const stripped = try stripClipPathStreams(alloc, raw);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = out_path, .data = stripped });
    return out_path;
}

fn parseDictInt(dict: []const u8, key: []const u8) ?i64 {
    const pos = std.mem.find(u8, dict, key) orelse return null;
    const rest = std.mem.trimStart(u8, dict[pos + key.len ..], " \t\r\n");
    var end: usize = 0;
    while (end < rest.len and rest[end] >= '0' and rest[end] <= '9') : (end += 1) {}
    if (end == 0) return null;
    return std.fmt.parseInt(i64, rest[0..end], 10) catch null;
}

fn extractSMaskRef(alloc: std.mem.Allocator, dict: []const u8) !?[]const u8 {
    const pos = std.mem.find(u8, dict, "/SMask") orelse return null;
    const rest = std.mem.trimStart(u8, dict[pos + 6 ..], " \t\r\n");
    var it = std.mem.tokenizeAny(u8, rest, " \t\r\n");
    const n1 = it.next() orelse return null;
    const n2 = it.next() orelse return null;
    const rtok = it.next() orelse return null;
    if (!std.mem.eql(u8, rtok, "R")) return null;
    return try std.fmt.allocPrint(alloc, "/SMask {s} {s} R", .{ n1, n2 });
}

pub const RewriteImagesResult = struct {
    bytes: []u8,
    replaced_count: usize,
    needs_xref_repair: bool,
};

/// Pure-Zig dual-key PDF image rewriter: replaces every non-mask raster Image XObject (>= 8x8 px)
/// with a 1x1 solid DeviceRGB pixel `(r, g, b)` while preserving `/SMask`, PDF clip paths, and z-order.
pub fn rewriteImagesToSolidKey(alloc: std.mem.Allocator, raw: []const u8, key: Rgb) !RewriteImagesResult {
    // Pass 1: collect all object IDs referenced by `/SMask <id> 0 R` so alpha masks stay untouched
    var smask_ids = std.AutoHashMap(u64, void).init(alloc);
    defer smask_ids.deinit();
    var spos: usize = 0;
    while (std.mem.findPos(u8, raw, spos, "/SMask")) |mpos| {
        const rest = std.mem.trimStart(u8, raw[mpos + 6 ..], " \t\r\n");
        var it = std.mem.tokenizeAny(u8, rest, " \t\r\n");
        if (it.next()) |id_tok| {
            if (std.fmt.parseInt(u64, id_tok, 10)) |oid| {
                try smask_ids.put(oid, {});
            } else |_| {}
        }
        spos = mpos + 6;
    }

    var out: std.ArrayList(u8) = .empty;
    try out.ensureTotalCapacity(alloc, raw.len);
    var replaced: usize = 0;
    var needs_repair = false;

    var cursor: usize = 0;
    while (cursor < raw.len) {
        // Find next " 0 obj"
        const obj_marker = std.mem.findPos(u8, raw, cursor, " 0 obj") orelse {
            try out.appendSlice(alloc, raw[cursor..]);
            break;
        };
        // Walk back to start of object number
        var id_start = obj_marker;
        while (id_start > cursor and raw[id_start - 1] >= '0' and raw[id_start - 1] <= '9') : (id_start -= 1) {}
        const oid = std.fmt.parseInt(u64, raw[id_start..obj_marker], 10) catch 0;
        const body_after_hdr = obj_marker + 6;
        const endobj_pos = std.mem.findPos(u8, raw, body_after_hdr, "endobj") orelse {
            try out.appendSlice(alloc, raw[cursor..]);
            break;
        };
        const obj_slice = raw[body_after_hdr..endobj_pos];

        // Check if this object is a non-mask Image XObject with a stream
        const is_img = (std.mem.find(u8, obj_slice, "/Subtype /Image") != null or std.mem.find(u8, obj_slice, "/Subtype/Image") != null);
        const is_mask = (std.mem.find(u8, obj_slice, "/ImageMask true") != null or std.mem.find(u8, obj_slice, "/ImageMask/true") != null or smask_ids.contains(oid));
        if (is_img and !is_mask) {
            if (std.mem.find(u8, obj_slice, "<<")) |d_start| {
                if (std.mem.findPos(u8, obj_slice, d_start, "stream")) |st_rel| {
                    if (std.mem.findPos(u8, obj_slice, st_rel + 6, "endstream")) |es_rel| {
                        const dict = obj_slice[d_start..st_rel];
                        const iw = parseDictInt(dict, "/Width") orelse 0;
                        const ih = parseDictInt(dict, "/Height") orelse 0;
                        if (iw >= 8 and ih >= 8) {
                            const smask_opt = try extractSMaskRef(alloc, dict);
                            defer if (smask_opt) |s| alloc.free(s);
                            const smask_clause = smask_opt orelse "";
                            const repl = try std.fmt.allocPrint(
                                alloc,
                                "<< /Type /XObject /Subtype /Image /Width 1 /Height 1 /ColorSpace /DeviceRGB /BitsPerComponent 8 {s} /Length 3 >>\nstream\n{c}{c}{c}\nendstream",
                                .{ smask_clause, key.r, key.g, key.b },
                            );
                            defer alloc.free(repl);
                            const orig_span_start = body_after_hdr + d_start;
                            const orig_span_end = body_after_hdr + es_rel + 9;
                            const orig_len = orig_span_end - orig_span_start;

                            try out.appendSlice(alloc, raw[cursor..orig_span_start]);
                            try out.appendSlice(alloc, repl);
                            if (repl.len <= orig_len) {
                                var pad: usize = orig_len - repl.len;
                                while (pad > 0) : (pad -= 1) try out.append(alloc, ' ');
                            } else {
                                needs_repair = true;
                            }
                            cursor = orig_span_end;
                            replaced += 1;
                            continue;
                        }
                    }
                }
            }
        }
        try out.appendSlice(alloc, raw[cursor .. endobj_pos + 6]);
        cursor = endobj_pos + 6;
    }

    return .{
        .bytes = try out.toOwnedSlice(alloc),
        .replaced_count = replaced,
        .needs_xref_repair = needs_repair,
    };
}

pub const DualKeyPdfs = struct {
    pdf_a: []const u8,
    pdf_b: []const u8,
    replaced_images: usize,
};

/// Build two temporary PDFs where every real raster image is swapped with Magenta (#FF00FF) vs Lime (#00FF00).
pub fn makeDualKeyPdfs(alloc: std.mem.Allocator, io: std.Io, pdf_path: []const u8, tmp_tag: []const u8) !DualKeyPdfs {
    const clean_path = try std.fmt.allocPrint(alloc, "/tmp/vedit_covclean_{s}.pdf", .{tmp_tag});
    const raw_a = try std.fmt.allocPrint(alloc, "/tmp/vedit_cova_raw_{s}.pdf", .{tmp_tag});
    const raw_b = try std.fmt.allocPrint(alloc, "/tmp/vedit_covb_raw_{s}.pdf", .{tmp_tag});
    const out_a = try std.fmt.allocPrint(alloc, "/tmp/vedit_cova_{s}.pdf", .{tmp_tag});
    const out_b = try std.fmt.allocPrint(alloc, "/tmp/vedit_covb_{s}.pdf", .{tmp_tag});
    defer std.Io.Dir.cwd().deleteFile(io, clean_path) catch {};

    // Normalize PDF structure (decompress object streams so /Image dicts are plaintext, keeping JPEG streams compact)
    const cl = try runCmd(alloc, io, &.{ "mutool", "clean", pdf_path, clean_path }, null);
    if (cl.exit_code != 0) return error.MutoolCleanFailed;
    const base_bytes = try std.Io.Dir.cwd().readFileAlloc(io, clean_path, alloc, .unlimited);

    const ka = try rewriteImagesToSolidKey(alloc, base_bytes, .{ .r = 255, .g = 0, .b = 255 });
    const kb = try rewriteImagesToSolidKey(alloc, base_bytes, .{ .r = 0, .g = 255, .b = 0 });

    if (ka.needs_xref_repair) {
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = raw_a, .data = ka.bytes });
        defer std.Io.Dir.cwd().deleteFile(io, raw_a) catch {};
        _ = try runCmd(alloc, io, &.{ "mutool", "clean", raw_a, out_a }, null);
    } else {
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = out_a, .data = ka.bytes });
    }
    if (kb.needs_xref_repair) {
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = raw_b, .data = kb.bytes });
        defer std.Io.Dir.cwd().deleteFile(io, raw_b) catch {};
        _ = try runCmd(alloc, io, &.{ "mutool", "clean", raw_b, out_b }, null);
    } else {
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = out_b, .data = kb.bytes });
    }

    return .{ .pdf_a = out_a, .pdf_b = out_b, .replaced_images = ka.replaced_count };
}

/// Parse binary PPM (`P6`) bytes into RGB pixel matrix.
pub fn parsePpm(data: []const u8) !PpmImage {
    if (data.len < 11 or data[0] != 'P' or data[1] != '6') return error.InvalidPpm;
    var i: usize = 2;
    var header_nums: [3]usize = .{ 0, 0, 0 };
    var idx: usize = 0;
    while (idx < 3 and i < data.len) {
        // Skip whitespace and # comments
        while (i < data.len) {
            if (data[i] == '#') {
                while (i < data.len and data[i] != '\n') : (i += 1) {}
            } else if (data[i] == ' ' or data[i] == '\t' or data[i] == '\r' or data[i] == '\n') {
                i += 1;
            } else break;
        }
        const start = i;
        while (i < data.len and data[i] >= '0' and data[i] <= '9') : (i += 1) {}
        if (i == start) return error.InvalidPpm;
        header_nums[idx] = std.fmt.parseInt(usize, data[start..i], 10) catch return error.InvalidPpm;
        idx += 1;
    }
    if (idx != 3 or i >= data.len) return error.InvalidPpm;
    i += 1; // single whitespace byte after maxval
    const w = header_nums[0];
    const h = header_nums[1];
    const need = w * h * 3;
    if (i + need > data.len) return error.TruncatedPpm;
    return .{ .width = w, .height = h, .pixels = data[i .. i + need] };
}

pub fn renderPagePpm(alloc: std.mem.Allocator, io: std.Io, pdf_path: []const u8, page_num: usize, dpi: u32, tmp_tag: []const u8) !PpmImage {
    const ppm_path = try std.fmt.allocPrint(alloc, "/tmp/vedit_p{d}_{s}.ppm", .{ page_num, tmp_tag });
    defer std.Io.Dir.cwd().deleteFile(io, ppm_path) catch {};
    const dpi_s = try std.fmt.allocPrint(alloc, "{d}", .{dpi});
    const pg_s = try std.fmt.allocPrint(alloc, "{d}", .{page_num});
    const res = try runCmd(alloc, io, &.{ "mutool", "draw", "-F", "ppm", "-r", dpi_s, "-o", ppm_path, pdf_path, pg_s }, null);
    if (res.exit_code != 0) return error.MutoolDrawPpmFailed;
    const raw = try std.Io.Dir.cwd().readFileAlloc(io, ppm_path, alloc, .unlimited);
    return parsePpm(raw);
}

fn parseBoxArray(obj_txt: []const u8, key: []const u8) ?[4]f64 {
    const kpos = std.mem.find(u8, obj_txt, key) orelse return null;
    const lbr = std.mem.findScalarPos(u8, obj_txt, kpos + key.len, '[') orelse return null;
    const rbr = std.mem.findScalarPos(u8, obj_txt, lbr + 1, ']') orelse return null;
    var nums: [4]f64 = .{ 0, 0, 0, 0 };
    if (parseFloatSlice(obj_txt[lbr + 1 .. rbr], &nums) == 4) return nums;
    return null;
}

/// Inspect PDF Catalog, PDF/UA-1 structural tags, embedded fonts, and TrimBox/BleedBox via `mutool`.
pub fn inspectCatalog(alloc: std.mem.Allocator, io: std.Io, pdf_path: []const u8) !CatalogInfo {
    const root_res = try runCmd(alloc, io, &.{ "mutool", "show", pdf_path, "trailer/Root" }, null);
    const info_res = try runCmd(alloc, io, &.{ "mutool", "info", pdf_path }, null);
    const pages_res = try runCmd(alloc, io, &.{ "mutool", "show", pdf_path, "pages" }, null);

    const root = root_res.stdout;
    const marked = std.mem.find(u8, root, "/MarkInfo") != null and containsFold(root, "/Marked true");
    const has_struct = std.mem.find(u8, root, "/StructTreeRoot") != null;
    const has_outlines = std.mem.find(u8, root, "/Outlines") != null;

    var has_lang = false;
    var lang_val: []const u8 = "";
    if (std.mem.find(u8, root, "/Lang")) |lpos| {
        if (std.mem.findScalarPos(u8, root, lpos + 5, '(')) |lp| {
            if (std.mem.findScalarPos(u8, root, lp + 1, ')')) |rp| {
                lang_val = try alloc.dupe(u8, root[lp + 1 .. rp]);
                has_lang = lang_val.len > 0;
            }
        }
    }

    var has_pdfua_xmp = false;
    var xmp_has_title = false;
    if (std.mem.find(u8, root, "/Metadata")) |mpos| {
        const rest = std.mem.trimStart(u8, root[mpos + 9 ..], " \t\r\n");
        var it = std.mem.tokenizeAny(u8, rest, " \t\r\n");
        if (it.next()) |obj_id| {
            const xmp_res = runCmd(alloc, io, &.{ "mutool", "show", "-b", pdf_path, obj_id }, null) catch null;
            if (xmp_res) |xr| {
                if (std.mem.find(u8, xr.stdout, "pdfuaid:part") != null) has_pdfua_xmp = true;
                if (std.mem.find(u8, xr.stdout, "dc:title") != null) xmp_has_title = true;
            }
        }
    }
    const has_title = xmp_has_title or (std.mem.find(u8, info_res.stdout, "/Title") != null);

    // Parse embedded vs unembedded fonts from `mutool info`
    var unemb: std.ArrayList([]const u8) = .empty;
    var emb: std.ArrayList([]const u8) = .empty;
    var seen_fonts = std.StringHashMap(void).init(alloc);
    var in_fonts_sec = false;
    var lines_it = std.mem.splitScalar(u8, info_res.stdout, '\n');
    while (lines_it.next()) |ln| {
        if (std.mem.startsWith(u8, ln, "Fonts (")) {
            in_fonts_sec = true;
            continue;
        }
        if (in_fonts_sec) {
            if (ln.len == 0 or (ln[0] != '\t' and ln[0] != ' ')) {
                in_fonts_sec = false;
                continue;
            }
            if (std.mem.findScalar(u8, ln, '"')) |q1| {
                if (std.mem.findScalarPos(u8, ln, q1 + 1, '"')) |q2| {
                    const raw_fname = ln[q1 + 1 .. q2];
                    const clean_name = stripSubsetPrefix(raw_fname);
                    const is_subset = raw_fname.len > 7 and raw_fname[6] == '+';
                    const is_type3 = std.mem.find(u8, ln, "Type3") != null;
                    if (!seen_fonts.contains(clean_name)) {
                        const owned = try alloc.dupe(u8, clean_name);
                        try seen_fonts.put(owned, {});
                        if (is_subset or is_type3) {
                            try emb.append(alloc, owned);
                        } else {
                            // Check if this non-subset font actually embeds a /FontFile stream
                            var embedded_stream = false;
                            if (std.mem.findScalarLast(u8, ln, '(')) |op| {
                                const obj_tok = std.mem.trim(u8, ln[op + 1 ..], " R)\r");
                                var sp_it = std.mem.tokenizeScalar(u8, obj_tok, ' ');
                                if (sp_it.next()) |fobj| {
                                    const fshow = runCmd(alloc, io, &.{ "mutool", "show", pdf_path, fobj }, null) catch null;
                                    if (fshow) |fs| {
                                        if (std.mem.find(u8, fs.stdout, "/FontFile") != null or std.mem.find(u8, fs.stdout, "/DescendantFonts") != null) {
                                            embedded_stream = true;
                                        }
                                    }
                                }
                            }
                            if (embedded_stream) {
                                try emb.append(alloc, owned);
                            } else {
                                try unemb.append(alloc, owned);
                            }
                        }
                    }
                }
            }
        }
    }

    // Parse pages & bleed boxes
    var pg_count: usize = 0;
    var all_bleed = true;
    var min_bleed: f64 = 1e9;
    var media_w: f64 = 612.0;
    var media_h: f64 = 792.0;
    var pg_it = std.mem.splitScalar(u8, pages_res.stdout, '\n');
    while (pg_it.next()) |pln| {
        if (!std.mem.startsWith(u8, pln, "page ")) continue;
        pg_count += 1;
        if (std.mem.find(u8, pln, "= ")) |eq| {
            const rest = pln[eq + 2 ..];
            var tok_it = std.mem.tokenizeAny(u8, rest, " \t\r\n");
            if (tok_it.next()) |pobj| {
                const pshow = runCmd(alloc, io, &.{ "mutool", "show", pdf_path, pobj }, null) catch continue;
                const mb = parseBoxArray(pshow.stdout, "/MediaBox");
                const tb = parseBoxArray(pshow.stdout, "/TrimBox");
                const bb = parseBoxArray(pshow.stdout, "/BleedBox");
                if (pg_count == 1) {
                    if (mb) |m| {
                        media_w = m[2] - m[0];
                        media_h = m[3] - m[1];
                    }
                }
                var margin: f64 = 0.0;
                if (tb != null and bb != null) {
                    const t = tb.?;
                    const b = bb.?;
                    margin = @min(@min(t[0] - b[0], t[1] - b[1]), @min(b[2] - t[2], b[3] - t[3]));
                } else if (tb != null and mb != null) {
                    const t = tb.?;
                    const m = mb.?;
                    margin = @min(@min(t[0] - m[0], t[1] - m[1]), @min(m[2] - t[2], m[3] - t[3]));
                }
                if (margin < 5.0) all_bleed = false;
                min_bleed = @min(min_bleed, margin);
            }
        }
    }
    if (pg_count == 0) {
        all_bleed = false;
        min_bleed = 0.0;
    }

    return .{
        .page_count = pg_count,
        .marked = marked,
        .has_struct_tree = has_struct,
        .has_lang = has_lang,
        .lang = lang_val,
        .has_title = has_title,
        .has_outlines = has_outlines,
        .has_pdfua_xmp = has_pdfua_xmp,
        .bleed_all_pages = all_bleed,
        .min_bleed_margin_pt = if (min_bleed > 1e8) 0.0 else min_bleed,
        .unembedded_fonts = try unemb.toOwnedSlice(alloc),
        .embedded_fonts = try emb.toOwnedSlice(alloc),
        .media_w = media_w,
        .media_h = media_h,
    };
}

test "stripBtEtStreams preserves length and blanks Typst BT/Span blocks" {
    const alloc = std.testing.allocator;
    const sample = "q 1 0 0 1 0 0 cm\nBT/Span<</ActualText( )>>BDC /f1 9 Tf (hi)Tj EMC ET\nQ\n";
    const out = try stripBtEtStreams(alloc, sample);
    defer alloc.free(out);
    try std.testing.expectEqual(sample.len, out.len);
    try std.testing.expect(std.mem.find(u8, out, "BT") == null);
    try std.testing.expect(std.mem.find(u8, out, "ET") == null);
    try std.testing.expect(std.mem.find(u8, out, "q 1 0 0 1 0 0 cm") != null);
    try std.testing.expect(std.mem.find(u8, out, "\nQ\n") != null);
}

test "parsePpm decodes minimal P6 raster" {
    const ppm = "P6\n2 1\n255\n\x01\x02\x03\xfe\xfd\xfc";
    const img = try parsePpm(ppm);
    try std.testing.expectEqual(@as(usize, 2), img.width);
    try std.testing.expectEqual(@as(usize, 1), img.height);
    const p0 = img.pixelAt(0, 0);
    const p1 = img.pixelAt(1, 0);
    try std.testing.expectEqual(@as(u8, 1), p0.r);
    try std.testing.expectEqual(@as(u8, 254), p1.r);
}

test "stripClipPathStreams neutralizes W n and W* n inside streams without touching dicts or strings" {
    const alloc = std.testing.allocator;
    const sample = "<< /Width 612 /W [1 2] >>\nstream\n50 680 80 30 re W n\n(Hello W n) Tj\n10 10 20 20 re W* n\nendstream\n";
    const out = try stripClipPathStreams(alloc, sample);
    defer alloc.free(out);
    try std.testing.expectEqual(sample.len, out.len);
    try std.testing.expect(std.mem.find(u8, out, "/Width 612 /W [1 2]") != null);
    try std.testing.expect(std.mem.find(u8, out, "(Hello W n)") != null);
    try std.testing.expect(std.mem.find(u8, out, "re   n") != null);
    try std.testing.expect(std.mem.find(u8, out, "re    n") != null);
}

test "rewriteImagesToSolidKey swaps Image XObject and preserves SMask object untouched" {
    const alloc = std.testing.allocator;
    const payload_a: [200]u8 = @splat('A');
    const payload_b: [20]u8 = @splat('B');
    const sample = try std.fmt.allocPrint(
        alloc,
        "5 0 obj\n<< /Type /XObject /Subtype /Image /Width 64 /Height 64 /ColorSpace /DeviceRGB /SMask 6 0 R /Length 200 >>\nstream\n{s}\nendstream\nendobj\n6 0 obj\n<< /Type /XObject /Subtype /Image /Width 64 /Height 64 /ColorSpace /DeviceGray /Length 20 >>\nstream\n{s}\nendstream\nendobj\n",
        .{ payload_a, payload_b },
    );
    defer alloc.free(sample);
    const res = try rewriteImagesToSolidKey(alloc, sample, .{ .r = 255, .g = 0, .b = 255 });
    defer alloc.free(res.bytes);
    try std.testing.expectEqual(@as(usize, 1), res.replaced_count);
    try std.testing.expect(!res.needs_xref_repair);
    try std.testing.expectEqual(sample.len, res.bytes.len);
    try std.testing.expect(std.mem.find(u8, res.bytes, "/SMask 6 0 R") != null);
    try std.testing.expect(std.mem.find(u8, res.bytes, "BBBBBBBBBBBBBBBBBBBB") != null);
}
