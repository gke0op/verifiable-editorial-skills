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

pub const PageLink = struct {
    page: usize,
    uri: []const u8,
    x0: f64,
    y0: f64,
    x1: f64,
    y1: f64,
    is_hidden: bool = false,
    is_extra_action: bool = false,
};

pub const PageData = struct {
    page_num: usize,
    width: f64,
    height: f64,
    spans: []const PageSpan,
    images: []const PlacedImage,
    graphics: []const FillSample,
    stroke_count: usize,
    /// Count of visible printable glyphs sliced by an active `<clip_path>`/`<clip_text>` in `mutool draw -F trace`
    /// (works identically on mutool 1.23 where `stext` ignores W/W* clip paths as well as 1.24+).
    trace_clipped_chars: usize = 0,
    /// Suspicious glyph/ToUnicode width anomalies detected directly from `mutool draw -F trace`.
    tounicode_anomalies: []const []const u8 = &.{},
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

pub const PamCmykImage = struct {
    width: usize,
    height: usize,
    pixels: []const u8, // CMYKCMYK... len == width * height * 4
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

var g_tmp_seq = std.atomic.Value(u64).init(0);

/// Create a private `0700` per-invocation temp directory under `/tmp` with PID + CSPRNG entropy.
pub fn makePrivateTmpDir(alloc: std.mem.Allocator, io: std.Io) ![]u8 {
    const pid = std.c.getpid();
    const seq = g_tmp_seq.fetchAdd(1, .monotonic);
    var rbytes: [8]u8 = undefined;
    io.random(&rbytes);
    const rhex = std.fmt.bytesToHex(rbytes, .lower);
    const dir_path = try std.fmt.allocPrint(alloc, "/tmp/vedit_{d}_{d}_{s}", .{ pid, seq, rhex });
    try std.Io.Dir.cwd().createDirPath(io, dir_path);
    const zpath = try alloc.dupeSentinel(u8, dir_path, 0);
    defer alloc.free(zpath);
    _ = std.c.chmod(zpath.ptr, 0o700);
    return dir_path;
}

/// Allocate a race-free temp file path inside a private `tmp_tag` directory (if leading `/`) or uniquely suffixed by PID + atomic seq.
pub fn tmpPath(alloc: std.mem.Allocator, tmp_tag: []const u8, filename: []const u8) ![]u8 {
    const seq = g_tmp_seq.fetchAdd(1, .monotonic);
    if (tmp_tag.len > 0 and tmp_tag[0] == '/') {
        return try std.fmt.allocPrint(alloc, "{s}/{d}_{s}", .{ tmp_tag, seq, filename });
    }
    const pid = std.c.getpid();
    return try std.fmt.allocPrint(alloc, "/tmp/vedit_{d}_{d}_{s}_{s}", .{ pid, seq, tmp_tag, filename });
}

/// Checked finite & bounded float-to-integer rounding (prevents ReleaseSafe `@intFromFloat` SIGABRT DoS).
pub fn checkedRoundInt(comptime T: type, v: f64, lo: f64, hi: f64) !T {
    if (!std.math.isFinite(v)) return error.NonFiniteFloat;
    const r = @round(v);
    if (r < lo or r > hi) return error.FloatOutOfRange;
    return @intFromFloat(r);
}

/// RFC 8259 JSON string serializer (returns quoted & escaped `"..."` string using `std.json.Stringify`).
pub fn jsonString(alloc: std.mem.Allocator, s: []const u8) ![]u8 {
    var w: std.Io.Writer.Allocating = .init(alloc);
    errdefer w.deinit();
    try std.json.Stringify.encodeJsonString(s, .{}, &w.writer);
    return try w.toOwnedSlice();
}

/// Best-effort temporary file removal: ignores `FileNotFound`, logs unexpected OS errors in debug.
pub fn removeTmpBestEffort(io: std.Io, path: []const u8) void {
    std.Io.Dir.cwd().deleteFile(io, path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => std.log.debug("tmp cleanup skipped for {s}: {s}", .{ path, @errorName(err) }),
    };
}

/// Best-effort private temp directory tree removal.
pub fn removeTmpDirBestEffort(io: std.Io, path: []const u8) void {
    std.Io.Dir.cwd().deleteTree(io, path) catch |err| {
        std.log.debug("tmp dir cleanup skipped for {s}: {s}", .{ path, @errorName(err) });
    };
}

/// Best-effort diagnostic write to stderr.
pub fn writeStderrBestEffort(io: std.Io, s: []const u8) void {
    std.Io.File.stderr().writeStreamingAll(io, s) catch |err| {
        std.log.debug("stderr write failed: {s}", .{@errorName(err)});
    };
}

pub const RunResult = struct {
    stdout: []u8,
    stderr: []u8,
    exit_code: u8,
};

pub fn runCmd(alloc: std.mem.Allocator, io: std.Io, argv: []const []const u8, cwd: ?[]const u8) !RunResult {
    const res = std.process.run(alloc, io, .{
        .argv = argv,
        .cwd = if (cwd) |p| .{ .path = p } else .inherit,
        .stdout_limit = .unlimited,
        .stderr_limit = .unlimited,
    }) catch |err| {
        if (err == error.FileNotFound and argv.len > 0 and std.mem.eql(u8, argv[0], "mutool")) {
            writeStderrBestEffort(
                io,
                "[vedit] error: 'mutool' not found on PATH — install mupdf-tools (Ubuntu: sudo apt install mupdf-tools | macOS: brew install mupdf-tools)\n",
            );
            return error.MutoolNotFound;
        }
        return err;
    };
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

const ClipRect = struct { x0: f64, y0: f64, x1: f64, y1: f64 };

const ClipPoly = struct {
    pts: []const [2]f64,
};

const ClipShape = struct {
    rect: ClipRect,
    is_rect: bool = true,
    eofill: bool = false,
    subpaths: []const ClipPoly = &.{},
};

fn isAsciiAlnum(ch: u8) bool {
    return (ch >= 'A' and ch <= 'Z') or (ch >= 'a' and ch <= 'z') or (ch >= '0' and ch <= '9');
}

fn isPrintableGlyphCodepoint(cp: u21) bool {
    if (cp < 0x80) return isAsciiAlnum(@intCast(cp));
    // Exclude whitespace/control/format/punctuation-only ranges; include Latin Extended, Greek, Cyrillic, CJK, Math Alnum
    if (cp == 0x00A0 or cp == 0x00AD or (cp >= 0x2000 and cp <= 0x206F)) return false;
    return cp >= 0x00C0;
}

fn decodeSingleGlyphCodepoint(raw: []const u8) ?u21 {
    if (raw.len == 0) return null;
    if (raw[0] == '&') {
        if (raw.len > 4 and std.mem.startsWith(u8, raw, "&#x") and raw[raw.len - 1] == ';') {
            return std.fmt.parseInt(u21, raw[3 .. raw.len - 1], 16) catch null;
        }
        if (raw.len > 3 and std.mem.startsWith(u8, raw, "&#") and raw[raw.len - 1] == ';') {
            return std.fmt.parseInt(u21, raw[2 .. raw.len - 1], 10) catch null;
        }
        return null;
    }
    const len = std.unicode.utf8ByteSequenceLength(raw[0]) catch return null;
    if (len != raw.len) return null;
    return std.unicode.utf8Decode(raw) catch null;
}

fn isTallGlyph(cp: u21) bool {
    if (cp >= 0x80) return true;
    const ch: u8 = @intCast(cp);
    return (ch >= 'A' and ch <= 'Z') or (ch >= '0' and ch <= '9') or
        ch == 'b' or ch == 'd' or ch == 'f' or ch == 'h' or ch == 'i' or ch == 'k' or ch == 'l' or ch == 't';
}

fn isDescGlyph(cp: u21) bool {
    if (cp >= 0x80) return false;
    const ch: u8 = @intCast(cp);
    return ch == 'g' or ch == 'j' or ch == 'p' or ch == 'q' or ch == 'y';
}

fn pointInSubpaths(px: f64, py: f64, subpaths: []const ClipPoly, eofill: bool) bool {
    if (subpaths.len == 0) return true;
    if (eofill) {
        var inside = false;
        for (subpaths) |sp| {
            const n = sp.pts.len;
            if (n < 3) continue;
            var j: usize = n - 1;
            for (0..n) |i| {
                const xi = sp.pts[i][0];
                const yi = sp.pts[i][1];
                const xj = sp.pts[j][0];
                const yj = sp.pts[j][1];
                if (((yi > py) != (yj > py)) and (px < (xj - xi) * (py - yi) / (yj - yi) + xi)) {
                    inside = !inside;
                }
                j = i;
            }
        }
        return inside;
    } else {
        var winding: i32 = 0;
        for (subpaths) |sp| {
            const n = sp.pts.len;
            if (n < 3) continue;
            for (0..n) |i| {
                const a = sp.pts[i];
                const b = sp.pts[(i + 1) % n];
                if (a[1] <= py) {
                    if (b[1] > py and ((b[0] - a[0]) * (py - a[1]) - (px - a[0]) * (b[1] - a[1])) > 0.0) {
                        winding += 1;
                    }
                } else {
                    if (b[1] <= py and ((b[0] - a[0]) * (py - a[1]) - (px - a[0]) * (b[1] - a[1])) < 0.0) {
                        winding -= 1;
                    }
                }
            }
        }
        return winding != 0;
    }
}

fn pointInSubpathsTol(px: f64, py: f64, subpaths: []const ClipPoly, eofill: bool, tol: f64) bool {
    if (pointInSubpaths(px, py, subpaths, eofill)) return true;
    if (tol <= 0.0) return false;
    const offsets = [_][2]f64{ .{ tol, 0 }, .{ -tol, 0 }, .{ 0, tol }, .{ 0, -tol } };
    for (offsets) |d| {
        if (pointInSubpaths(px + d[0], py + d[1], subpaths, eofill)) return true;
    }
    return false;
}

fn isSignedDigitsTrimmed(raw: []const u8) bool {
    const s = std.mem.trim(u8, raw, " \t\r\n");
    if (s.len == 0) return false;
    var i: usize = 0;
    if (s[0] == '+' or s[0] == '-') {
        i = 1;
    } else if (s.len >= 3 and s[0] == 0xE2 and s[1] == 0x88 and s[2] == 0x92) {
        i = 3; // UTF-8 Unicode minus '−' (U+2212)
    }
    if (i >= s.len) return false;
    while (i < s.len) : (i += 1) {
        if (s[i] < '0' or s[i] > '9') return false;
    }
    return true;
}

fn proseEndsWithStandalone10(items: []const u8) bool {
    var end = items.len;
    while (end > 0 and (items[end - 1] == ' ' or items[end - 1] == '\t')) : (end -= 1) {}
    if (end < 2) return false;
    if (items[end - 2] != '1' or items[end - 1] != '0') return false;
    if (end >= 3 and items[end - 3] >= '0' and items[end - 3] <= '9') return false;
    return true;
}

fn proseEndsWithSmallIntBase(items: []const u8) bool {
    var end = items.len;
    while (end > 0 and (items[end - 1] == ' ' or items[end - 1] == '\t')) : (end -= 1) {}
    if (end == 0) return false;
    const last = items[end - 1];
    if (last < '2' or last > '9') return false;
    if (end >= 2 and (isAsciiAlnum(items[end - 2]) or items[end - 2] == '.')) return false;
    return true;
}

fn isAxisAlignedRectSubpath(pts: []const [2]f64) bool {
    if (pts.len < 4 or pts.len > 5) return false;
    const n = if (pts.len == 5 and @abs(pts[0][0] - pts[4][0]) < 1e-3 and @abs(pts[0][1] - pts[4][1]) < 1e-3) @as(usize, 4) else pts.len;
    if (n != 4) return false;
    for (0..4) |i| {
        const a = pts[i];
        const b = pts[(i + 1) % 4];
        const dx = @abs(b[0] - a[0]);
        const dy = @abs(b[1] - a[1]);
        if (dx > 0.05 and dy > 0.05) return false;
    }
    return true;
}

/// Count printable glyphs inside `<fill_text>`/`<stroke_text>` whose 4-corner ink core lies inside
/// the visible page `[0, page_w] x [0, page_h]` yet extends outside ANY active `<clip_path>`/`<clip_text>`
/// (supporting unbounded dynamic clip stack depth, curved/diagonal/even-odd polygons, and non-ASCII UTF-8 glyphs).
pub fn countTraceClippedAlnum(alloc: std.mem.Allocator, page_xml: []const u8, page_w: f64, page_h: f64) !usize {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();

    var stack: std.ArrayList(ClipShape) = .empty;
    try stack.append(a, .{ .rect = .{ .x0 = 0.0, .y0 = 0.0, .x1 = page_w, .y1 = page_h } });

    var in_clip_path = false;
    var in_clip_text = false;
    var clip_eofill = false;
    var clip_tf: [6]f64 = .{ 1, 0, 0, 1, 0, 0 };
    var clip_trm: [4]f64 = .{ 10, 0, 0, 10 };
    var cp_x0: f64 = 1e18;
    var cp_y0: f64 = 1e18;
    var cp_x1: f64 = -1e18;
    var cp_y1: f64 = -1e18;
    var cp_has_pts = false;
    var cp_has_curve = false;
    var cp_subpaths: std.ArrayList(ClipPoly) = .empty;
    var cur_sub: std.ArrayList([2]f64) = .empty;
    var cur_pt: [2]f64 = .{ 0.0, 0.0 };

    var in_text = false;
    var txt_tf: [6]f64 = .{ 1, 0, 0, 1, 0, 0 };
    var trm: [4]f64 = .{ 10, 0, 0, 10 };
    var clipped: usize = 0;

    var pos: usize = 0;
    while (std.mem.findScalarPos(u8, page_xml, pos, '<')) |lt| {
        const gt = std.mem.findScalarPos(u8, page_xml, lt + 1, '>') orelse break;
        const tag = page_xml[lt + 1 .. gt];
        pos = gt + 1;
        const self_closing = (tag.len > 0 and tag[tag.len - 1] == '/');

        if (std.mem.startsWith(u8, tag, "clip_path")) {
            in_clip_path = !self_closing;
            clip_eofill = if (extractAttr(tag, "winding")) |wv| std.mem.eql(u8, wv, "eofill") else false;
            clip_tf = .{ 1, 0, 0, 1, 0, 0 };
            if (extractAttr(tag, "transform")) |tv| _ = parseFloatSlice(tv, &clip_tf);
            cp_x0 = 1e18;
            cp_y0 = 1e18;
            cp_x1 = -1e18;
            cp_y1 = -1e18;
            cp_has_pts = false;
            cp_has_curve = false;
            cp_subpaths = .empty;
            cur_sub = .empty;
            if (self_closing) {
                try stack.append(a, stack.items[stack.items.len - 1]);
            }
        } else if (std.mem.eql(u8, tag, "/clip_path")) {
            in_clip_path = false;
            if (cur_sub.items.len >= 3) {
                const pts = try cur_sub.toOwnedSlice(a);
                if (pts.len >= 3) try cp_subpaths.append(a, .{ .pts = pts });
            }
            const prev = stack.items[stack.items.len - 1];
            if (cp_has_pts) {
                const subs = try cp_subpaths.toOwnedSlice(a);
                const is_rect = (!cp_has_curve) and subs.len == 1 and isAxisAlignedRectSubpath(subs[0].pts);
                try stack.append(a, .{
                    .rect = .{
                        .x0 = @max(prev.rect.x0, cp_x0),
                        .y0 = @max(prev.rect.y0, cp_y0),
                        .x1 = @min(prev.rect.x1, cp_x1),
                        .y1 = @min(prev.rect.y1, cp_y1),
                    },
                    .is_rect = is_rect,
                    .eofill = clip_eofill,
                    .subpaths = if (is_rect) &.{} else subs,
                });
            } else {
                try stack.append(a, prev);
            }
        } else if (std.mem.startsWith(u8, tag, "clip_text")) {
            in_clip_text = !self_closing;
            clip_tf = .{ 1, 0, 0, 1, 0, 0 };
            if (extractAttr(tag, "transform")) |tv| _ = parseFloatSlice(tv, &clip_tf);
            clip_trm = .{ 10, 0, 0, 10 };
            cp_x0 = 1e18;
            cp_y0 = 1e18;
            cp_x1 = -1e18;
            cp_y1 = -1e18;
            cp_has_pts = false;
            if (self_closing) {
                try stack.append(a, stack.items[stack.items.len - 1]);
            }
        } else if (std.mem.eql(u8, tag, "/clip_text")) {
            in_clip_text = false;
            const prev = stack.items[stack.items.len - 1];
            try stack.append(a, if (cp_has_pts) .{
                .rect = .{
                    .x0 = @max(prev.rect.x0, cp_x0),
                    .y0 = @max(prev.rect.y0, cp_y0),
                    .x1 = @min(prev.rect.x1, cp_x1),
                    .y1 = @min(prev.rect.y1, cp_y1),
                },
            } else prev);
        } else if (std.mem.startsWith(u8, tag, "clip_stroke_path") or
            std.mem.startsWith(u8, tag, "clip_image_mask"))
        {
            try stack.append(a, stack.items[stack.items.len - 1]);
        } else if (std.mem.startsWith(u8, tag, "pop_clip")) {
            if (stack.items.len > 1) _ = stack.pop();
        } else if (in_clip_path) {
            if (std.mem.startsWith(u8, tag, "moveto ")) {
                if (cur_sub.items.len >= 3) {
                    const pts = try cur_sub.toOwnedSlice(a);
                    if (pts.len >= 3) try cp_subpaths.append(a, .{ .pts = pts });
                }
                cur_sub = .empty;
                if (extractAttr(tag, "x")) |xv| {
                    if (extractAttr(tag, "y")) |yv| {
                        const x = std.fmt.parseFloat(f64, xv) catch continue;
                        const y = std.fmt.parseFloat(f64, yv) catch continue;
                        const tx = clip_tf[0] * x + clip_tf[2] * y + clip_tf[4];
                        const ty = clip_tf[1] * x + clip_tf[3] * y + clip_tf[5];
                        cp_x0 = @min(cp_x0, tx);
                        cp_y0 = @min(cp_y0, ty);
                        cp_x1 = @max(cp_x1, tx);
                        cp_y1 = @max(cp_y1, ty);
                        cp_has_pts = true;
                        cur_pt = .{ tx, ty };
                        try cur_sub.append(a, cur_pt);
                    }
                }
            } else if (std.mem.startsWith(u8, tag, "lineto ")) {
                if (extractAttr(tag, "x")) |xv| {
                    if (extractAttr(tag, "y")) |yv| {
                        const x = std.fmt.parseFloat(f64, xv) catch continue;
                        const y = std.fmt.parseFloat(f64, yv) catch continue;
                        const tx = clip_tf[0] * x + clip_tf[2] * y + clip_tf[4];
                        const ty = clip_tf[1] * x + clip_tf[3] * y + clip_tf[5];
                        cp_x0 = @min(cp_x0, tx);
                        cp_y0 = @min(cp_y0, ty);
                        cp_x1 = @max(cp_x1, tx);
                        cp_y1 = @max(cp_y1, ty);
                        cp_has_pts = true;
                        cur_pt = .{ tx, ty };
                        try cur_sub.append(a, cur_pt);
                    }
                }
            } else if (std.mem.startsWith(u8, tag, "curveto ")) {
                cp_has_curve = true;
                const x1v = extractAttr(tag, "x1") orelse continue;
                const y1v = extractAttr(tag, "y1") orelse continue;
                const x2v = extractAttr(tag, "x2") orelse continue;
                const y2v = extractAttr(tag, "y2") orelse continue;
                const x3v = extractAttr(tag, "x3") orelse continue;
                const y3v = extractAttr(tag, "y3") orelse continue;
                const x1 = std.fmt.parseFloat(f64, x1v) catch continue;
                const y1 = std.fmt.parseFloat(f64, y1v) catch continue;
                const x2 = std.fmt.parseFloat(f64, x2v) catch continue;
                const y2 = std.fmt.parseFloat(f64, y2v) catch continue;
                const x3 = std.fmt.parseFloat(f64, x3v) catch continue;
                const y3 = std.fmt.parseFloat(f64, y3v) catch continue;
                const p0 = cur_pt;
                const p1 = [2]f64{ clip_tf[0] * x1 + clip_tf[2] * y1 + clip_tf[4], clip_tf[1] * x1 + clip_tf[3] * y1 + clip_tf[5] };
                const p2 = [2]f64{ clip_tf[0] * x2 + clip_tf[2] * y2 + clip_tf[4], clip_tf[1] * x2 + clip_tf[3] * y2 + clip_tf[5] };
                const p3 = [2]f64{ clip_tf[0] * x3 + clip_tf[2] * y3 + clip_tf[4], clip_tf[1] * x3 + clip_tf[3] * y3 + clip_tf[5] };
                // Sample cubic Bezier into 8 segments so circular/rounded clips evaluate accurately
                const steps: usize = 8;
                for (1..steps + 1) |si| {
                    const t = @as(f64, @floatFromInt(si)) / @as(f64, @floatFromInt(steps));
                    const u = 1.0 - t;
                    const bx = u * u * u * p0[0] + 3.0 * u * u * t * p1[0] + 3.0 * u * t * t * p2[0] + t * t * t * p3[0];
                    const by = u * u * u * p0[1] + 3.0 * u * u * t * p1[1] + 3.0 * u * t * t * p2[1] + t * t * t * p3[1];
                    cp_x0 = @min(cp_x0, bx);
                    cp_y0 = @min(cp_y0, by);
                    cp_x1 = @max(cp_x1, bx);
                    cp_y1 = @max(cp_y1, by);
                    cp_has_pts = true;
                    try cur_sub.append(a, .{ bx, by });
                }
                cur_pt = p3;
            }
        } else if (in_clip_text) {
            if (std.mem.startsWith(u8, tag, "span ")) {
                clip_trm = .{ 10, 0, 0, 10 };
                if (extractAttr(tag, "trm")) |trv| _ = parseFloatSlice(trv, &clip_trm);
            } else if (std.mem.startsWith(u8, tag, "g ")) {
                const xv = extractAttr(tag, "x") orelse continue;
                const yv = extractAttr(tag, "y") orelse continue;
                const x = std.fmt.parseFloat(f64, xv) catch continue;
                const y = std.fmt.parseFloat(f64, yv) catch continue;
                const adv = if (extractAttr(tag, "adv")) |av| (std.fmt.parseFloat(f64, av) catch 0.5) else 0.5;
                const ox = clip_tf[0] * x + clip_tf[2] * y + clip_tf[4];
                const oy = clip_tf[1] * x + clip_tf[3] * y + clip_tf[5];
                const dx = clip_tf[0] * (adv * clip_trm[0]) + clip_tf[2] * (adv * clip_trm[1]);
                const dy = clip_tf[1] * (adv * clip_trm[0]) + clip_tf[3] * (adv * clip_trm[1]);
                const ax = clip_tf[0] * clip_trm[2] + clip_tf[2] * clip_trm[3];
                const ay = clip_tf[1] * clip_trm[2] + clip_tf[3] * clip_trm[3];
                const us = [_]f64{ 0.0, 1.0 };
                const vs = [_]f64{ -0.25, 0.85 };
                for (us) |u| {
                    for (vs) |v| {
                        const px = ox + u * dx + v * ax;
                        const py = oy + u * dy + v * ay;
                        cp_x0 = @min(cp_x0, px);
                        cp_y0 = @min(cp_y0, py);
                        cp_x1 = @max(cp_x1, px);
                        cp_y1 = @max(cp_y1, py);
                        cp_has_pts = true;
                    }
                }
            }
        } else if (std.mem.startsWith(u8, tag, "fill_text") or std.mem.startsWith(u8, tag, "stroke_text")) {
            in_text = !self_closing;
            txt_tf = .{ 1, 0, 0, 1, 0, 0 };
            if (extractAttr(tag, "transform")) |tv| _ = parseFloatSlice(tv, &txt_tf);
            trm = .{ 10, 0, 0, 10 };
        } else if (std.mem.eql(u8, tag, "/fill_text") or std.mem.eql(u8, tag, "/stroke_text")) {
            in_text = false;
        } else if (in_text and std.mem.startsWith(u8, tag, "span ")) {
            trm = .{ 10, 0, 0, 10 };
            if (extractAttr(tag, "trm")) |trv| _ = parseFloatSlice(trv, &trm);
        } else if (in_text and stack.items.len > 1 and std.mem.startsWith(u8, tag, "g ")) {
            const uval = extractAttr(tag, "unicode") orelse continue;
            const cp = decodeSingleGlyphCodepoint(uval) orelse continue;
            if (!isPrintableGlyphCodepoint(cp)) continue;
            const xv = extractAttr(tag, "x") orelse continue;
            const yv = extractAttr(tag, "y") orelse continue;
            const x = std.fmt.parseFloat(f64, xv) catch continue;
            const y = std.fmt.parseFloat(f64, yv) catch continue;
            const adv = if (extractAttr(tag, "adv")) |av| (std.fmt.parseFloat(f64, av) catch 0.5) else 0.5;

            const ox = txt_tf[0] * x + txt_tf[2] * y + txt_tf[4];
            const oy = txt_tf[1] * x + txt_tf[3] * y + txt_tf[5];
            const dx = txt_tf[0] * (adv * trm[0]) + txt_tf[2] * (adv * trm[1]);
            const dy = txt_tf[1] * (adv * trm[0]) + txt_tf[3] * (adv * trm[1]);
            const ax = txt_tf[0] * trm[2] + txt_tf[2] * trm[3];
            const ay = txt_tf[1] * trm[2] + txt_tf[3] * trm[3];

            const v0: f64 = if (isDescGlyph(cp)) -0.14 else 0.05;
            const v1: f64 = if (isTallGlyph(cp)) 0.62 else 0.48;
            const p00_x = ox + 0.15 * dx + v0 * ax;
            const p00_y = oy + 0.15 * dy + v0 * ay;
            const p10_x = ox + 0.85 * dx + v0 * ax;
            const p10_y = oy + 0.85 * dy + v0 * ay;
            const p01_x = ox + 0.15 * dx + v1 * ax;
            const p01_y = oy + 0.15 * dy + v1 * ay;
            const p11_x = ox + 0.85 * dx + v1 * ax;
            const p11_y = oy + 0.85 * dy + v1 * ay;

            const gx0 = @min(@min(p00_x, p10_x), @min(p01_x, p11_x));
            const gx1 = @max(@max(p00_x, p10_x), @max(p01_x, p11_x));
            const gy0 = @min(@min(p00_y, p10_y), @min(p01_y, p11_y));
            const gy1 = @max(@max(p00_y, p10_y), @max(p01_y, p11_y));
            const mx = 0.5 * (gx0 + gx1);
            const my = 0.5 * (gy0 + gy1);

            // Flag any visible-page glyph whose 4-corner ink core extends outside ANY active clip box/polygon
            if (mx >= 0.0 and mx <= page_w and my >= 0.0 and my <= page_h) {
                const top = stack.items[stack.items.len - 1].rect;
                const tol: f64 = 1.0;
                var is_out = (gx0 < top.x0 - tol or gx1 > top.x1 + tol or gy0 < top.y0 - tol or gy1 > top.y1 + tol);
                if (!is_out) {
                    const corners = [_][2]f64{
                        .{ p00_x, p00_y },
                        .{ p10_x, p10_y },
                        .{ p01_x, p01_y },
                        .{ p11_x, p11_y },
                    };
                    for (stack.items[1..]) |cs| {
                        if (cs.is_rect or cs.subpaths.len == 0) continue;
                        for (corners) |pt| {
                            if (!pointInSubpathsTol(pt[0], pt[1], cs.subpaths, cs.eofill, tol)) {
                                is_out = true;
                                break;
                            }
                        }
                        if (is_out) break;
                    }
                }
                if (is_out) clipped += 1;
            }
        }
    }
    return clipped;
}

fn isWideUppercaseLetter(uval: []const u8) bool {
    if (uval.len != 1) return false;
    return switch (uval[0]) {
        'A', 'D', 'G', 'H', 'M', 'N', 'O', 'Q', 'W' => true,
        else => false,
    };
}

fn collectTraceToUnicodeAnomalies(alloc: std.mem.Allocator, page_xml: []const u8, page_num: usize) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var seen_keys = std.StringHashMap(void).init(alloc);
    var in_text = false;
    var cur_font: []const u8 = "";
    var is_condensed = false;
    var pos: usize = 0;
    while (std.mem.findScalarPos(u8, page_xml, pos, '<')) |lt| {
        const gt = std.mem.findScalarPos(u8, page_xml, lt + 1, '>') orelse break;
        const tag = page_xml[lt + 1 .. gt];
        pos = gt + 1;
        const self_closing = (tag.len > 0 and tag[tag.len - 1] == '/');
        if (std.mem.startsWith(u8, tag, "fill_text") or std.mem.startsWith(u8, tag, "stroke_text")) {
            in_text = !self_closing;
        } else if (std.mem.eql(u8, tag, "/fill_text") or std.mem.eql(u8, tag, "/stroke_text")) {
            in_text = false;
        } else if (in_text and std.mem.startsWith(u8, tag, "span ")) {
            cur_font = extractAttr(tag, "font") orelse "";
            is_condensed = containsFold(cur_font, "cond") or containsFold(cur_font, "narrow") or
                containsFold(cur_font, "comp") or containsFold(cur_font, "thin");
        } else if (in_text and !is_condensed and std.mem.startsWith(u8, tag, "g ")) {
            const uval = extractAttr(tag, "unicode") orelse continue;
            if (!isWideUppercaseLetter(uval)) continue;
            const adv_s = extractAttr(tag, "adv") orelse continue;
            const adv = std.fmt.parseFloat(f64, adv_s) catch continue;
            // Tabular digits have narrow ~0.44-0.50em advance; wide capitals ('A','M','W','G','D','H','O','Q') are >=0.56em in proportional/mono fonts
            if (adv > 0.05 and adv < 0.50) {
                const gid = extractAttr(tag, "glyph") orelse "?";
                const key = try std.fmt.allocPrint(alloc, "{s}:{s}:{s}", .{ cur_font, gid, uval });
                if (!seen_keys.contains(key)) {
                    try seen_keys.put(key, {});
                    try out.append(alloc, try std.fmt.allocPrint(alloc, "p.{d} font '{s}' glyph {s} mapped to '{s}' has suspicious digit-like advance {d:.3}em (possible /ToUnicode spoof)", .{ page_num, stripSubsetPrefix(cur_font), gid, uval, adv }));
                }
            }
        }
    }
    return out.toOwnedSlice(alloc);
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
    var prev_line_span_cy: f64 = -1e9;

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
            prev_line_span_cy = -1e9;
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
            const next_col_opt: ?Rgb = if (extractAttr(tag, "color")) |col| parseHexColor(col) else null;
            const raw_c = extractAttr(tag, "c") orelse "";
            const is_space_char = (raw_c.len == 1 and raw_c[0] == ' ');
            const color_changed = has_glyph and !is_space_char and next_col_opt != null and
                (next_col_opt.?.r != cur_fg.r or next_col_opt.?.g != cur_fg.g or next_col_opt.?.b != cur_fg.b);
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
                    const spatial_split = has_glyph and ((qx0 - prev_cx1) > cur_size * 1.8 or (prev_cx1 - qx1) > cur_size * 1.8 or @abs(qcy - prev_cy) > cur_size * 0.45);
                    // Split into a new span on spatial jump OR foreground color transition (defeats trailing-dot cur_fg overwrite)
                    if (spatial_split or color_changed) {
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
                            if (spatial_split) try prose.append(alloc, ' ');
                            prev_line_span_size = cur_size;
                            prev_line_span_cy = (sy0 + sy1) * 0.5;
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
            if (raw_c.len > 0) {
                try decodeXmlChar(alloc, raw_c, &cur_chars);
            }
            if (next_col_opt) |nc| {
                if (!is_space_char or !has_glyph) cur_fg = nc;
            }
            if (extractAttr(tag, "flags")) |fl| {
                const fval = std.fmt.parseInt(u32, fl, 10) catch 0;
                if ((fval & 16) != 0) cur_bold = true;
            }
        } else if (std.mem.eql(u8, tag, "/font") and in_font) {
            in_font = false;
            const raw_txt = cur_chars.items;
            const cur_cy: f64 = if (has_glyph) (sy0 + sy1) * 0.5 else prev_line_span_cy;
            // Preserve raised scientific `10^exp` (including sub-1.5pt baseline shifts) and small integer bases `2^9`
            if (raw_txt.len > 0) {
                const raised_base10 = prev_line_span_size > 0.0 and
                    cur_size <= prev_line_span_size - 0.5 and
                    cur_cy < prev_line_span_cy - prev_line_span_size * 0.12 and
                    isSignedDigitsTrimmed(raw_txt) and
                    proseEndsWithStandalone10(prose.items);
                const raised_small_base = prev_line_span_size > 0.0 and
                    cur_size <= prev_line_span_size - 0.8 and
                    cur_cy < prev_line_span_cy - prev_line_span_size * 0.15 and
                    isSignedDigitsTrimmed(raw_txt) and
                    proseEndsWithSmallIntBase(prose.items);
                if (raised_base10 or raised_small_base) {
                    while (prose.items.len > 0 and (prose.items[prose.items.len - 1] == ' ' or prose.items[prose.items.len - 1] == '\t')) {
                        _ = prose.pop();
                    }
                    try prose.append(alloc, '^');
                    try prose.appendSlice(alloc, std.mem.trim(u8, raw_txt, " \t\r\n"));
                } else {
                    if (prev_line_span_size > 0.0 and @abs(cur_size - prev_line_span_size) >= 1.5) {
                        if (prose.items.len > 0 and prose.items[prose.items.len - 1] != ' ' and prose.items[prose.items.len - 1] != '\n' and raw_txt[0] != ' ') {
                            try prose.append(alloc, ' ');
                        }
                    }
                    try prose.appendSlice(alloc, raw_txt);
                }
                prev_line_span_size = cur_size;
                if (has_glyph) prev_line_span_cy = cur_cy;
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

    // Parse trace XML to attach placed images, fill colors, vector stroke counts, and clip-sliced glyph counts per page
    const txml = trace_res.stdout;
    var tpos: usize = 0;
    var tpage_idx: usize = 0;
    var tpage_body_start: usize = 0;
    var imgs: std.ArrayList(PlacedImage) = .empty;
    var gfx: std.ArrayList(FillSample) = .empty;
    var strokes: usize = 0;

    while (std.mem.findScalarPos(u8, txml, tpos, '<')) |lt| {
        const gt = std.mem.findScalarPos(u8, txml, lt + 1, '>') orelse break;
        const tag = txml[lt + 1 .. gt];
        tpos = gt + 1;

        if (std.mem.startsWith(u8, tag, "page ")) {
            tpage_idx = if (extractAttr(tag, "number")) |v| std.fmt.parseInt(usize, v, 10) catch (tpage_idx + 1) else (tpage_idx + 1);
            tpage_body_start = tpos;
            imgs = .empty;
            gfx = .empty;
            strokes = 0;
        } else if (std.mem.eql(u8, tag, "/page")) {
            if (tpage_idx >= 1 and tpage_idx <= pages.items.len) {
                const p_ref = &pages.items[tpage_idx - 1];
                p_ref.images = try imgs.toOwnedSlice(alloc);
                p_ref.graphics = try gfx.toOwnedSlice(alloc);
                p_ref.stroke_count = strokes;
                const pbody = txml[tpage_body_start..lt];
                p_ref.trace_clipped_chars = try countTraceClippedAlnum(alloc, pbody, p_ref.width, p_ref.height);
                p_ref.tounicode_anomalies = try collectTraceToUnicodeAnomalies(alloc, pbody, p_ref.page_num);
            }
        } else if (std.mem.startsWith(u8, tag, "fill_image ") or
            std.mem.startsWith(u8, tag, "fill_image_mask ") or
            std.mem.startsWith(u8, tag, "clip_image_mask "))
        {
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
            if (!std.math.isFinite(pw) or !std.math.isFinite(ph) or pw > 1.0e8 or ph > 1.0e8) {
                return error.InvalidImageTransform;
            }
            // Audit all visibly placed rasters & masks (>= 8x8 pt placed) including stretched sub-8px tiles
            if (nw >= 1 and nh >= 1 and pw >= 8.0 and ph >= 8.0) {
                const ix0 = @min(@min(tf[4], tf[4] + tf[0]), @min(tf[4] + tf[2], tf[4] + tf[0] + tf[2]));
                const ix1 = @max(@max(tf[4], tf[4] + tf[0]), @max(tf[4] + tf[2], tf[4] + tf[0] + tf[2]));
                const iy0 = @min(@min(tf[5], tf[5] + tf[1]), @min(tf[5] + tf[3], tf[5] + tf[1] + tf[3]));
                const iy1 = @max(@max(tf[5], tf[5] + tf[1]), @max(tf[5] + tf[3], tf[5] + tf[1] + tf[3]));
                const pw_x10 = try checkedRoundInt(i64, pw * 10.0, 1.0, 1.0e12);
                const ph_x10 = try checkedRoundInt(i64, ph * 10.0, 1.0, 1.0e12);
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
                if (n == 3 and std.math.isFinite(comps[0]) and std.math.isFinite(comps[1]) and std.math.isFinite(comps[2]) and (std.mem.find(u8, cs, "RGB") != null or cs.len == 0)) {
                    try gfx.append(alloc, .{
                        .rgb = .{
                            .r = @intFromFloat(@round(std.math.clamp(comps[0], 0.0, 1.0) * 255.0)),
                            .g = @intFromFloat(@round(std.math.clamp(comps[1], 0.0, 1.0) * 255.0)),
                            .b = @intFromFloat(@round(std.math.clamp(comps[2], 0.0, 1.0) * 255.0)),
                        },
                        .is_stroke = is_st,
                        .linewidth = lw,
                    });
                } else if (n == 1 and std.math.isFinite(comps[0])) {
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

fn isNonContentStream(raw: []const u8, st_idx: usize, body: []const u8) bool {
    const win_start = if (st_idx > 600) st_idx - 600 else 0;
    const win = raw[win_start..st_idx];
    const hdr = if (std.mem.findLast(u8, win, "<<")) |ds| win[ds..] else win;
    const dict_non_content =
        std.mem.find(u8, hdr, "/Subtype /Image") != null or
        std.mem.find(u8, hdr, "/Subtype/Image") != null or
        std.mem.find(u8, hdr, "/FontFile") != null or
        std.mem.find(u8, hdr, "/Length1") != null or
        std.mem.find(u8, hdr, "/Subtype /CIDFontType0C") != null or
        std.mem.find(u8, hdr, "/Subtype/CIDFontType0C") != null or
        std.mem.find(u8, hdr, "/Subtype /Type1C") != null or
        std.mem.find(u8, hdr, "/Subtype/Type1C") != null or
        std.mem.find(u8, hdr, "/Subtype /OpenType") != null or
        std.mem.find(u8, hdr, "/Subtype/OpenType") != null or
        std.mem.find(u8, hdr, "/Filter /DCTDecode") != null or
        std.mem.find(u8, hdr, "/Filter/DCTDecode") != null or
        std.mem.find(u8, hdr, "/Filter /JPXDecode") != null or
        std.mem.find(u8, hdr, "/Filter /JBIG2Decode") != null or
        std.mem.find(u8, hdr, "/Subtype /XML") != null or
        std.mem.find(u8, hdr, "/Subtype/XML") != null or
        std.mem.find(u8, hdr, "/Type /Metadata") != null or
        std.mem.find(u8, hdr, "/Type/Metadata") != null or
        std.mem.find(u8, hdr, "/Type /ObjStm") != null or
        std.mem.find(u8, hdr, "/Type /XRef") != null or
        std.mem.find(u8, hdr, "/N 1") != null or
        std.mem.find(u8, hdr, "/N 3") != null or
        std.mem.find(u8, hdr, "/N 4") != null;
    if (dict_non_content) return true;
    // Also detect embedded TTF/OTF/CFF/ICC/ToUnicode CMap binaries directly by magic bytes
    if (body.len >= 4) {
        const b4 = body[0..4];
        if (std.mem.eql(u8, b4, &[_]u8{ 0x00, 0x01, 0x00, 0x00 }) or
            std.mem.eql(u8, b4, "OTTO") or
            std.mem.eql(u8, b4, "true") or
            std.mem.eql(u8, b4, "ttcf") or
            (body[0] == 0x01 and body[1] == 0x00 and body[2] == 0x04))
        {
            return true;
        }
    }
    const head_scan = body[0..@min(body.len, 256)];
    if (std.mem.find(u8, head_scan, "begincmap") != null or std.mem.find(u8, head_scan, "<?xpacket") != null) return true;
    return false;
}

fn blankRangeKeepNewlines(buf: []u8, start: usize, end: usize) void {
    var k = start;
    while (k < end and k < buf.len) : (k += 1) {
        if (buf[k] != '\n') buf[k] = ' ';
    }
}

fn isGraphicsOrMarkedOp(tok: []const u8) bool {
    const ops = [_][]const u8{
        "rg",  "RG",  "g",   "G",  "k",  "K", "gs", "sc", "SC", "scn", "SCN", "cs", "CS", "q", "Q", "cm", "w", "J", "j", "M", "d", "ri", "i",
        "BDC", "BMC", "EMC", "MP", "DP",
    };
    for (ops) |op| {
        if (std.mem.eql(u8, tok, op)) return true;
    }
    return false;
}

fn isTextOp(tok: []const u8) bool {
    const ops = [_][]const u8{
        "BT", "ET", "Tf", "Td", "TD", "Tm", "T*", "Tc", "Tw", "Tz", "TL", "Tr", "Ts", "Tj", "TJ", "'", "\"",
    };
    for (ops) |op| {
        if (std.mem.eql(u8, tok, op)) return true;
    }
    return false;
}

fn isPdfStreamDelim(ch: u8) bool {
    return ch == ' ' or ch == '\t' or ch == '\r' or ch == '\n' or ch == 0 or ch == 12 or
        ch == '(' or ch == ')' or ch == '<' or ch == '>' or ch == '[' or ch == ']' or
        ch == '{' or ch == '}' or ch == '/' or ch == '%';
}

const TokSpan = struct { start: usize, end: usize };

/// Lexer-accurate PDF BT...ET text blanker: properly skips literal strings `(...)` (including nested parens
/// and `\` escapes), hex strings `<...>`, and `%...` comments so `(SMITH ET AL. 2024)` never corrupts streams,
/// while preserving legal graphics-state color/alpha operators (`rg`, `RG`, `g`, `k`, `gs`, `sc`, `scn`, `cs`)
/// inside `BT...ET` so subsequent background fills keep exact PDF color state.
fn blankBtEtInPlace(buf: []u8) void {
    var i: usize = 0;
    var in_bt = false;
    var pending: [64]TokSpan = undefined;
    var pending_len: usize = 0;

    while (i < buf.len) {
        const ch = buf[i];
        if (ch == ' ' or ch == '\t' or ch == '\r' or ch == '\n' or ch == 0 or ch == 12) {
            i += 1;
            continue;
        }
        if (ch == '%') {
            while (i < buf.len and buf[i] != '\n' and buf[i] != '\r') : (i += 1) {}
            continue;
        }
        // Literal string (...)
        if (ch == '(') {
            const start = i;
            i += 1;
            var depth: usize = 1;
            while (i < buf.len and depth > 0) : (i += 1) {
                if (buf[i] == '\\' and i + 1 < buf.len) {
                    i += 1;
                } else if (buf[i] == '(') {
                    depth += 1;
                } else if (buf[i] == ')') {
                    depth -= 1;
                }
            }
            if (in_bt and pending_len < pending.len) {
                pending[pending_len] = .{ .start = start, .end = i };
                pending_len += 1;
            }
            continue;
        }
        // Dictionary <<...>> or hex string <...>
        if (ch == '<') {
            const start = i;
            if (i + 1 < buf.len and buf[i + 1] == '<') {
                i += 2;
                var ddepth: usize = 1;
                while (i < buf.len and ddepth > 0) {
                    if (buf[i] == '(') {
                        i += 1;
                        var pdepth: usize = 1;
                        while (i < buf.len and pdepth > 0) : (i += 1) {
                            if (buf[i] == '\\' and i + 1 < buf.len) {
                                i += 1;
                            } else if (buf[i] == '(') {
                                pdepth += 1;
                            } else if (buf[i] == ')') {
                                pdepth -= 1;
                            }
                        }
                        continue;
                    }
                    if (i + 1 < buf.len and buf[i] == '<' and buf[i + 1] == '<') {
                        ddepth += 1;
                        i += 2;
                    } else if (i + 1 < buf.len and buf[i] == '>' and buf[i + 1] == '>') {
                        ddepth -= 1;
                        i += 2;
                    } else {
                        i += 1;
                    }
                }
            } else {
                i += 1;
                while (i < buf.len and buf[i] != '>') : (i += 1) {}
                if (i < buf.len) i += 1;
            }
            if (in_bt and pending_len < pending.len) {
                pending[pending_len] = .{ .start = start, .end = i };
                pending_len += 1;
            }
            continue;
        }
        // Array [...]
        if (ch == '[') {
            const start = i;
            i += 1;
            var adepth: usize = 1;
            while (i < buf.len and adepth > 0) {
                if (buf[i] == '(') {
                    i += 1;
                    var pdepth: usize = 1;
                    while (i < buf.len and pdepth > 0) : (i += 1) {
                        if (buf[i] == '\\' and i + 1 < buf.len) {
                            i += 1;
                        } else if (buf[i] == '(') {
                            pdepth += 1;
                        } else if (buf[i] == ')') {
                            pdepth -= 1;
                        }
                    }
                    continue;
                }
                if (buf[i] == '[') {
                    adepth += 1;
                } else if (buf[i] == ']') {
                    adepth -= 1;
                }
                i += 1;
            }
            if (in_bt and pending_len < pending.len) {
                pending[pending_len] = .{ .start = start, .end = i };
                pending_len += 1;
            }
            continue;
        }
        // Name /Foo
        if (ch == '/') {
            const start = i;
            i += 1;
            while (i < buf.len and !isPdfStreamDelim(buf[i])) : (i += 1) {}
            if (in_bt and pending_len < pending.len) {
                pending[pending_len] = .{ .start = start, .end = i };
                pending_len += 1;
            }
            continue;
        }
        // Regular token (number or operator)
        if (!isPdfStreamDelim(ch)) {
            const start = i;
            while (i < buf.len and !isPdfStreamDelim(buf[i])) : (i += 1) {}
            const tok = buf[start..i];
            if (!in_bt) {
                if (std.mem.eql(u8, tok, "BT")) {
                    in_bt = true;
                    pending_len = 0;
                    blankRangeKeepNewlines(buf, start, i);
                }
            } else {
                if (std.mem.eql(u8, tok, "ET")) {
                    for (pending[0..pending_len]) |sp| blankRangeKeepNewlines(buf, sp.start, sp.end);
                    blankRangeKeepNewlines(buf, start, i);
                    pending_len = 0;
                    in_bt = false;
                } else if (isGraphicsOrMarkedOp(tok)) {
                    // Keep graphics-state & PDF/UA-1 marked-content operators and their operands intact!
                    pending_len = 0;
                } else if (isTextOp(tok)) {
                    for (pending[0..pending_len]) |sp| blankRangeKeepNewlines(buf, sp.start, sp.end);
                    blankRangeKeepNewlines(buf, start, i);
                    pending_len = 0;
                } else {
                    if (pending_len < pending.len) {
                        pending[pending_len] = .{ .start = start, .end = i };
                        pending_len += 1;
                    } else {
                        blankRangeKeepNewlines(buf, pending[0].start, pending[0].end);
                        std.mem.copyForwards(TokSpan, pending[0 .. pending.len - 1], pending[1..]);
                        pending[pending.len - 1] = .{ .start = start, .end = i };
                    }
                }
            }
            continue;
        }
        i += 1;
    }
}

/// Pure-Zig ISO 32000 delimiter-safe BT...ET text-block stripper (handles Typst `BT/Span` tagged streams
/// while skipping binary Image/Font/Metadata/ICC/CMap streams so photo-heavy & TTF-embedded PDFs stay 100% intact).
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
        const body_slice = out[body_start..body_end];
        if (!isNonContentStream(out, st_idx, body_slice)) {
            blankBtEtInPlace(body_slice);
        }
        pos = body_end + 9;
    }
    return out;
}

/// Build a temporary text-free PDF (decompressed via `mutool clean -d`, BT...ET blanked in-place in Zig)
/// so subsequent `renderPagePpm` calls return true text-free backgrounds for WCAG & texture audits.
pub fn makeBackgroundOnlyPdf(alloc: std.mem.Allocator, io: std.Io, pdf_path: []const u8, tmp_tag: []const u8) ![]const u8 {
    const clean_path = try tmpPath(alloc, tmp_tag, "clean.pdf");
    const bg_path = try tmpPath(alloc, tmp_tag, "bg.pdf");
    defer removeTmpBestEffort(io, clean_path);

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
        if (isNonContentStream(out, st_idx, out[body_start..body_end])) {
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
            if (ch == '%') {
                while (i < body_end and out[i] != '\n' and out[i] != '\r') : (i += 1) {}
                continue;
            }
            if (ch == 'W') {
                const prev_ok = (i == body_start) or isWs(out[i - 1]);
                if (!prev_ok) continue;
                var op_len: usize = 1;
                if (i + 1 < body_end and out[i + 1] == '*') op_len = 2;
                const after = i + op_len;
                if (after >= body_end or (!isWs(out[after]) and out[after] != '%')) continue;
                // Check next non-whitespace/non-comment operator is a path terminator/painter (`n`, `f`, `F`, `S`, `s`, `B`, `b`)
                var k = after;
                while (k < body_end) {
                    if (isWs(out[k])) {
                        k += 1;
                    } else if (out[k] == '%') {
                        while (k < body_end and out[k] != '\n' and out[k] != '\r') : (k += 1) {}
                    } else break;
                }
                if (k < body_end) {
                    const nxt = out[k];
                    const is_path_op = (nxt == 'n' or nxt == 'f' or nxt == 'F' or nxt == 'S' or nxt == 's' or nxt == 'B' or nxt == 'b');
                    const nxt_after = k + 1;
                    const nxt_delim = (nxt_after >= body_end) or isWs(out[nxt_after]) or out[nxt_after] == '*' or out[nxt_after] == '%';
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
    const clean_path = try tmpPath(alloc, tmp_tag, "clipclean.pdf");
    const out_path = try tmpPath(alloc, tmp_tag, "unclipped.pdf");
    defer removeTmpBestEffort(io, clean_path);

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
            } else |err| switch (err) {
                error.InvalidCharacter, error.Overflow => {},
            }
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
    const clean_path = try tmpPath(alloc, tmp_tag, "covclean.pdf");
    const raw_a = try tmpPath(alloc, tmp_tag, "cova_raw.pdf");
    const raw_b = try tmpPath(alloc, tmp_tag, "covb_raw.pdf");
    const out_a = try tmpPath(alloc, tmp_tag, "cova.pdf");
    const out_b = try tmpPath(alloc, tmp_tag, "covb.pdf");
    defer removeTmpBestEffort(io, clean_path);

    // Normalize PDF structure (decompress object streams so /Image dicts are plaintext, keeping JPEG streams compact)
    const cl = try runCmd(alloc, io, &.{ "mutool", "clean", pdf_path, clean_path }, null);
    if (cl.exit_code != 0) return error.MutoolCleanFailed;
    const base_bytes = try std.Io.Dir.cwd().readFileAlloc(io, clean_path, alloc, .unlimited);

    const ka = try rewriteImagesToSolidKey(alloc, base_bytes, .{ .r = 255, .g = 0, .b = 255 });
    const kb = try rewriteImagesToSolidKey(alloc, base_bytes, .{ .r = 0, .g = 255, .b = 0 });

    if (ka.needs_xref_repair) {
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = raw_a, .data = ka.bytes });
        defer removeTmpBestEffort(io, raw_a);
        _ = try runCmd(alloc, io, &.{ "mutool", "clean", raw_a, out_a }, null);
    } else {
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = out_a, .data = ka.bytes });
    }
    if (kb.needs_xref_repair) {
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = raw_b, .data = kb.bytes });
        defer removeTmpBestEffort(io, raw_b);
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
    const fname = try std.fmt.allocPrint(alloc, "p{d}.ppm", .{page_num});
    const ppm_path = try tmpPath(alloc, tmp_tag, fname);
    defer removeTmpBestEffort(io, ppm_path);
    const dpi_s = try std.fmt.allocPrint(alloc, "{d}", .{dpi});
    const pg_s = try std.fmt.allocPrint(alloc, "{d}", .{page_num});
    const res = try runCmd(alloc, io, &.{ "mutool", "draw", "-F", "ppm", "-r", dpi_s, "-o", ppm_path, pdf_path, pg_s }, null);
    if (res.exit_code != 0) return error.MutoolDrawPpmFailed;
    const raw = try std.Io.Dir.cwd().readFileAlloc(io, ppm_path, alloc, .unlimited);
    return parsePpm(raw);
}

/// Parse binary Netpbm PAM (`P7`, `DEPTH 4`, `MAXVAL 255`) bytes emitted by `mutool draw -c cmyk -F pam`.
pub fn parsePamCmyk(data: []const u8) !PamCmykImage {
    if (data.len < 16 or !std.mem.startsWith(u8, data, "P7\n")) return error.InvalidPam;
    const endhdr = std.mem.find(u8, data, "ENDHDR\n") orelse return error.InvalidPam;
    const hdr = data[0..endhdr];
    var w: usize = 0;
    var h: usize = 0;
    var depth: usize = 0;
    var it = std.mem.splitScalar(u8, hdr, '\n');
    while (it.next()) |ln| {
        if (std.mem.startsWith(u8, ln, "WIDTH ")) {
            w = std.fmt.parseInt(usize, std.mem.trim(u8, ln[6..], " \t\r"), 10) catch return error.InvalidPam;
        } else if (std.mem.startsWith(u8, ln, "HEIGHT ")) {
            h = std.fmt.parseInt(usize, std.mem.trim(u8, ln[7..], " \t\r"), 10) catch return error.InvalidPam;
        } else if (std.mem.startsWith(u8, ln, "DEPTH ")) {
            depth = std.fmt.parseInt(usize, std.mem.trim(u8, ln[6..], " \t\r"), 10) catch return error.InvalidPam;
        }
    }
    if (w == 0 or h == 0 or depth != 4) return error.InvalidPam;
    const body_start = endhdr + "ENDHDR\n".len;
    const need = w * h * 4;
    if (body_start + need > data.len) return error.TruncatedPam;
    return .{ .width = w, .height = h, .pixels = data[body_start .. body_start + need] };
}

pub fn renderPageCmykPam(alloc: std.mem.Allocator, io: std.Io, pdf_path: []const u8, page_num: usize, dpi: u32, tmp_tag: []const u8) !PamCmykImage {
    const fname = try std.fmt.allocPrint(alloc, "p{d}_cmyk.pam", .{page_num});
    const pam_path = try tmpPath(alloc, tmp_tag, fname);
    defer removeTmpBestEffort(io, pam_path);
    const dpi_s = try std.fmt.allocPrint(alloc, "{d}", .{dpi});
    const pg_s = try std.fmt.allocPrint(alloc, "{d}", .{page_num});
    const res = try runCmd(alloc, io, &.{ "mutool", "draw", "-c", "cmyk", "-F", "pam", "-r", dpi_s, "-o", pam_path, pdf_path, pg_s }, null);
    if (res.exit_code != 0) return error.MutoolDrawPamFailed;
    const raw = try std.Io.Dir.cwd().readFileAlloc(io, pam_path, alloc, .unlimited);
    return parsePamCmyk(raw);
}

fn normalizeBox(b: [4]f64) [4]f64 {
    return .{ @min(b[0], b[2]), @min(b[1], b[3]), @max(b[0], b[2]), @max(b[1], b[3]) };
}

fn parseDirectOrIndirectBox(alloc: std.mem.Allocator, io: std.Io, pdf_path: []const u8, obj_txt: []const u8, key: []const u8) ?[4]f64 {
    var search_pos: usize = 0;
    while (std.mem.findPos(u8, obj_txt, search_pos, key)) |kpos| {
        const after = kpos + key.len;
        if (after < obj_txt.len and isPdfIdentChar(obj_txt[after]) and obj_txt[after] != '/') {
            search_pos = after;
            continue;
        }
        var k = after;
        while (k < obj_txt.len and isWs(obj_txt[k])) : (k += 1) {}
        if (k >= obj_txt.len) return null;
        if (obj_txt[k] == '[') {
            const rbr = std.mem.findScalarPos(u8, obj_txt, k + 1, ']') orelse return null;
            var nums: [4]f64 = .{ 0, 0, 0, 0 };
            if (parseFloatSlice(obj_txt[k + 1 .. rbr], &nums) == 4) return normalizeBox(nums);
            return null;
        }
        if (obj_txt[k] >= '0' and obj_txt[k] <= '9') {
            var it = std.mem.tokenizeAny(u8, obj_txt[k..], " \t\r\n");
            const id_tok = it.next() orelse return null;
            _ = it.next() orelse return null; // gen
            const r_tok = it.next() orelse return null;
            if (std.mem.eql(u8, r_tok, "R")) {
                const res = runCmd(alloc, io, &.{ "mutool", "show", pdf_path, id_tok }, null) catch return null;
                if (res.exit_code != 0) return null;
                const lbr = std.mem.findScalar(u8, res.stdout, '[') orelse return null;
                const rbr = std.mem.findScalarPos(u8, res.stdout, lbr + 1, ']') orelse return null;
                var nums: [4]f64 = .{ 0, 0, 0, 0 };
                if (parseFloatSlice(res.stdout[lbr + 1 .. rbr], &nums) == 4) return normalizeBox(nums);
            }
            return null;
        }
        search_pos = after;
    }
    return null;
}

/// Decode a PDF `/URI (...)` literal string or `/URI <hex>` string inside an annotation or action dictionary.
pub fn parsePdfUriField(alloc: std.mem.Allocator, dict: []const u8) !?[]u8 {
    var search_pos: usize = 0;
    while (std.mem.findPos(u8, dict, search_pos, "/URI")) |upos| {
        const after_key = upos + 4;
        if (after_key < dict.len and isPdfIdentChar(dict[after_key]) and dict[after_key] != '/') {
            search_pos = after_key;
            continue;
        }
        var k = after_key;
        while (k < dict.len and isWs(dict[k])) : (k += 1) {}
        if (k >= dict.len) return null;
        if (dict[k] == '(') {
            k += 1;
            var depth: usize = 1;
            var out: std.ArrayList(u8) = .empty;
            while (k < dict.len and depth > 0) : (k += 1) {
                const ch = dict[k];
                if (ch == '\\' and k + 1 < dict.len) {
                    k += 1;
                    const esc = dict[k];
                    switch (esc) {
                        'n' => try out.append(alloc, '\n'),
                        'r' => try out.append(alloc, '\r'),
                        't' => try out.append(alloc, '\t'),
                        '\r', '\n' => {},
                        else => try out.append(alloc, esc),
                    }
                } else if (ch == '(') {
                    depth += 1;
                    try out.append(alloc, '(');
                } else if (ch == ')') {
                    depth -= 1;
                    if (depth > 0) try out.append(alloc, ')');
                } else {
                    try out.append(alloc, ch);
                }
            }
            return try out.toOwnedSlice(alloc);
        } else if (dict[k] == '<' and (k + 1 >= dict.len or dict[k + 1] != '<')) {
            k += 1;
            const hend = std.mem.findScalarPos(u8, dict, k, '>') orelse return null;
            var out: std.ArrayList(u8) = .empty;
            var hi: ?u8 = null;
            for (dict[k..hend]) |ch| {
                const nib: u8 = if (ch >= '0' and ch <= '9')
                    ch - '0'
                else if (ch >= 'a' and ch <= 'f')
                    ch - 'a' + 10
                else if (ch >= 'A' and ch <= 'F')
                    ch - 'A' + 10
                else
                    continue;
                if (hi) |h| {
                    try out.append(alloc, (h << 4) | nib);
                    hi = null;
                } else {
                    hi = nib;
                }
            }
            return try out.toOwnedSlice(alloc);
        }
        search_pos = after_key;
    }
    return null;
}

fn parseIndirectActionObj(dict: []const u8) ?[]const u8 {
    var pos: usize = 0;
    while (std.mem.findPos(u8, dict, pos, "/A")) |apos| {
        const after = apos + 2;
        if (after >= dict.len or !isWs(dict[after])) {
            pos = after;
            continue;
        }
        const rest = std.mem.trimStart(u8, dict[after..], " \t\r\n");
        if (rest.len > 0 and rest[0] >= '0' and rest[0] <= '9') {
            var it = std.mem.tokenizeAny(u8, rest, " \t\r\n");
            const id_tok = it.next() orelse return null;
            _ = it.next() orelse return null; // gen
            const r_tok = it.next() orelse return null;
            if (std.mem.eql(u8, r_tok, "R")) return id_tok;
        }
        pos = after;
    }
    return null;
}

const MUPDF_LINKS_JS =
    \\var doc = Document.openDocument(scriptArgs[0]);
    \\var pdf = doc.isPDF() ? doc.asPDF() : null;
    \\var n = doc.countPages();
    \\for (var p = 0; p < n; p++) {
    \\  var page = doc.loadPage(p);
    \\  var links = page.getLinks();
    \\  var hiddenMap = {};
    \\  if (pdf) {
    \\    var pobj = pdf.findPage(p);
    \\    var annots = pobj.get("Annots");
    \\    if (annots && annots.isArray()) {
    \\      for (var ai = 0; ai < annots.length; ai++) {
    \\        var an = annots.get(ai).resolve();
    \\        if (!an || !an.isDictionary()) continue;
    \\        var st = an.get("Subtype");
    \\        if (!st || st.asName() != "Link") continue;
    \\        var f = an.get("F");
    \\        var fval = f ? f.valueOf() : 0;
    \\        var isHid = ((fval & 2) != 0) ? 1 : 0;
    \\        var act = an.get("A");
    \\        if (act) act = act.resolve();
    \\        if (act && act.isDictionary()) {
    \\          var uobj = act.get("URI");
    \\          if (uobj) uobj = uobj.resolve();
    \\          if (uobj && uobj.isString() && isHid) hiddenMap[uobj.asString()] = true;
    \\        }
    \\        var aa = an.get("AA");
    \\        if (aa) aa = aa.resolve();
    \\        if (aa && aa.isDictionary()) {
    \\          var rb = an.get("Rect");
    \\          var rx0 = 0, ry0 = 0, rx1 = 0, ry1 = 0;
    \\          if (rb && rb.isArray() && rb.length >= 4) {
    \\            rx0 = rb.get(0).valueOf(); ry0 = rb.get(1).valueOf();
    \\            rx1 = rb.get(2).valueOf(); ry1 = rb.get(3).valueOf();
    \\          }
    \\          aa.forEach(function(k, v) {
    \\            v = v.resolve();
    \\            if (v && v.isDictionary()) {
    \\              var u2 = v.get("URI");
    \\              if (u2) u2 = u2.resolve();
    \\              if (u2 && u2.isString() && u2.asString().length > 0) {
    \\                print("LINK\t" + (p+1) + "\t" + rx0 + "\t" + ry0 + "\t" + rx1 + "\t" + ry1 + "\t" + isHid + "\t1\t" + u2.asString().replace(/[\r\n\t]/g, " "));
    \\              }
    \\            }
    \\          });
    \\        }
    \\      }
    \\    }
    \\  }
    \\  for (var i = 0; i < links.length; i++) {
    \\    var lk = links[i];
    \\    var uri = lk.getURI();
    \\    if (!uri || uri.length === 0 || uri.charAt(0) === '#') continue;
    \\    var b = lk.getBounds();
    \\    var hid = hiddenMap[uri] ? 1 : 0;
    \\    print("LINK\t" + (p+1) + "\t" + b[0] + "\t" + b[1] + "\t" + b[2] + "\t" + b[3] + "\t" + hid + "\t0\t" + uri.replace(/[\r\n\t]/g, " "));
    \\  }
    \\}
    \\
;

/// Extract all resolved external `/Subtype /Link` annotations via libmupdf (`mutool run` `page.getLinks()` + `/F` Hidden & `/AA` audit),
/// eliminating raw-text decoy `/URI`, indirect `/URI`, inline `/Annots`, and indirect zero-`/Rect` parser differentials.
pub fn extractPageLinks(alloc: std.mem.Allocator, io: std.Io, pdf_path: []const u8) ![]PageLink {
    const js_path = try tmpPath(alloc, "links", "extract_links.js");
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = js_path, .data = MUPDF_LINKS_JS });
    defer removeTmpBestEffort(io, js_path);

    const res = try runCmd(alloc, io, &.{ "mutool", "run", js_path, pdf_path }, null);
    if (res.exit_code != 0) return error.MutoolRunLinksFailed;

    var out: std.ArrayList(PageLink) = .empty;
    var ln_it = std.mem.splitScalar(u8, res.stdout, '\n');
    while (ln_it.next()) |raw_ln| {
        const ln = std.mem.trimEnd(u8, raw_ln, "\r");
        if (!std.mem.startsWith(u8, ln, "LINK\t")) continue;
        var f_it = std.mem.splitScalar(u8, ln["LINK\t".len..], '\t');
        const pg_s = f_it.next() orelse continue;
        const x0_s = f_it.next() orelse continue;
        const y0_s = f_it.next() orelse continue;
        const x1_s = f_it.next() orelse continue;
        const y1_s = f_it.next() orelse continue;
        const hid_s = f_it.next() orelse continue;
        const aa_s = f_it.next() orelse continue;
        const uri_s = f_it.rest();
        if (uri_s.len == 0) continue;

        const pg = std.fmt.parseInt(usize, pg_s, 10) catch continue;
        const rx0 = std.fmt.parseFloat(f64, x0_s) catch 0.0;
        const ry0 = std.fmt.parseFloat(f64, y0_s) catch 0.0;
        const rx1 = std.fmt.parseFloat(f64, x1_s) catch 0.0;
        const ry1 = std.fmt.parseFloat(f64, y1_s) catch 0.0;
        try out.append(alloc, .{
            .page = pg,
            .uri = try alloc.dupe(u8, std.mem.trim(u8, uri_s, " \t\r\n")),
            .x0 = @min(rx0, rx1),
            .y0 = @min(ry0, ry1),
            .x1 = @max(rx0, rx1),
            .y1 = @max(ry0, ry1),
            .is_hidden = std.mem.eql(u8, hid_s, "1"),
            .is_extra_action = std.mem.eql(u8, aa_s, "1"),
        });
    }
    return out.toOwnedSlice(alloc);
}

fn findIndirectObjIdAfter(dict: []const u8, key: []const u8) ?[]const u8 {
    var pos: usize = 0;
    while (std.mem.findPos(u8, dict, pos, key)) |kpos| {
        const after = kpos + key.len;
        if (after < dict.len and isPdfIdentChar(dict[after]) and dict[after] != '/') {
            pos = after;
            continue;
        }
        const rest = std.mem.trimStart(u8, dict[after..], " \t\r\n");
        if (rest.len > 0 and rest[0] >= '0' and rest[0] <= '9') {
            var it = std.mem.tokenizeAny(u8, rest, " \t\r\n[]");
            const id_tok = it.next() orelse return null;
            _ = it.next() orelse return null;
            const r_tok = it.next() orelse return null;
            if (std.mem.eql(u8, r_tok, "R")) return id_tok;
        }
        pos = after;
    }
    return null;
}

fn fontDescriptorHasEmbeddedStream(alloc: std.mem.Allocator, io: std.Io, pdf_path: []const u8, font_dict: []const u8) bool {
    if (std.mem.find(u8, font_dict, "/FontFile") != null) return true;
    if (findIndirectObjIdAfter(font_dict, "/FontDescriptor")) |fd_id| {
        const fd_res = runCmd(alloc, io, &.{ "mutool", "show", pdf_path, fd_id }, null) catch return false;
        if (fd_res.exit_code == 0 and std.mem.find(u8, fd_res.stdout, "/FontFile") != null) return true;
    }
    return false;
}

fn isPdfFontObjectEmbedded(alloc: std.mem.Allocator, io: std.Io, pdf_path: []const u8, fobj_id: []const u8) bool {
    const fshow = runCmd(alloc, io, &.{ "mutool", "show", pdf_path, fobj_id }, null) catch return false;
    if (fshow.exit_code != 0) return false;
    const fdict = fshow.stdout;
    // Genuine Type3 font has `/Subtype /Type3` on the font dictionary itself (defeats `"Type3"` font-name substring)
    if (std.mem.find(u8, fdict, "/Subtype /Type3") != null or std.mem.find(u8, fdict, "/Subtype/Type3") != null) {
        return std.mem.find(u8, fdict, "/CharProcs") != null;
    }
    // Type0 composite font: MUST dereference `/DescendantFonts [ <cid_id> 0 R ]` -> `/FontDescriptor` -> `/FontFile*`
    if (std.mem.find(u8, fdict, "/Subtype /Type0") != null or std.mem.find(u8, fdict, "/Subtype/Type0") != null or
        std.mem.find(u8, fdict, "/DescendantFonts") != null)
    {
        if (std.mem.find(u8, fdict, "/DescendantFonts")) |dpos| {
            const after = std.mem.trimStart(u8, fdict[dpos + "/DescendantFonts".len ..], " \t\r\n[");
            var it = std.mem.tokenizeAny(u8, after, " \t\r\n[]");
            if (it.next()) |cid_id| {
                const cshow = runCmd(alloc, io, &.{ "mutool", "show", pdf_path, cid_id }, null) catch return false;
                if (cshow.exit_code == 0) {
                    // Handle indirect array `/DescendantFonts 12 0 R` -> `[ 13 0 R ]`
                    if (std.mem.find(u8, cshow.stdout, "/FontDescriptor") != null or std.mem.find(u8, cshow.stdout, "/FontFile") != null) {
                        return fontDescriptorHasEmbeddedStream(alloc, io, pdf_path, cshow.stdout);
                    }
                    const inner = std.mem.trimStart(u8, cshow.stdout, " \t\r\n[");
                    var it2 = std.mem.tokenizeAny(u8, inner, " \t\r\n[]");
                    if (it2.next()) |cid_id2| {
                        const c2 = runCmd(alloc, io, &.{ "mutool", "show", pdf_path, cid_id2 }, null) catch return false;
                        if (c2.exit_code == 0) return fontDescriptorHasEmbeddedStream(alloc, io, pdf_path, c2.stdout);
                    }
                }
            }
        }
        return false;
    }
    // Simple Type1 / TrueType / OpenType font: dereference `/FontDescriptor` -> `/FontFile*` (fixes BOTH fake `ABCDEF+` AND indirect `/FontDescriptor` false-FAIL!)
    return fontDescriptorHasEmbeddedStream(alloc, io, pdf_path, fdict);
}

fn hasNonEmptyPdfTitle(info_stdout: []const u8) bool {
    const tpos = std.mem.find(u8, info_stdout, "/Title") orelse return false;
    const rest = std.mem.trimStart(u8, info_stdout[tpos + 6 ..], " \t\r\n");
    if (rest.len == 0) return false;
    if (rest[0] == '(') {
        const rp = std.mem.findScalarPos(u8, rest, 1, ')') orelse return false;
        return std.mem.trim(u8, rest[1..rp], " \t\r\n").len > 0;
    }
    if (rest[0] == '<') {
        const rb = std.mem.findScalarPos(u8, rest, 1, '>') orelse return false;
        return std.mem.trim(u8, rest[1..rb], " \t\r\n").len > 0;
    }
    return false;
}

/// Inspect PDF Catalog, PDF/UA-1 structural tags, dereferenced font embedding, and normalized MediaBox/CropBox-clamped Trim/Bleed boxes.
fn parseMutoolFontName(ln: []const u8) ?[]const u8 {
    // mutool 1.23 prints single quotes ('Helvetica'), mutool 1.24+ prints double quotes ("Helvetica")
    if (std.mem.findScalar(u8, ln, '\'')) |q1| {
        if (std.mem.findScalarPos(u8, ln, q1 + 1, '\'')) |q2| return ln[q1 + 1 .. q2];
    }
    if (std.mem.findScalar(u8, ln, '"')) |q1| {
        if (std.mem.findScalarPos(u8, ln, q1 + 1, '"')) |q2| return ln[q1 + 1 .. q2];
    }
    return null;
}

pub fn inspectCatalog(alloc: std.mem.Allocator, io: std.Io, pdf_path: []const u8) !CatalogInfo {
    const root_res = try runCmd(alloc, io, &.{ "mutool", "show", pdf_path, "trailer/Root" }, null);
    const info_res = try runCmd(alloc, io, &.{ "mutool", "info", pdf_path }, null);
    const pages_res = try runCmd(alloc, io, &.{ "mutool", "show", pdf_path, "pages" }, null);

    const root = root_res.stdout;
    const marked = std.mem.find(u8, root, "/MarkInfo") != null and containsFold(root, "/Marked true");
    var has_struct = false;
    if (findIndirectObjIdAfter(root, "/StructTreeRoot")) |st_id| {
        const sres = runCmd(alloc, io, &.{ "mutool", "show", pdf_path, st_id }, null) catch null;
        if (sres) |sr| {
            if (sr.exit_code == 0 and std.mem.find(u8, sr.stdout, "/K") != null) has_struct = true;
        }
    } else if (std.mem.find(u8, root, "/StructTreeRoot")) |spos| {
        if (std.mem.find(u8, root[spos..], "/K") != null) has_struct = true;
    }
    const has_outlines = std.mem.find(u8, root, "/Outlines") != null;

    var has_lang = false;
    var lang_val: []const u8 = "";
    if (std.mem.find(u8, root, "/Lang")) |lpos| {
        if (std.mem.findScalarPos(u8, root, lpos + 5, '(')) |lp| {
            if (std.mem.findScalarPos(u8, root, lp + 1, ')')) |rp| {
                lang_val = try alloc.dupe(u8, std.mem.trim(u8, root[lp + 1 .. rp], " \t\r\n"));
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
    const has_title = xmp_has_title or hasNonEmptyPdfTitle(info_res.stdout);

    // Audit EVERY distinct font PDF object ID (keyed by object ID, NOT font name — defeats Bypass C, fake `ABCDEF+`, unembedded Type0, `"Type3"` substr, AND indirect `/FontDescriptor` false-FAIL!)
    var unemb: std.ArrayList([]const u8) = .empty;
    var emb: std.ArrayList([]const u8) = .empty;
    var seen_obj_ids = std.StringHashMap(void).init(alloc);
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
            if (parseMutoolFontName(ln)) |raw_fname| {
                const clean_name = stripSubsetPrefix(raw_fname);
                var fobj_id: ?[]const u8 = null;
                if (std.mem.findScalarLast(u8, ln, '(')) |op| {
                    const obj_tok = std.mem.trim(u8, ln[op + 1 ..], " R)\r");
                    var sp_it = std.mem.tokenizeScalar(u8, obj_tok, ' ');
                    fobj_id = sp_it.next();
                }
                const dedup_key = fobj_id orelse raw_fname;
                if (!seen_obj_ids.contains(dedup_key)) {
                    try seen_obj_ids.put(try alloc.dupe(u8, dedup_key), {});
                    const owned = try alloc.dupe(u8, clean_name);
                    const embedded_stream = if (fobj_id) |fid| isPdfFontObjectEmbedded(alloc, io, pdf_path, fid) else false;
                    if (embedded_stream) {
                        try emb.append(alloc, owned);
                    } else {
                        try unemb.append(alloc, owned);
                    }
                }
            }
        }
    }

    // Parse pages & normalized BleedBox intersected with MediaBox and CropBox
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
                const mb = parseDirectOrIndirectBox(alloc, io, pdf_path, pshow.stdout, "/MediaBox");
                const cb = parseDirectOrIndirectBox(alloc, io, pdf_path, pshow.stdout, "/CropBox");
                const tb = parseDirectOrIndirectBox(alloc, io, pdf_path, pshow.stdout, "/TrimBox");
                const bb = parseDirectOrIndirectBox(alloc, io, pdf_path, pshow.stdout, "/BleedBox");
                if (pg_count == 1) {
                    if (mb) |m| {
                        media_w = m[2] - m[0];
                        media_h = m[3] - m[1];
                    }
                }
                var margin: f64 = 0.0;
                if (tb) |t| {
                    // Effective physical bleed region cannot exceed MediaBox or CropBox (defeats ghost BleedBox & CropBox==TrimBox)
                    var eff: ?[4]f64 = bb orelse mb;
                    if (eff != null and mb != null) {
                        const e = eff.?;
                        const m = mb.?;
                        eff = .{ @max(e[0], m[0]), @max(e[1], m[1]), @min(e[2], m[2]), @min(e[3], m[3]) };
                    }
                    if (eff != null and cb != null) {
                        const e = eff.?;
                        const c = cb.?;
                        eff = .{ @max(e[0], c[0]), @max(e[1], c[1]), @min(e[2], c[2]), @min(e[3], c[3]) };
                    }
                    if (eff) |b| {
                        margin = @min(@min(t[0] - b[0], t[1] - b[1]), @min(b[2] - t[2], b[3] - t[3]));
                    }
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

test "countTraceClippedAlnum catches W/W* clipped glyphs independent of mutool stext" {
    const trace_xml =
        \\<clip_path winding="eofill" transform="1 0 0 -1 0 792">
        \\    <moveto x="50" y="680"/>
        \\    <lineto x="130" y="680"/>
        \\    <lineto x="130" y="710"/>
        \\    <lineto x="50" y="710"/>
        \\    <closepath/>
        \\</clip_path>
        \\<fill_text transform="1 0 0 -1 0 792">
        \\    <span font="Helvetica" trm="12 0 0 12">
        \\        <g unicode="T" x="54" y="690" adv="0.611"/>
        \\        <g unicode="b" x="137.34" y="690" adv="0.556"/>
        \\        <g unicode="a" x="144.01" y="690" adv="0.556"/>
        \\        <g unicode="r" x="150.68" y="690" adv="0.333"/>
        \\        <g unicode="k" x="154.68" y="690" adv="0.500"/>
        \\    </span>
        \\</fill_text>
        \\<pop_clip/>
        \\<fill_text transform="1 0 0 -1 0 792">
        \\    <span font="Helvetica" trm="12 0 0 12">
        \\        <g unicode="Z" x="200" y="690" adv="0.611"/>
        \\    </span>
        \\</fill_text>
    ;
    // "T" is inside [50, 130], "bark" (4 chars) are outside, "Z" is after pop_clip so unclipped
    try std.testing.expectEqual(@as(usize, 4), try countTraceClippedAlnum(std.testing.allocator, trace_xml, 612.0, 792.0));
}

test "countTraceClippedAlnum catches horizontal top-half glyph slicing while passing generous clips" {
    // Issue #2 Escape 3 (F_horizontal_half_slice): 12pt Helvetica at y=690 clipped to y in [680, 694]
    const half_sliced =
        \\<clip_path winding="eofill" transform="1 0 0 -1 0 792">
        \\    <moveto x="40" y="680"/>
        \\    <lineto x="440" y="680"/>
        \\    <lineto x="440" y="694"/>
        \\    <lineto x="40" y="694"/>
        \\    <closepath/>
        \\</clip_path>
        \\<fill_text transform="1 0 0 -1 0 792">
        \\    <span font="Helvetica" trm="12 0 0 12">
        \\        <g unicode="T" x="54" y="690" adv="0.611"/>
        \\        <g unicode="h" x="61.33" y="690" adv="0.556"/>
        \\        <g unicode="o" x="68.00" y="690" adv="0.556"/>
        \\    </span>
        \\</fill_text>
        \\<pop_clip/>
    ;
    try std.testing.expectEqual(@as(usize, 3), try countTraceClippedAlnum(std.testing.allocator, half_sliced, 612.0, 792.0));

    // Generous control (E_generous_clip_control): clip y in [670, 720] covers full cap-height + descenders
    const generous =
        \\<clip_path winding="eofill" transform="1 0 0 -1 0 792">
        \\    <moveto x="40" y="670"/>
        \\    <lineto x="440" y="670"/>
        \\    <lineto x="440" y="720"/>
        \\    <lineto x="40" y="720"/>
        \\    <closepath/>
        \\</clip_path>
        \\<fill_text transform="1 0 0 -1 0 792">
        \\    <span font="Helvetica" trm="12 0 0 12">
        \\        <g unicode="T" x="54" y="690" adv="0.611"/>
        \\        <g unicode="g" x="61.33" y="690" adv="0.556"/>
        \\    </span>
        \\</fill_text>
        \\<pop_clip/>
    ;
    try std.testing.expectEqual(@as(usize, 0), try countTraceClippedAlnum(std.testing.allocator, generous, 612.0, 792.0));
}

test "parseMutoolFontName handles both mutool 1.23 single quotes and 1.24+ double quotes" {
    try std.testing.expectEqualStrings("Helvetica", parseMutoolFontName("\t1\t(5 0 R):\tType1 'Helvetica' WinAnsiEncoding (5 0 R)").?);
    try std.testing.expectEqualStrings("ABCDEF+Inter", parseMutoolFontName("\t1\t(7 0 R):\tCIDFontType0 \"ABCDEF+Inter\" Identity-H (7 0 R)").?);
}
