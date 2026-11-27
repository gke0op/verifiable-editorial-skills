//! Pure-Zig 0.17.0 Media, Font Provisioning, Facing-Spread & Panoramic Plate Engine (`media.zig`).
//! Zero Python, zero C image libraries — compiles cleanly on macOS arm64, Linux x86_64 musl & aarch64 musl:
//!   - `vedit fetch-fonts` : SIL-OFL 8-font open-source stack downloader + SHA-256 manifest
//!   - `vedit spreads`     : Facing-spread contact-sheet composer (`[2|3]`, `[4|5]`) with spine shadow
//!   - `vedit plate`       : Fixed-slot panoramic crop, black-point alignment & raised-cosine edge feather
//!   - `encodePngRgb`      : Pure-Zig compressed PNG encoder (`std.compress.flate.Compress` zlib + Sub filter)
//!   - `encodeJpegRgb`     : Pure-Zig ITU-T T.81 Baseline 4:4:4 JPEG encoder (Annex K DCT + Huffman)

const std = @import("std");
const mupdf = @import("mupdf.zig");

pub const FontSpec = struct {
    file: []const u8,
    family: []const u8,
    url: []const u8,
    sha256: [64]u8,
};

pub const FONT_SPECS = [_]FontSpec{
    .{
        .file = "CormorantGaramond-Regular.ttf",
        .family = "Cormorant Garamond",
        .url = "https://raw.githubusercontent.com/google/fonts/main/ofl/cormorantgaramond/CormorantGaramond%5Bwght%5D.ttf",
        .sha256 = "b20b7d9626dd956b2c5e558692ad328b1f19e3275e2782db4fa07670d83f35e0".*,
    },
    .{
        .file = "CormorantGaramond-Italic.ttf",
        .family = "Cormorant Garamond",
        .url = "https://raw.githubusercontent.com/google/fonts/main/ofl/cormorantgaramond/CormorantGaramond-Italic%5Bwght%5D.ttf",
        .sha256 = "0f48ea6abb2084537854f7174c470991a463b13036309e3b50a81511611c530d".*,
    },
    .{
        .file = "SourceSerif4-Regular.ttf",
        .family = "Source Serif 4",
        .url = "https://raw.githubusercontent.com/google/fonts/main/ofl/sourceserif4/SourceSerif4%5Bopsz%2Cwght%5D.ttf",
        .sha256 = "97b2d4da6e3cb494b5a1e66ae176914d852ccabef49e0c02c0df25f3e39aca0b".*,
    },
    .{
        .file = "SourceSerif4-Italic.ttf",
        .family = "Source Serif 4",
        .url = "https://raw.githubusercontent.com/google/fonts/main/ofl/sourceserif4/SourceSerif4-Italic%5Bopsz%2Cwght%5D.ttf",
        .sha256 = "15fbc7e4679489a501998c3669272637a6646388ef7e4bd77eebb5bf967a1f42".*,
    },
    .{
        .file = "Inter-Variable.ttf",
        .family = "Inter",
        .url = "https://raw.githubusercontent.com/google/fonts/main/ofl/inter/Inter%5Bopsz%2Cwght%5D.ttf",
        .sha256 = "29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031".*,
    },
    .{
        .file = "Inter-Italic-Variable.ttf",
        .family = "Inter",
        .url = "https://raw.githubusercontent.com/google/fonts/main/ofl/inter/Inter-Italic%5Bopsz%2Cwght%5D.ttf",
        .sha256 = "acd98e64795781b2058f07b18475e0ecee2a0fe2b42a49e2f9e37d0d6bf66ce6".*,
    },
    .{
        .file = "IBMPlexMono-Regular.ttf",
        .family = "IBM Plex Mono",
        .url = "https://raw.githubusercontent.com/google/fonts/main/ofl/ibmplexmono/IBMPlexMono-Regular.ttf",
        .sha256 = "6a3412f058c7d8dfd9170c41e85ade48e5156ecb89356110ca57a0a27734af46".*,
    },
    .{
        .file = "IBMPlexMono-SemiBold.ttf",
        .family = "IBM Plex Mono",
        .url = "https://raw.githubusercontent.com/google/fonts/main/ofl/ibmplexmono/IBMPlexMono-SemiBold.ttf",
        .sha256 = "d3c38e55c78f5b0f28009fddba4834ec503278936a5986032424c9bd2d23aa46".*,
    },
};

pub const FontResult = struct {
    file: []const u8,
    family: []const u8,
    status: []const u8,
    bytes: usize,
    sha256_hex: [64]u8,
};

pub const FetchFontsReport = struct {
    font_dir: []const u8,
    fonts: []const FontResult,
};

pub const PlateResult = struct {
    input_w: usize,
    input_h: usize,
    out_w: usize,
    out_h: usize,
    out_bytes: usize,
    dpi_x: f64,
    dpi_y: f64,
    corner: mupdf.Rgb,
};

pub const SpreadsResult = struct {
    written: []const []const u8,
};

fn sha256Hex(data: []const u8) [64]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data, &digest, .{});
    return std.fmt.bytesToHex(digest, .lower);
}

pub fn parseHexRgb(raw: []const u8) ?mupdf.Rgb {
    const s = if (raw.len > 0 and raw[0] == '#') raw[1..] else raw;
    if (s.len != 6) return null;
    const r = std.fmt.parseInt(u8, s[0..2], 16) catch return null;
    const g = std.fmt.parseInt(u8, s[2..4], 16) catch return null;
    const b = std.fmt.parseInt(u8, s[4..6], 16) catch return null;
    return .{ .r = r, .g = g, .b = b };
}

// =============================================================================
// 1. PURE-ZIG SIL-OFL FONT FETCHER (`vedit fetch-fonts`)
// =============================================================================

fn ensureDir(io: std.Io, path: []const u8) !void {
    if (path.len == 0 or std.mem.eql(u8, path, ".") or std.mem.eql(u8, path, "/")) return;
    if (std.Io.Dir.cwd().openDir(io, path, .{})) |d| {
        var dir = d;
        dir.close(io);
        return;
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    }
    try std.Io.Dir.cwd().createDirPath(io, path);
}

pub fn isValidFontMagic(data: []const u8) bool {
    if (data.len < 12) return false;
    const h = data[0..4];
    return std.mem.eql(u8, h, &[_]u8{ 0x00, 0x01, 0x00, 0x00 }) or
        std.mem.eql(u8, h, "OTTO") or
        std.mem.eql(u8, h, "true") or
        std.mem.eql(u8, h, "ttcf");
}

pub fn fetchFonts(alloc: std.mem.Allocator, io: std.Io, target_dir: []const u8, force: bool) !FetchFontsReport {
    try ensureDir(io, target_dir);
    var results: std.ArrayList(FontResult) = .empty;

    for (FONT_SPECS) |spec| {
        const dest = try std.fs.path.join(alloc, &.{ target_dir, spec.file });
        if (!force) {
            if (std.Io.Dir.cwd().readFileAlloc(io, dest, alloc, .unlimited)) |existing| {
                const got_sha = sha256Hex(existing);
                if (existing.len > 10_000 and isValidFontMagic(existing) and std.mem.eql(u8, &got_sha, &spec.sha256)) {
                    try results.append(alloc, .{
                        .file = spec.file,
                        .family = spec.family,
                        .status = "cached",
                        .bytes = existing.len,
                        .sha256_hex = got_sha,
                    });
                    continue;
                }
            } else |err| switch (err) {
                error.FileNotFound => {},
                else => return err,
            }
        }

        const tmp_dest = try std.fmt.allocPrint(alloc, "{s}.{d}.tmp", .{ dest, std.c.getpid() });
        const res = try mupdf.runCmd(alloc, io, &.{
            "curl",
            "-fsSL",
            "--proto",
            "=https",
            "--proto-redir",
            "=https",
            "--max-time",
            "25",
            "-A",
            "verifiable-editorial-font-fetcher/0.7-zig (+https://github.com/gke0op/verifiable-editorial-skills)",
            "-o",
            tmp_dest,
            "--",
            spec.url,
        }, null);
        if (res.exit_code != 0) {
            mupdf.removeTmpBestEffort(io, tmp_dest);
            return error.FontDownloadFailed;
        }
        const data = try std.Io.Dir.cwd().readFileAlloc(io, tmp_dest, alloc, .unlimited);
        if (data.len < 10_000 or !isValidFontMagic(data)) {
            mupdf.removeTmpBestEffort(io, tmp_dest);
            return error.InvalidFontBinary;
        }
        const got_sha = sha256Hex(data);
        if (!std.mem.eql(u8, &got_sha, &spec.sha256)) {
            mupdf.removeTmpBestEffort(io, tmp_dest);
            return error.FontDigestMismatch;
        }
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = dest, .data = data });
        mupdf.removeTmpBestEffort(io, tmp_dest);

        try results.append(alloc, .{
            .file = spec.file,
            .family = spec.family,
            .status = "downloaded",
            .bytes = data.len,
            .sha256_hex = got_sha,
        });
    }

    // Write deterministic RFC 8259 escaped fonts_manifest.json
    var mf: std.ArrayList(u8) = .empty;
    try mf.appendSlice(alloc, "{\n  \"license\": \"SIL Open Font License 1.1\",\n  \"fonts\": [\n");
    for (results.items, 0..) |fr, idx| {
        const comma: []const u8 = if (idx + 1 < results.items.len) "," else "";
        const j_file = try mupdf.jsonString(alloc, fr.file);
        const j_fam = try mupdf.jsonString(alloc, fr.family);
        const j_st = try mupdf.jsonString(alloc, fr.status);
        try mf.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\    {{ "file": {s}, "family": {s}, "status": {s}, "bytes": {d}, "sha256": "{s}" }}{s}
            \\
        , .{ j_file, j_fam, j_st, fr.bytes, fr.sha256_hex[0..], comma }));
    }
    try mf.appendSlice(alloc, "  ]\n}\n");
    const mf_path = try std.fs.path.join(alloc, &.{ target_dir, "fonts_manifest.json" });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = mf_path, .data = mf.items });

    return .{
        .font_dir = target_dir,
        .fonts = try results.toOwnedSlice(alloc),
    };
}

// =============================================================================
// 2. PURE-ZIG PNG ENCODER (ZLIB DEFLATE + SUB SCANLINE FILTER)
// =============================================================================

fn writeBeU32(out: *std.ArrayList(u8), alloc: std.mem.Allocator, val: u32) !void {
    var b: [4]u8 = undefined;
    std.mem.writeInt(u32, &b, val, .big);
    try out.appendSlice(alloc, &b);
}

fn appendPngChunk(out: *std.ArrayList(u8), alloc: std.mem.Allocator, chunk_type: *const [4]u8, payload: []const u8) !void {
    try writeBeU32(out, alloc, @as(u32, @intCast(payload.len)));
    const crc_start = out.items.len;
    try out.appendSlice(alloc, chunk_type);
    try out.appendSlice(alloc, payload);
    const crc = std.hash.Crc32.hash(out.items[crc_start..]);
    try writeBeU32(out, alloc, crc);
}

pub fn encodePngRgb(alloc: std.mem.Allocator, width: usize, height: usize, pixels: []const u8) ![]u8 {
    if (pixels.len < width * height * 3) return error.InvalidPixelBuffer;

    // Build filtered scanlines using PNG Filter Type 1 (Sub) for clean compression
    const stride = width * 3;
    const raw_scan = try alloc.alloc(u8, height * (stride + 1));
    defer alloc.free(raw_scan);

    for (0..height) |y| {
        const dst_off = y * (stride + 1);
        const src_off = y * stride;
        raw_scan[dst_off] = 1; // Sub filter
        for (0..stride) |x| {
            const cur = pixels[src_off + x];
            const left: u8 = if (x >= 3) pixels[src_off + x - 3] else 0;
            raw_scan[dst_off + 1 + x] = cur -% left;
        }
    }

    // Compress scanlines into zlib stream via Zig 0.17 std.compress.flate.Compress
    var zlib_out: std.Io.Writer.Allocating = .init(alloc);
    defer zlib_out.deinit();
    try zlib_out.ensureUnusedCapacity(128);
    const win_buf = try alloc.alloc(u8, std.compress.flate.max_window_len);
    defer alloc.free(win_buf);

    var comp = try std.compress.flate.Compress.init(&zlib_out.writer, win_buf, .zlib, .{
        .good = 8,
        .nice = 128,
        .lazy = 16,
        .chain = 128,
    });
    try comp.writer.writeAll(raw_scan);
    try comp.finish();
    try zlib_out.writer.flush();

    var png: std.ArrayList(u8) = .empty;
    errdefer png.deinit(alloc);
    try png.appendSlice(alloc, &[_]u8{ 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A });

    var ihdr: [13]u8 = undefined;
    std.mem.writeInt(u32, ihdr[0..4], @as(u32, @intCast(width)), .big);
    std.mem.writeInt(u32, ihdr[4..8], @as(u32, @intCast(height)), .big);
    ihdr[8] = 8; // bit depth
    ihdr[9] = 2; // RGB
    ihdr[10] = 0; // deflate
    ihdr[11] = 0; // adaptive filter
    ihdr[12] = 0; // non-interlaced
    try appendPngChunk(&png, alloc, "IHDR", &ihdr);
    try appendPngChunk(&png, alloc, "IDAT", zlib_out.written());
    try appendPngChunk(&png, alloc, "IEND", &.{});

    return png.toOwnedSlice(alloc);
}

// =============================================================================
// 3. PURE-ZIG BASELINE 4:4:4 JPEG ENCODER (ITU-T T.81 ANNEX K)
// =============================================================================

const ZIGZAG = [64]u8{
    0,  1,  8,  16, 9,  2,  3,  10,
    17, 24, 32, 25, 18, 11, 4,  5,
    12, 19, 26, 33, 40, 48, 41, 34,
    27, 20, 13, 6,  7,  14, 21, 28,
    35, 42, 49, 56, 57, 50, 43, 36,
    29, 22, 15, 23, 30, 37, 44, 51,
    58, 59, 52, 45, 38, 31, 39, 46,
    53, 60, 61, 54, 47, 55, 62, 63,
};

const STD_LUMA_QUANT = [64]u8{
    16, 11, 10, 16, 24,  40,  51,  61,
    12, 12, 14, 19, 26,  58,  60,  55,
    14, 13, 16, 24, 40,  57,  69,  56,
    14, 17, 22, 29, 51,  87,  80,  62,
    18, 22, 37, 56, 68,  109, 103, 77,
    24, 35, 55, 64, 81,  104, 113, 92,
    49, 64, 78, 87, 103, 121, 120, 101,
    72, 92, 95, 98, 112, 100, 103, 99,
};

const STD_CHROMA_QUANT = [64]u8{
    17, 18, 24, 47, 99, 99, 99, 99,
    18, 21, 26, 66, 99, 99, 99, 99,
    24, 26, 56, 99, 99, 99, 99, 99,
    47, 66, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99,
};

const DC_LUMA_BITS = [16]u8{ 0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0 };
const DC_LUMA_VALS = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 };

const DC_CHROMA_BITS = [16]u8{ 0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0 };
const DC_CHROMA_VALS = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 };

const AC_LUMA_BITS = [16]u8{ 0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 125 };
const AC_LUMA_VALS = [_]u8{
    0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07,
    0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xA1, 0x08, 0x23, 0x42, 0xB1, 0xC1, 0x15, 0x52, 0xD1, 0xF0,
    0x24, 0x33, 0x62, 0x72, 0x82, 0x09, 0x0A, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x25, 0x26, 0x27, 0x28,
    0x29, 0x2A, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49,
    0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69,
    0x6A, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89,
    0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7,
    0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5,
    0xC6, 0xC7, 0xC8, 0xC9, 0xCA, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xE1, 0xE2,
    0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA, 0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8,
    0xF9, 0xFA,
};

const AC_CHROMA_BITS = [16]u8{ 0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 119 };
const AC_CHROMA_VALS = [_]u8{
    0x00, 0x01, 0x02, 0x03, 0x11, 0x04, 0x05, 0x21, 0x31, 0x06, 0x12, 0x41, 0x51, 0x07, 0x61, 0x71,
    0x13, 0x22, 0x32, 0x81, 0x08, 0x14, 0x42, 0x91, 0xA1, 0xB1, 0xC1, 0x09, 0x23, 0x33, 0x52, 0xF0,
    0x15, 0x62, 0x72, 0xD1, 0x0A, 0x16, 0x24, 0x34, 0xE1, 0x25, 0xF1, 0x17, 0x18, 0x19, 0x1A, 0x26,
    0x27, 0x28, 0x29, 0x2A, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48,
    0x49, 0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68,
    0x69, 0x6A, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87,
    0x88, 0x89, 0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3, 0xA4, 0xA5,
    0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3,
    0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9, 0xCA, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA,
    0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8,
    0xF9, 0xFA,
};

const HuffEntry = struct { code: u16, len: u8 };

fn buildHuffLut(bits: *const [16]u8, vals: []const u8) [256]HuffEntry {
    var lut: [256]HuffEntry = @splat(.{ .code = 0, .len = 0 });
    var code: u32 = 0;
    var vi: usize = 0;
    for (0..16) |bl| {
        const count = bits[bl];
        for (0..count) |_| {
            if (vi < vals.len) {
                lut[vals[vi]] = .{ .code = @as(u16, @intCast(code)), .len = @as(u8, @intCast(bl + 1)) };
                vi += 1;
            }
            code += 1;
        }
        code <<= 1;
    }
    return lut;
}

const JpegBitWriter = struct {
    buf: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    bit_buf: u32 = 0,
    bit_cnt: u5 = 0,

    fn putBits(self: *JpegBitWriter, code: u16, len: u8) !void {
        var rem = len;
        while (rem > 0) {
            rem -= 1;
            const bit: u32 = (@as(u32, code) >> @as(u4, @intCast(rem))) & 1;
            self.bit_buf = (self.bit_buf << 1) | bit;
            self.bit_cnt += 1;
            if (self.bit_cnt == 8) {
                const byte: u8 = @as(u8, @truncate(self.bit_buf));
                try self.buf.append(self.alloc, byte);
                if (byte == 0xFF) try self.buf.append(self.alloc, 0x00);
                self.bit_buf = 0;
                self.bit_cnt = 0;
            }
        }
    }

    fn flush(self: *JpegBitWriter) !void {
        if (self.bit_cnt > 0) {
            const pad: u8 = @as(u8, 8) - self.bit_cnt;
            try self.putBits(0x7F, pad);
        }
    }
};

fn buildCosTable() [8][8]f32 {
    var tbl: [8][8]f32 = undefined;
    for (0..8) |u| {
        const alpha: f32 = if (u == 0) 0.35355339 else 0.5;
        for (0..8) |x| {
            const angle = (@as(f32, @floatFromInt(2 * x + 1)) * @as(f32, @floatFromInt(u)) * std.math.pi) / 16.0;
            tbl[u][x] = alpha * @cos(angle);
        }
    }
    return tbl;
}

fn fdct8x8(block: *const [64]f32, cos_t: *const [8][8]f32) [64]f32 {
    var tmp: [64]f32 = undefined;
    for (0..8) |row| {
        for (0..8) |u| {
            var sum: f32 = 0.0;
            for (0..8) |x| {
                sum += block[row * 8 + x] * cos_t[u][x];
            }
            tmp[row * 8 + u] = sum;
        }
    }
    var out: [64]f32 = undefined;
    for (0..8) |v| {
        for (0..8) |u| {
            var sum: f32 = 0.0;
            for (0..8) |y| {
                sum += tmp[y * 8 + u] * cos_t[v][y];
            }
            out[v * 8 + u] = sum;
        }
    }
    return out;
}

fn bitCategory(v: i32) u8 {
    var a: u32 = @intCast(@abs(v));
    var bits: u8 = 0;
    while (a > 0) : (a >>= 1) bits += 1;
    return bits;
}

fn encodeBlock(
    bw: *JpegBitWriter,
    block: *const [64]f32,
    cos_t: *const [8][8]f32,
    quant: *const [64]u8,
    dc_lut: *const [256]HuffEntry,
    ac_lut: *const [256]HuffEntry,
    prev_dc: *i32,
) !void {
    const dct = fdct8x8(block, cos_t);
    var zz: [64]i32 = undefined;
    for (0..64) |zi| {
        const idx = ZIGZAG[zi];
        const q = @as(f32, @floatFromInt(quant[idx]));
        zz[zi] = @as(i32, @intFromFloat(@round(dct[idx] / q)));
    }

    // DC coefficient (differential)
    const diff = zz[0] - prev_dc.*;
    prev_dc.* = zz[0];
    const dcat = bitCategory(diff);
    const dh = dc_lut[dcat];
    try bw.putBits(dh.code, dh.len);
    if (dcat > 0) {
        const enc: u16 = if (diff >= 0)
            @as(u16, @intCast(diff))
        else
            @as(u16, @intCast((@as(i32, 1) << @as(u5, @intCast(dcat))) - 1 + diff));
        try bw.putBits(enc, dcat);
    }

    // AC coefficients (RLE)
    var zero_run: usize = 0;
    for (1..64) |k| {
        const val = zz[k];
        if (val == 0) {
            zero_run += 1;
        } else {
            while (zero_run >= 16) {
                const zrl = ac_lut[0xF0];
                try bw.putBits(zrl.code, zrl.len);
                zero_run -= 16;
            }
            const acat = bitCategory(val);
            const sym: u8 = @as(u8, @intCast(zero_run << 4)) | acat;
            const ah = ac_lut[sym];
            try bw.putBits(ah.code, ah.len);
            const enc: u16 = if (val >= 0)
                @as(u16, @intCast(val))
            else
                @as(u16, @intCast((@as(i32, 1) << @as(u5, @intCast(acat))) - 1 + val));
            try bw.putBits(enc, acat);
            zero_run = 0;
        }
    }
    if (zero_run > 0) {
        const eob = ac_lut[0x00];
        try bw.putBits(eob.code, eob.len);
    }
}

fn scaleQuantTable(base: *const [64]u8, quality: u8) [64]u8 {
    const q = std.math.clamp(quality, 1, 100);
    const scale: u32 = if (q < 50) @divTrunc(@as(u32, 5000), @as(u32, q)) else 200 - @as(u32, q) * 2;
    var out: [64]u8 = undefined;
    for (0..64) |i| {
        const v = @divTrunc(@as(u32, base[i]) * scale + 50, 100);
        out[i] = @as(u8, @intCast(std.math.clamp(v, 1, 255)));
    }
    return out;
}

fn writeJpegDht(out: *std.ArrayList(u8), alloc: std.mem.Allocator, tc_th: u8, bits: *const [16]u8, vals: []const u8) !void {
    const len: u16 = @as(u16, @intCast(2 + 1 + 16 + vals.len));
    try out.appendSlice(alloc, &[_]u8{ 0xFF, 0xC4, @as(u8, @truncate(len >> 8)), @as(u8, @truncate(len)), tc_th });
    try out.appendSlice(alloc, bits);
    try out.appendSlice(alloc, vals);
}

pub fn encodeJpegRgb(alloc: std.mem.Allocator, width: usize, height: usize, pixels: []const u8, quality: u8) ![]u8 {
    if (width == 0 or height == 0 or pixels.len < width * height * 3) return error.InvalidPixelBuffer;

    const q_y = scaleQuantTable(&STD_LUMA_QUANT, quality);
    const q_c = scaleQuantTable(&STD_CHROMA_QUANT, quality);
    const dc_y_lut = buildHuffLut(&DC_LUMA_BITS, &DC_LUMA_VALS);
    const dc_c_lut = buildHuffLut(&DC_CHROMA_BITS, &DC_CHROMA_VALS);
    const ac_y_lut = buildHuffLut(&AC_LUMA_BITS, &AC_LUMA_VALS);
    const ac_c_lut = buildHuffLut(&AC_CHROMA_BITS, &AC_CHROMA_VALS);
    const cos_t = buildCosTable();

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(alloc);

    // SOI + APP0 (JFIF 1.01)
    try out.appendSlice(alloc, &[_]u8{
        0xFF, 0xD8,
        0xFF, 0xE0,
        0x00, 0x10,
        'J',  'F',
        'I',  'F',
        0x00, 0x01,
        0x01, 0x00,
        0x00, 0x01,
        0x00, 0x01,
        0x00, 0x00,
    });

    // DQT luminance (id 0) & chrominance (id 1) in zigzag order
    try out.appendSlice(alloc, &[_]u8{ 0xFF, 0xDB, 0x00, 0x43, 0x00 });
    for (0..64) |zi| try out.append(alloc, q_y[ZIGZAG[zi]]);
    try out.appendSlice(alloc, &[_]u8{ 0xFF, 0xDB, 0x00, 0x43, 0x01 });
    for (0..64) |zi| try out.append(alloc, q_c[ZIGZAG[zi]]);

    // SOF0 (Baseline DCT, 8-bit, 3 components 4:4:4 subsampling=0)
    const w16: u16 = @as(u16, @intCast(width));
    const h16: u16 = @as(u16, @intCast(height));
    try out.appendSlice(alloc, &[_]u8{
        0xFF,                         0xC0,                    0x00,                         0x11,                    0x08,
        @as(u8, @truncate(h16 >> 8)), @as(u8, @truncate(h16)), @as(u8, @truncate(w16 >> 8)), @as(u8, @truncate(w16)), 0x03,
        0x01, 0x11, 0x00, // Y:  1x1, quant 0
        0x02, 0x11, 0x01, // Cb: 1x1, quant 1
        0x03, 0x11, 0x01, // Cr: 1x1, quant 1
    });

    // DHT tables
    try writeJpegDht(&out, alloc, 0x00, &DC_LUMA_BITS, &DC_LUMA_VALS);
    try writeJpegDht(&out, alloc, 0x10, &AC_LUMA_BITS, &AC_LUMA_VALS);
    try writeJpegDht(&out, alloc, 0x01, &DC_CHROMA_BITS, &DC_CHROMA_VALS);
    try writeJpegDht(&out, alloc, 0x11, &AC_CHROMA_BITS, &AC_CHROMA_VALS);

    // SOS
    try out.appendSlice(alloc, &[_]u8{
        0xFF, 0xDA, 0x00, 0x0C, 0x03,
        0x01, 0x00, 0x02, 0x11, 0x03,
        0x11, 0x00, 0x3F, 0x00,
    });

    var bw: JpegBitWriter = .{ .buf = &out, .alloc = alloc };
    var prev_y: i32 = 0;
    var prev_cb: i32 = 0;
    var prev_cr: i32 = 0;

    var by: usize = 0;
    while (by < height) : (by += 8) {
        var bx: usize = 0;
        while (bx < width) : (bx += 8) {
            var y_blk: [64]f32 = undefined;
            var cb_blk: [64]f32 = undefined;
            var cr_blk: [64]f32 = undefined;
            for (0..8) |dy| {
                const sy = @min(by + dy, height - 1);
                for (0..8) |dx| {
                    const sx = @min(bx + dx, width - 1);
                    const off = (sy * width + sx) * 3;
                    const r: f32 = @floatFromInt(pixels[off]);
                    const g: f32 = @floatFromInt(pixels[off + 1]);
                    const b: f32 = @floatFromInt(pixels[off + 2]);
                    const idx = dy * 8 + dx;
                    y_blk[idx] = 0.299 * r + 0.587 * g + 0.114 * b - 128.0;
                    cb_blk[idx] = -0.168736 * r - 0.331264 * g + 0.5 * b;
                    cr_blk[idx] = 0.5 * r - 0.418688 * g - 0.081312 * b;
                }
            }
            try encodeBlock(&bw, &y_blk, &cos_t, &q_y, &dc_y_lut, &ac_y_lut, &prev_y);
            try encodeBlock(&bw, &cb_blk, &cos_t, &q_c, &dc_c_lut, &ac_c_lut, &prev_cb);
            try encodeBlock(&bw, &cr_blk, &cos_t, &q_c, &dc_c_lut, &ac_c_lut, &prev_cr);
        }
    }
    try bw.flush();
    try out.appendSlice(alloc, &[_]u8{ 0xFF, 0xD9 }); // EOI
    return out.toOwnedSlice(alloc);
}

// =============================================================================
// 4. IMAGE DIMENSION PROBE & PANORAMIC PLATE PROCESSOR (`vedit plate`)
// =============================================================================

pub const ImageDims = struct { width: usize, height: usize };

pub fn probeImageDims(raw: []const u8) ?ImageDims {
    // PNG IHDR
    if (raw.len >= 24 and std.mem.eql(u8, raw[0..8], &[_]u8{ 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A })) {
        const w = std.mem.readInt(u32, raw[16..20], .big);
        const h = std.mem.readInt(u32, raw[20..24], .big);
        if (w > 0 and h > 0) return .{ .width = w, .height = h };
        return null;
    }
    // JPEG SOF0/SOF1/SOF2
    if (raw.len >= 4 and raw[0] == 0xFF and raw[1] == 0xD8) {
        var pos: usize = 2;
        while (pos + 4 <= raw.len) {
            while (pos < raw.len and raw[pos] != 0xFF) pos += 1;
            while (pos < raw.len and raw[pos] == 0xFF) pos += 1;
            if (pos >= raw.len) break;
            const marker = raw[pos];
            pos += 1;
            if (marker == 0xD9 or marker == 0xDA) break;
            if (marker == 0x01 or (marker >= 0xD0 and marker <= 0xD7)) continue;
            if (pos + 2 > raw.len) break;
            const seg_len = std.mem.readInt(u16, raw[pos..][0..2], .big);
            if (seg_len < 2 or pos + seg_len > raw.len) break;
            if ((marker >= 0xC0 and marker <= 0xC3) or (marker >= 0xC5 and marker <= 0xC7) or (marker >= 0xC9 and marker <= 0xCB)) {
                if (seg_len >= 7) {
                    const h = std.mem.readInt(u16, raw[pos + 3 ..][0..2], .big);
                    const w = std.mem.readInt(u16, raw[pos + 5 ..][0..2], .big);
                    if (w > 0 and h > 0) return .{ .width = w, .height = h };
                }
            }
            pos += seg_len;
        }
    }
    return null;
}

pub fn applyBlackLiftAndFeather(
    pixels: []u8,
    width: usize,
    height: usize,
    bg: mupdf.Rgb,
    feather_y: f64,
    feather_x: f64,
    do_lift: bool,
) void {
    const n_px = width * height;
    if (n_px == 0) return;

    var p10 = [3]f64{ 0.0, 0.0, 0.0 };
    if (do_lift) {
        var hist: [3][256]usize = .{ @splat(0), @splat(0), @splat(0) };
        for (0..n_px) |i| {
            hist[0][pixels[i * 3]] += 1;
            hist[1][pixels[i * 3 + 1]] += 1;
            hist[2][pixels[i * 3 + 2]] += 1;
        }
        const target_rank = n_px / 10;
        for (0..3) |ch| {
            var acc: usize = 0;
            for (0..256) |bval| {
                acc += hist[ch][bval];
                if (acc >= target_rank) {
                    p10[ch] = @floatFromInt(bval);
                    break;
                }
            }
        }
    }

    const bg_f = [3]f64{ @floatFromInt(bg.r), @floatFromInt(bg.g), @floatFromInt(bg.b) };
    const scale_f = [3]f64{
        (255.0 - bg_f[0]) / @max(255.0 - p10[0], 1.0),
        (255.0 - bg_f[1]) / @max(255.0 - p10[1], 1.0),
        (255.0 - bg_f[2]) / @max(255.0 - p10[2], 1.0),
    };

    const safe_fy = if (std.math.isFinite(feather_y)) std.math.clamp(feather_y, 0.0, 0.5) else 0.0;
    const safe_fx = if (std.math.isFinite(feather_x)) std.math.clamp(feather_x, 0.0, 0.5) else 0.0;
    const fy: usize = if (safe_fy > 0.0) @max(@as(usize, 1), @as(usize, @intFromFloat(@round(@as(f64, @floatFromInt(height)) * safe_fy)))) else 0;
    const fx: usize = if (safe_fx > 0.0) @max(@as(usize, 1), @as(usize, @intFromFloat(@round(@as(f64, @floatFromInt(width)) * safe_fx)))) else 0;

    for (0..height) |y| {
        var wy: f64 = 1.0;
        if (fy > 1) {
            if (y < fy) {
                const t = @as(f64, @floatFromInt(y)) / @as(f64, @floatFromInt(fy - 1));
                wy = 0.5 * (1.0 - @cos(std.math.pi * t));
            } else if (y >= height - fy) {
                const t = @as(f64, @floatFromInt(height - 1 - y)) / @as(f64, @floatFromInt(fy - 1));
                wy = 0.5 * (1.0 - @cos(std.math.pi * t));
            }
        }
        for (0..width) |x| {
            var wx: f64 = 1.0;
            if (fx > 1) {
                if (x < fx) {
                    const t = @as(f64, @floatFromInt(x)) / @as(f64, @floatFromInt(fx - 1));
                    wx = 0.5 * (1.0 - @cos(std.math.pi * t));
                } else if (x >= width - fx) {
                    const t = @as(f64, @floatFromInt(width - 1 - x)) / @as(f64, @floatFromInt(fx - 1));
                    wx = 0.5 * (1.0 - @cos(std.math.pi * t));
                }
            }
            const mask = wy * wx;
            const off = (y * width + x) * 3;
            for (0..3) |ch| {
                const raw_v: f64 = @floatFromInt(pixels[off + ch]);
                const lifted: f64 = if (do_lift)
                    std.math.clamp((raw_v - p10[ch]) * scale_f[ch] + bg_f[ch], bg_f[ch], 255.0)
                else
                    raw_v;
                const blended = std.math.clamp(lifted * mask + bg_f[ch] * (1.0 - mask), 0.0, 255.0);
                pixels[off + ch] = @as(u8, @intFromFloat(@round(blended)));
            }
        }
    }
}

pub fn processPlate(
    alloc: std.mem.Allocator,
    io: std.Io,
    input_path: []const u8,
    output_path: []const u8,
    width_pt: f64,
    height_pt: f64,
    bg: mupdf.Rgb,
    feather_y: f64,
    feather_x: f64,
    quality: u8,
    do_lift: bool,
    tmp_tag: []const u8,
) !PlateResult {
    if (!std.math.isFinite(width_pt) or !std.math.isFinite(height_pt) or width_pt <= 0.0 or height_pt <= 0.0 or width_pt > 1.0e6 or height_pt > 1.0e6) {
        return error.InvalidPlateDimensions;
    }
    if (!std.math.isFinite(feather_y) or !std.math.isFinite(feather_x) or feather_y < 0.0 or feather_y > 0.5 or feather_x < 0.0 or feather_x > 0.5) {
        return error.InvalidFeatherParameter;
    }
    if (quality < 1 or quality > 100) return error.InvalidJpegQuality;

    const raw_in = try std.Io.Dir.cwd().readFileAlloc(io, input_path, alloc, .unlimited);
    const dims = probeImageDims(raw_in) orelse return error.UnsupportedImageFormat;

    const ppm_path = try mupdf.tmpPath(alloc, tmp_tag, "plate.ppm");
    defer mupdf.removeTmpBestEffort(io, ppm_path);

    const w_arg = try std.fmt.allocPrint(alloc, "{d}", .{dims.width});
    const h_arg = try std.fmt.allocPrint(alloc, "{d}", .{dims.height});
    const dec = try mupdf.runCmd(alloc, io, &.{ "mutool", "draw", "-F", "ppm", "-w", w_arg, "-h", h_arg, "-o", ppm_path, input_path }, null);
    if (dec.exit_code != 0) return error.MutoolDecodeFailed;

    const ppm_raw = try std.Io.Dir.cwd().readFileAlloc(io, ppm_path, alloc, .unlimited);
    const img = try mupdf.parsePpm(ppm_raw);

    // Deterministic center crop to target slot aspect (checked finite rounding)
    const target_aspect = width_pt / height_pt;
    const src_aspect = @as(f64, @floatFromInt(img.width)) / @as(f64, @floatFromInt(img.height));
    var crop_w = img.width;
    var crop_h = img.height;
    if (src_aspect < target_aspect) {
        const raw_h = try mupdf.checkedRoundInt(usize, @as(f64, @floatFromInt(img.width)) / target_aspect, 0.0, @as(f64, @floatFromInt(img.height)) + 1.0);
        crop_h = @max(@as(usize, 1), @min(img.height, raw_h));
    } else {
        const raw_w = try mupdf.checkedRoundInt(usize, @as(f64, @floatFromInt(img.height)) * target_aspect, 0.0, @as(f64, @floatFromInt(img.width)) + 1.0);
        crop_w = @max(@as(usize, 1), @min(img.width, raw_w));
    }
    const x0 = (img.width - crop_w) / 2;
    const y0 = (img.height - crop_h) / 2;

    const cropped = try alloc.alloc(u8, crop_w * crop_h * 3);
    for (0..crop_h) |y| {
        const src_row = ((y0 + y) * img.width + x0) * 3;
        const dst_row = y * crop_w * 3;
        @memcpy(cropped[dst_row .. dst_row + crop_w * 3], img.pixels[src_row .. src_row + crop_w * 3]);
    }

    applyBlackLiftAndFeather(cropped, crop_w, crop_h, bg, feather_y, feather_x, do_lift);

    if (std.fs.path.dirname(output_path)) |parent| {
        if (parent.len > 0) try ensureDir(io, parent);
    }

    const is_png = std.ascii.endsWithIgnoreCase(output_path, ".png");
    const encoded = if (is_png)
        try encodePngRgb(alloc, crop_w, crop_h, cropped)
    else
        try encodeJpegRgb(alloc, crop_w, crop_h, cropped, quality);

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = output_path, .data = encoded });

    return .{
        .input_w = img.width,
        .input_h = img.height,
        .out_w = crop_w,
        .out_h = crop_h,
        .out_bytes = encoded.len,
        .dpi_x = @as(f64, @floatFromInt(crop_w)) / (width_pt / 72.0),
        .dpi_y = @as(f64, @floatFromInt(crop_h)) / (height_pt / 72.0),
        .corner = .{ .r = cropped[0], .g = cropped[1], .b = cropped[2] },
    };
}

// =============================================================================
// 5. FACING-SPREAD CONTACT SHEET COMPOSER (`vedit spreads`)
// =============================================================================

fn downscaleBilinear(alloc: std.mem.Allocator, src: []const u8, sw: usize, sh: usize, dw: usize, dh: usize) ![]u8 {
    const out = try alloc.alloc(u8, dw * dh * 3);
    const sx_ratio = @as(f64, @floatFromInt(sw)) / @as(f64, @floatFromInt(dw));
    const sy_ratio = @as(f64, @floatFromInt(sh)) / @as(f64, @floatFromInt(dh));
    for (0..dh) |dy| {
        const fy = (@as(f64, @floatFromInt(dy)) + 0.5) * sy_ratio - 0.5;
        const y0: usize = if (fy < 0.0) 0 else @min(sh - 1, @as(usize, @intFromFloat(@floor(fy))));
        const y1: usize = @min(sh - 1, y0 + 1);
        const ty = std.math.clamp(fy - @as(f64, @floatFromInt(y0)), 0.0, 1.0);
        for (0..dw) |dx| {
            const fx = (@as(f64, @floatFromInt(dx)) + 0.5) * sx_ratio - 0.5;
            const x0: usize = if (fx < 0.0) 0 else @min(sw - 1, @as(usize, @intFromFloat(@floor(fx))));
            const x1: usize = @min(sw - 1, x0 + 1);
            const tx = std.math.clamp(fx - @as(f64, @floatFromInt(x0)), 0.0, 1.0);

            const o00 = (y0 * sw + x0) * 3;
            const o10 = (y0 * sw + x1) * 3;
            const o01 = (y1 * sw + x0) * 3;
            const o11 = (y1 * sw + x1) * 3;
            const dst = (dy * dw + dx) * 3;
            for (0..3) |ch| {
                const top = @as(f64, @floatFromInt(src[o00 + ch])) * (1.0 - tx) + @as(f64, @floatFromInt(src[o10 + ch])) * tx;
                const bot = @as(f64, @floatFromInt(src[o01 + ch])) * (1.0 - tx) + @as(f64, @floatFromInt(src[o11 + ch])) * tx;
                out[dst + ch] = @as(u8, @intFromFloat(@round(top * (1.0 - ty) + bot * ty)));
            }
        }
    }
    return out;
}

pub fn renderSpreads(
    alloc: std.mem.Allocator,
    io: std.Io,
    pdf_path: []const u8,
    out_dir: []const u8,
    dpi: u32,
    target_width: usize,
    tmp_tag: []const u8,
) !SpreadsResult {
    if (dpi < 18 or dpi > 600) return error.InvalidDpi;
    if (target_width > 16384) return error.InvalidTargetWidth;
    try ensureDir(io, out_dir);
    const cat = try mupdf.inspectCatalog(alloc, io, pdf_path);
    var written: std.ArrayList([]const u8) = .empty;

    var left_pg: usize = 2;
    while (left_pg + 1 <= cat.page_count) : (left_pg += 2) {
        const right_pg = left_pg + 1;
        const im_l = try mupdf.renderPagePpm(alloc, io, pdf_path, left_pg, dpi, tmp_tag);
        const im_r = try mupdf.renderPagePpm(alloc, io, pdf_path, right_pg, dpi, tmp_tag);
        const pw = @min(im_l.width, im_r.width);
        const ph = @min(im_l.height, im_r.height);
        const pad = @max(@as(usize, 24), @as(usize, @intFromFloat(@round(@as(f64, @floatFromInt(pw)) * 0.04))));
        const cw = pw * 2 + pad * 2;
        const ch = ph + pad * 2;

        const canvas = try alloc.alloc(u8, cw * ch * 3);
        // Archival desk mat (229, 224, 214)
        for (0..cw * ch) |pi| {
            canvas[pi * 3] = 229;
            canvas[pi * 3 + 1] = 224;
            canvas[pi * 3 + 2] = 214;
        }
        // Subtle 2px outer frame (188, 181, 170)
        for (pad - 2..pad + ph + 2) |y| {
            for (pad - 2..pad + pw * 2 + 2) |x| {
                const is_edge = (y < pad or y >= pad + ph or x < pad or x >= pad + pw * 2);
                if (is_edge) {
                    const off = (y * cw + x) * 3;
                    canvas[off] = 188;
                    canvas[off + 1] = 181;
                    canvas[off + 2] = 170;
                }
            }
        }
        // Paste left & right pages
        for (0..ph) |y| {
            const dst_l = ((pad + y) * cw + pad) * 3;
            const dst_r = ((pad + y) * cw + pad + pw) * 3;
            const src_l = y * im_l.width * 3;
            const src_r = y * im_r.width * 3;
            @memcpy(canvas[dst_l .. dst_l + pw * 3], im_l.pixels[src_l .. src_l + pw * 3]);
            @memcpy(canvas[dst_r .. dst_r + pw * 3], im_r.pixels[src_r .. src_r + pw * 3]);
        }
        // Central spine-gutter shadow
        const spine_x = pad + pw;
        const half_span = @max(@as(usize, 12), @as(usize, @intFromFloat(@round(@as(f64, @floatFromInt(pw)) * 0.016))));
        for (0..half_span * 2 + 1) |k| {
            const dx_abs = if (k >= half_span) k - half_span else half_span - k;
            const x = spine_x + k - half_span;
            const falloff = 1.0 - @as(f64, @floatFromInt(dx_abs)) / @as(f64, @floatFromInt(half_span + 1));
            const alpha_f: f64 = if (dx_abs == 0) 85.0 / 255.0 else (56.0 * std.math.pow(f64, falloff, 2.2)) / 255.0;
            if (alpha_f <= 0.0) continue;
            for (pad..pad + ph) |y| {
                const off = (y * cw + x) * 3;
                canvas[off] = @as(u8, @intFromFloat(@round(@as(f64, @floatFromInt(canvas[off])) * (1.0 - alpha_f) + 20.0 * alpha_f)));
                canvas[off + 1] = @as(u8, @intFromFloat(@round(@as(f64, @floatFromInt(canvas[off + 1])) * (1.0 - alpha_f) + 18.0 * alpha_f)));
                canvas[off + 2] = @as(u8, @intFromFloat(@round(@as(f64, @floatFromInt(canvas[off + 2])) * (1.0 - alpha_f) + 16.0 * alpha_f)));
            }
        }

        var final_w = cw;
        var final_h = ch;
        var final_px: []const u8 = canvas;
        if (target_width > 0 and cw > target_width) {
            final_w = target_width;
            final_h = @max(@as(usize, 1), @as(usize, @intFromFloat(@round(@as(f64, @floatFromInt(ch)) * (@as(f64, @floatFromInt(target_width)) / @as(f64, @floatFromInt(cw)))))));
            final_px = try downscaleBilinear(alloc, canvas, cw, ch, final_w, final_h);
        }

        const png_bytes = try encodePngRgb(alloc, final_w, final_h, final_px);
        const fname = try std.fmt.allocPrint(alloc, "spread_{d:0>2}_{d:0>2}.png", .{ left_pg, right_pg });
        const out_path = try std.fs.path.join(alloc, &.{ out_dir, fname });
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = out_path, .data = png_bytes });
        try written.append(alloc, out_path);
    }

    return .{ .written = try written.toOwnedSlice(alloc) };
}

// =============================================================================
// UNIT TESTS (Debug + -OReleaseSafe, leak-checked)
// =============================================================================

test "pure-Zig PNG and JPEG encoders emit valid headers and round-trip dimensions" {
    const alloc = std.testing.allocator;
    const w: usize = 32;
    const h: usize = 24;
    const px = try alloc.alloc(u8, w * h * 3);
    defer alloc.free(px);
    for (0..h) |y| {
        for (0..w) |x| {
            const off = (y * w + x) * 3;
            px[off] = @as(u8, @intCast(x * 7));
            px[off + 1] = @as(u8, @intCast(y * 10));
            px[off + 2] = 90;
        }
    }

    const png = try encodePngRgb(alloc, w, h, px);
    defer alloc.free(png);
    const pdims = probeImageDims(png) orelse return error.PngProbeFailed;
    try std.testing.expectEqual(w, pdims.width);
    try std.testing.expectEqual(h, pdims.height);

    const jpg = try encodeJpegRgb(alloc, w, h, px, 88);
    defer alloc.free(jpg);
    try std.testing.expectEqual(@as(u8, 0xFF), jpg[0]);
    try std.testing.expectEqual(@as(u8, 0xD8), jpg[1]);
    try std.testing.expectEqual(@as(u8, 0xFF), jpg[jpg.len - 2]);
    try std.testing.expectEqual(@as(u8, 0xD9), jpg[jpg.len - 1]);
    const jdims = probeImageDims(jpg) orelse return error.JpegProbeFailed;
    try std.testing.expectEqual(w, jdims.width);
    try std.testing.expectEqual(h, jdims.height);
}

test "applyBlackLiftAndFeather aligns dark edges to exact OLED void while preserving center highlight" {
    const alloc = std.testing.allocator;
    const w: usize = 40;
    const h: usize = 20;
    const px = try alloc.alloc(u8, w * h * 3);
    defer alloc.free(px);
    @memset(px, 0);
    // Bright golden highlight right in the center
    const center_off = ((h / 2) * w + (w / 2)) * 3;
    px[center_off] = 232;
    px[center_off + 1] = 192;
    px[center_off + 2] = 120;

    applyBlackLiftAndFeather(px, w, h, .{ .r = 7, .g = 9, .b = 15 }, 0.16, 0.10, true);

    try std.testing.expectEqual(@as(u8, 7), px[0]);
    try std.testing.expectEqual(@as(u8, 9), px[1]);
    try std.testing.expectEqual(@as(u8, 15), px[2]);
    try std.testing.expect(px[center_off] >= 220);
}
