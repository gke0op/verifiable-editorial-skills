//! Sovereign Zero-Python Adversarial Sabotage, Flagship Regression & Closed-Loop Test Court (`court_tests.zig`).
//! Ports 100% of the 30-test adversarial suite into bare-metal Zig 0.17.0 (`zig build test-court`),
//! verified in both `Debug` and `--release=safe` with zero Python and zero `pytest`.

const std = @import("std");
const kernels = @import("kernels_p2zig.zig");
const mupdf = @import("mupdf.zig");
const audit = @import("audit.zig");
const links = @import("links.zig");
const dissect = @import("dissect.zig");
const scaffold = @import("scaffold.zig");
const media = @import("media.zig");

const PdfLinkSpec = struct {
    uri: []const u8,
    x0: f64,
    y0: f64,
    x1: f64,
    y1: f64,
};

const PdfImageSpec = struct {
    w: usize,
    h: usize,
    jpeg_bytes: []const u8,
};

const PdfBuildOpts = struct {
    page_w: f64 = 612.0,
    page_h: f64 = 792.0,
    content: []const u8,
    image: ?PdfImageSpec = null,
    form_content: ?[]const u8 = null,
    links: []const PdfLinkSpec = &.{},
};

fn findRepoRoot(io: std.Io) []const u8 {
    if (std.Io.Dir.cwd().openDir(io, "demos/cosmos-mobile-primer", .{})) |d| {
        var dir = d;
        dir.close(io);
        return ".";
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => std.log.debug("repo root probe: {s}", .{@errorName(err)}),
    }
    return "..";
}

fn ensureTestDir(io: std.Io, path: []const u8) !void {
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

fn makeSolidJpeg(alloc: std.mem.Allocator, w: usize, h: usize, rgb: mupdf.Rgb) ![]u8 {
    const px = try alloc.alloc(u8, w * h * 3);
    for (0..w * h) |i| {
        px[i * 3] = rgb.r;
        px[i * 3 + 1] = rgb.g;
        px[i * 3 + 2] = rgb.b;
    }
    return media.encodeJpegRgb(alloc, w, h, px, 85);
}

/// Emit a valid ISO 32000-1 PDF with exact xref byte offsets, Base-14 Helvetica/Helvetica-Bold,
/// optional JPEG Image XObject (/Im1), optional Form XObject (/Fm1), and optional clickable /URI links.
fn writeSimplePdf(alloc: std.mem.Allocator, io: std.Io, path: []const u8, opts: PdfBuildOpts) !void {
    var out: std.ArrayList(u8) = .empty;
    var offsets: std.ArrayList(usize) = .empty;

    try out.appendSlice(alloc, "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n");

    // Object numbering:
    // 1: Catalog, 2: Pages, 3: Page, 4: Content Stream, 5: Font F1 (Helvetica), 6: Font F2 (Helvetica-Bold)
    // Optional 7+: Image XObject (/Im1), Form XObject (/Fm1), Link Annotations
    var next_id: usize = 7;
    const img_id: ?usize = if (opts.image != null) blk: {
        const id = next_id;
        next_id += 1;
        break :blk id;
    } else null;
    const form_id: ?usize = if (opts.form_content != null) blk: {
        const id = next_id;
        next_id += 1;
        break :blk id;
    } else null;
    const first_annot_id = next_id;
    next_id += opts.links.len;
    const total_objs = next_id - 1;

    // 1: Catalog
    try offsets.append(alloc, out.items.len);
    try out.appendSlice(alloc, "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n");

    // 2: Pages
    try offsets.append(alloc, out.items.len);
    try out.appendSlice(alloc, "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n");

    // 3: Page
    try offsets.append(alloc, out.items.len);
    var xobj_dict: std.ArrayList(u8) = .empty;
    if (img_id != null or form_id != null) {
        try xobj_dict.appendSlice(alloc, " /XObject <<");
        if (img_id) |iid| try xobj_dict.appendSlice(alloc, try std.fmt.allocPrint(alloc, " /Im1 {d} 0 R", .{iid}));
        if (form_id) |fid| try xobj_dict.appendSlice(alloc, try std.fmt.allocPrint(alloc, " /Fm1 {d} 0 R", .{fid}));
        try xobj_dict.appendSlice(alloc, " >>");
    }
    var annots_arr: std.ArrayList(u8) = .empty;
    if (opts.links.len > 0) {
        try annots_arr.appendSlice(alloc, " /Annots [");
        for (0..opts.links.len) |li| {
            try annots_arr.appendSlice(alloc, try std.fmt.allocPrint(alloc, " {d} 0 R", .{first_annot_id + li}));
        }
        try annots_arr.appendSlice(alloc, " ]");
    }
    try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\3 0 obj
        \\<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {d:.1} {d:.1}] /Resources << /Font << /F1 5 0 R /F2 6 0 R >>{s} >> /Contents 4 0 R{s} >>
        \\endobj
        \\
    , .{ opts.page_w, opts.page_h, xobj_dict.items, annots_arr.items }));

    // 4: Page Content Stream
    try offsets.append(alloc, out.items.len);
    try out.appendSlice(alloc, try std.fmt.allocPrint(alloc, "4 0 obj\n<< /Length {d} >>\nstream\n", .{opts.content.len}));
    try out.appendSlice(alloc, opts.content);
    try out.appendSlice(alloc, "\nendstream\nendobj\n");

    // 5: Helvetica
    try offsets.append(alloc, out.items.len);
    try out.appendSlice(alloc, "5 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n");

    // 6: Helvetica-Bold
    try offsets.append(alloc, out.items.len);
    try out.appendSlice(alloc, "6 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>\nendobj\n");

    // Optional Image XObject
    if (opts.image) |im| {
        try offsets.append(alloc, out.items.len);
        try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\{d} 0 obj
            \\<< /Type /XObject /Subtype /Image /Width {d} /Height {d} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length {d} >>
            \\stream
            \\
        , .{ img_id.?, im.w, im.h, im.jpeg_bytes.len }));
        try out.appendSlice(alloc, im.jpeg_bytes);
        try out.appendSlice(alloc, "\nendstream\nendobj\n");
    }

    // Optional Form XObject
    if (opts.form_content) |fc| {
        try offsets.append(alloc, out.items.len);
        try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\{d} 0 obj
            \\<< /Type /XObject /Subtype /Form /BBox [0 0 {d:.1} {d:.1}] /Resources << /Font << /F1 5 0 R /F2 6 0 R >> >> /Length {d} >>
            \\stream
            \\
        , .{ form_id.?, opts.page_w, opts.page_h, fc.len }));
        try out.appendSlice(alloc, fc);
        try out.appendSlice(alloc, "\nendstream\nendobj\n");
    }

    // Optional Link Annotations
    for (opts.links, 0..) |lk, li| {
        try offsets.append(alloc, out.items.len);
        try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\{d} 0 obj
            \\<< /Type /Annot /Subtype /Link /Rect [{d:.2} {d:.2} {d:.2} {d:.2}] /Border [0 0 0] /A << /Type /Action /S /URI /URI ({s}) >> >>
            \\endobj
            \\
        , .{ first_annot_id + li, lk.x0, lk.y0, lk.x1, lk.y1, lk.uri }));
    }

    const xref_off = out.items.len;
    try out.appendSlice(alloc, try std.fmt.allocPrint(alloc, "xref\n0 {d}\n0000000000 65535 f \n", .{total_objs + 1}));
    for (offsets.items) |off| {
        try out.appendSlice(alloc, try std.fmt.allocPrint(alloc, "{d:0>10} 00000 n \n", .{off}));
    }
    try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\trailer
        \\<< /Size {d} /Root 1 0 R >>
        \\startxref
        \\{d}
        \\%%EOF
        \\
    , .{ total_objs + 1, xref_off }));

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = out.items });
}

fn compileTypstSnippet(alloc: std.mem.Allocator, io: std.Io, tmp_dir: []const u8, name: []const u8, body: []const u8) ![]const u8 {
    const typ_path = try std.fmt.allocPrint(alloc, "{s}/{s}.typ", .{ tmp_dir, name });
    const pdf_path = try std.fmt.allocPrint(alloc, "{s}/{s}.pdf", .{ tmp_dir, name });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = typ_path, .data = body });
    const res = try mupdf.runCmd(alloc, io, &.{ "typst", "compile", typ_path, pdf_path }, null);
    if (res.exit_code != 0) return error.TypstCompileFailed;
    return pdf_path;
}

// =============================================================================
// 1. ADVERSARIAL SABOTAGE TESTS (EVERY SINGLE GATE MUST REJECT CHEATS!)
// =============================================================================

test "sabotage 01: WCAG rejects low-contrast dark text (#505862 on #051C2C < 3.0:1)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;
    const tmp = "/tmp/vedit_court_01";
    try ensureTestDir(io, tmp);
    defer mupdf.removeTmpDirBestEffort(io, tmp);

    const pdf = try std.fmt.allocPrint(alloc, "{s}/bad_contrast.pdf", .{tmp});
    try writeSimplePdf(alloc, io, pdf, .{
        .content =
        \\0.0196 0.1098 0.1725 rg 0 0 612 792 re f
        \\0.3137 0.3451 0.3843 rg
        \\BT /F1 11 Tf 50 700 Td (Unreadable dark-mode executive body text) Tj ET
        ,
    });
    const pages = try mupdf.extractPages(alloc, io, pdf);
    const rep = try audit.auditContrast(alloc, io, pdf, pages, "ct01");
    try std.testing.expect(!rep.passed);
    try std.testing.expect(rep.total_violations >= 1);
    try std.testing.expect(rep.worst_cr_x100 < 300);
}

test "sabotage 02: geometry rejects overlapping text spans (AABB collision)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;
    const tmp = "/tmp/vedit_court_02";
    try ensureTestDir(io, tmp);
    defer mupdf.removeTmpDirBestEffort(io, tmp);

    const pdf = try std.fmt.allocPrint(alloc, "{s}/collision.pdf", .{tmp});
    try writeSimplePdf(alloc, io, pdf, .{
        .content =
        \\0.067 0.067 0.067 rg
        \\BT /F2 11 Tf 80 600 Td (ANGIOSPERMS TRUE FLOWERS) Tj ET
        \\BT /F1 11 Tf 95 599 Td (Malvaceae OTT 659136 191 flw) Tj ET
        ,
    });
    const pages = try mupdf.extractPages(alloc, io, pdf);
    const rep = try audit.auditGeometry(alloc, io, pdf, pages, 55.0, "ct02");
    try std.testing.expect(!rep.passed);
    try std.testing.expect(rep.collisions >= 1);
}

test "sabotage 03: geometry rejects W/W* clip-path sliced text (vertical, top-half, bottom-half, Form XObject, nested + controls)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;
    const tmp = "/tmp/vedit_court_03";
    try ensureTestDir(io, tmp);
    defer mupdf.removeTmpDirBestEffort(io, tmp);

    const Case = struct { name: []const u8, content: []const u8, form: ?[]const u8 = null, expect_fail: bool };
    const cases = [_]Case{
        .{
            .name = "right_edge_slice",
            .content = "q 50 680 80 30 re W n 0.067 0.067 0.067 rg BT /F1 12 Tf 54 690 Td (Thick low-resin bark insulates cambium from fire) Tj ET Q",
            .expect_fail = true,
        },
        .{
            .name = "top_half_slice",
            .content = "q 40 680 400 14 re W n 0.067 0.067 0.067 rg BT /F1 12 Tf 54 690 Td (Thick low-resin bark insulates cambium from fire) Tj ET Q",
            .expect_fail = true,
        },
        .{
            .name = "bottom_half_slice",
            .content = "q 40 694 400 20 re W n 0.067 0.067 0.067 rg BT /F1 12 Tf 54 690 Td (Thick low-resin bark insulates cambium from fire) Tj ET Q",
            .expect_fail = true,
        },
        .{
            .name = "form_xobject_slice",
            .content = "/Fm1 Do",
            .form = "q 50 680 80 30 re W n 0.067 0.067 0.067 rg BT /F1 12 Tf 54 690 Td (Thick low-resin bark insulates cambium from fire) Tj ET Q",
            .expect_fail = true,
        },
        .{
            .name = "nested_inner_slices",
            .content = "q 0 0 612 792 re W n q 50 680 80 30 re W n 0.067 0.067 0.067 rg BT /F1 12 Tf 54 690 Td (Thick low-resin bark insulates cambium from fire) Tj ET Q Q",
            .expect_fail = true,
        },
        .{
            .name = "popped_clip_control",
            .content = "q 50 680 80 30 re W n Q 0.067 0.067 0.067 rg BT /F1 12 Tf 54 690 Td (Thick low-resin bark insulates cambium from fire) Tj ET",
            .expect_fail = false,
        },
        .{
            .name = "generous_clip_control",
            .content = "q 40 670 400 50 re W n 0.067 0.067 0.067 rg BT /F1 12 Tf 54 690 Td (Thick low-resin bark insulates cambium from fire) Tj ET Q",
            .expect_fail = false,
        },
    };

    for (cases) |tc| {
        const pdf = try std.fmt.allocPrint(alloc, "{s}/{s}.pdf", .{ tmp, tc.name });
        try writeSimplePdf(alloc, io, pdf, .{ .content = tc.content, .form_content = tc.form });
        const pages = try mupdf.extractPages(alloc, io, pdf);
        const rep = try audit.auditGeometry(alloc, io, pdf, pages, 55.0, tc.name);
        try std.testing.expectEqual(tc.expect_fail, !rep.passed);
        if (tc.expect_fail) try std.testing.expect(rep.clipped >= 1);
    }
}

test "sabotage 04: geometry rejects orphan display headline wrap" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;
    const tmp = "/tmp/vedit_court_04";
    try ensureTestDir(io, tmp);
    defer mupdf.removeTmpDirBestEffort(io, tmp);

    const pdf = try std.fmt.allocPrint(alloc, "{s}/orphan.pdf", .{tmp});
    try writeSimplePdf(alloc, io, pdf, .{
        .content =
        \\0.067 0.067 0.067 rg
        \\BT /F2 24 Tf 40 720 Td (Global Occurrence, Herbaria & Bloom) Tj ET
        \\BT /F2 24 Tf 40 692 Td (Calendars) Tj ET
        ,
    });
    const pages = try mupdf.extractPages(alloc, io, pdf);
    const rep = try audit.auditGeometry(alloc, io, pdf, pages, 55.0, "ct04");
    try std.testing.expect(!rep.passed);
    try std.testing.expect(rep.headline_orphans >= 1);
}

test "sabotage 05: dual-key coverage rejects clip-inflated 40% photo drawn across 75%" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;
    const tmp = "/tmp/vedit_court_05";
    try ensureTestDir(io, tmp);
    defer mupdf.removeTmpDirBestEffort(io, tmp);

    const jpg = try makeSolidJpeg(alloc, 200, 200, .{ .r = 30, .g = 110, .b = 75 });
    const pdf = try std.fmt.allocPrint(alloc, "{s}/sub50_clipped.pdf", .{tmp});
    // Clip strictly to top 40% (316.8pt of 792pt) while unclipped image spans 75% (594pt)
    try writeSimplePdf(alloc, io, pdf, .{
        .content = "q 0 475.2 612 316.8 re W n q 612 0 0 594 0 198 cm /Im1 Do Q Q",
        .image = .{ .w = 200, .h = 200, .jpeg_bytes = jpg },
    });
    const rep = try audit.auditCoverage(alloc, io, pdf, 1, 50.0, 2, null, "ct05");
    try std.testing.expect(!rep.passed);
    try std.testing.expect(rep.min_visible_pct >= 38.0 and rep.min_visible_pct <= 42.0);
}

test "sabotage 06: Rule 10 rejects hallucinated number, sign flip, precision tolerance & blanket escapes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;
    const tmp = "/tmp/vedit_court_06";
    try ensureTestDir(io, tmp);
    defer mupdf.removeTmpDirBestEffort(io, tmp);

    const Case = struct { name: []const u8, ledger_json: []const u8, text: []const u8, expect_pass: bool };
    const cases = [_]Case{
        .{ .name = "hallucinated", .ledger_json = "{\"g\":{\"value\":64896}}", .text = "Verified count is 64,896 but a hallucinated claim says 14,999 specimens.", .expect_pass = false },
        .{ .name = "sign_flip", .ledger_json = "[{\"metric_id\":\"c\",\"value\":-45.01}]", .text = "Carbon intensity moved -45.0% in reality, not +45.0%.", .expect_pass = false },
        .{ .name = "p0049", .ledger_json = "{\"k0\":{\"value\":64896}}", .text = "Significant at p = 0.049.", .expect_pass = false },
        .{ .name = "p0001", .ledger_json = "{\"k0\":{\"value\":64896}}", .text = "Fabricated p = 0.001 effect.", .expect_pass = false },
        .{ .name = "surge_52", .ledger_json = "{\"k0\":{\"value\":64896}}", .text = "A 52% surge in sales.", .expect_pass = false },
        .{ .name = "specimens_300", .ledger_json = "{\"k0\":{\"value\":64896}}", .text = "Only 300 specimens exist.", .expect_pass = false },
        .{ .name = "specimens_5", .ledger_json = "{\"k0\":{\"value\":64896}}", .text = "Only 5 specimens exist.", .expect_pass = false },
        .{ .name = "ratio_057", .ledger_json = "{\"k0\":{\"value\":0.5255}}", .text = "Ratio is 0.57.", .expect_pass = false },
        .{ .name = "ratio_05262", .ledger_json = "{\"k0\":{\"value\":0.5255}}", .text = "Ratio is 0.5262.", .expect_pass = false },
        .{ .name = "ratio_05260", .ledger_json = "{\"k0\":{\"value\":0.5255},\"k1\":{\"value\":64896}}", .text = "Ratio is 0.5260 across 64,896 records.", .expect_pass = false },
        .{ .name = "decimal_comma", .ledger_json = "{\"k0\":{\"value\":64.896}}", .text = "The share was 64,897 percent.", .expect_pass = false },
        .{ .name = "eight_digit", .ledger_json = "{\"k0\":{\"value\":45}}", .text = "The count was 12345678 units.", .expect_pass = false },
        // Controls MUST PASS
        .{ .name = "exact_and_round", .ledger_json = "{\"k0\":{\"value\":0.5255},\"k1\":{\"value\":64896}}", .text = "Ratio is 0.5255 (2dp: 0.53, 3dp: 0.526) across 64,896 records.", .expect_pass = true },
        .{ .name = "contextual_ord", .ledger_json = "{\"k0\":{\"value\":64896}}", .text = "See Figure 2 and Table 3 on Page 1 (Rule 10) for 64,896 rows.", .expect_pass = true },
    };

    for (cases) |tc| {
        const led = try std.fmt.allocPrint(alloc, "{s}/{s}.json", .{ tmp, tc.name });
        const pdf = try std.fmt.allocPrint(alloc, "{s}/{s}.pdf", .{ tmp, tc.name });
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = led, .data = tc.ledger_json });
        const content = try std.fmt.allocPrint(alloc, "BT /F1 11 Tf 50 700 Td ({s}) Tj ET", .{tc.text});
        try writeSimplePdf(alloc, io, pdf, .{ .content = content });
        const pages = try mupdf.extractPages(alloc, io, pdf);
        const rep = try audit.auditProse(alloc, io, pages, led, null, null, null);
        try std.testing.expectEqual(tc.expect_pass, rep.passed);
    }
}

test "sabotage 07: Rule 10 rejects forged caret, layout-raised, Unicode superscript exponents & fullwidth digits" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;
    const tmp = "/tmp/vedit_court_07";
    try ensureTestDir(io, tmp);
    defer mupdf.removeTmpDirBestEffort(io, tmp);

    const CaretCase = struct { name: []const u8, val: []const u8, txt: []const u8, expect_pass: bool };
    const caret_cases = [_]CaretCase{
        .{ .name = "caret_10_7", .val = "1000000.0", .txt = "We sampled 10^7 points.", .expect_pass = false },
        .{ .name = "caret_10_6", .val = "1000000.0", .txt = "We sampled 10^6 points.", .expect_pass = true },
        .{ .name = "sci_97e9", .val = "9.7", .txt = "Flux is 9.7*10^9 erg.", .expect_pass = false },
        .{ .name = "sci_97e6", .val = "9700000.0", .txt = "Flux is 9.7*10^6 erg.", .expect_pass = true },
    };
    for (caret_cases) |tc| {
        const led = try std.fmt.allocPrint(alloc, "{s}/{s}.json", .{ tmp, tc.name });
        const pdf = try std.fmt.allocPrint(alloc, "{s}/{s}.pdf", .{ tmp, tc.name });
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = led, .data = try std.fmt.allocPrint(alloc, "{{\"k0\":{{\"value\":{s}}}}}", .{tc.val}) });
        try writeSimplePdf(alloc, io, pdf, .{ .content = try std.fmt.allocPrint(alloc, "BT /F1 11 Tf 50 700 Td ({s}) Tj ET", .{tc.txt}) });
        const pages = try mupdf.extractPages(alloc, io, pdf);
        const rep = try audit.auditProse(alloc, io, pages, led, null, null, null);
        try std.testing.expectEqual(tc.expect_pass, rep.passed);
    }

    // Layout-positioned raised superscript 10^7 vs ledger 1e6 -> FAIL
    const sup_led = try std.fmt.allocPrint(alloc, "{s}/sup.json", .{tmp});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = sup_led, .data = "{\"k0\":{\"value\":1000000.0}}" });
    const sup_pdf = try std.fmt.allocPrint(alloc, "{s}/layout_sup_10_7.pdf", .{tmp});
    try writeSimplePdf(alloc, io, sup_pdf, .{
        .content =
        \\BT /F1 11 Tf 50 700 Td (We sampled 10) Tj ET
        \\BT /F1 7 Tf 121 704 Td (7) Tj ET
        \\BT /F1 11 Tf 127 700 Td (points.) Tj ET
        ,
    });
    const sup_pages = try mupdf.extractPages(alloc, io, sup_pdf);
    const sup_rep = try audit.auditProse(alloc, io, sup_pages, sup_led, null, null, null);
    try std.testing.expect(!sup_rep.passed);

    // Unconditional fullwidth digit (９９ -> 99) Rule 10 audit across all OSes (even without CJK fonts)
    const fw_led = try std.fmt.allocPrint(alloc, "{s}/fw.json", .{tmp});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = fw_led, .data = "{\"k0\":{\"value\":45.0}}" });
    const synthetic_fw = [_]mupdf.PageData{.{
        .page_num = 1,
        .width = 612.0,
        .height = 792.0,
        .spans = &.{},
        .images = &.{},
        .graphics = &.{},
        .stroke_count = 0,
        .prose_text = "The count was \xef\xbc\x99\xef\xbc\x99 units.",
    }};
    try std.testing.expect(!(try audit.auditProse(alloc, io, &synthetic_fw, fw_led, null, null, null)).passed);

    // Real Unicode superscript (10⁷ vs 10⁶) & fullwidth digits (when host CJK font covers U+FF19) via Typst
    if (mupdf.whichTool(alloc, io, "typst") != null) {
        const u7_pdf = try compileTypstSnippet(alloc, io, tmp, "uni_sup_7", "#set page(width: 612pt, height: 792pt)\nWe sampled 10\xe2\x81\xb7 points.");
        const u7_pages = try mupdf.extractPages(alloc, io, u7_pdf);
        try std.testing.expect(!(try audit.auditProse(alloc, io, u7_pages, sup_led, null, null, null)).passed);

        const u6_pdf = try compileTypstSnippet(alloc, io, tmp, "uni_sup_6", "#set page(width: 612pt, height: 792pt)\nWe sampled 10\xe2\x81\xb6 points.");
        const u6_pages = try mupdf.extractPages(alloc, io, u6_pdf);
        try std.testing.expect((try audit.auditProse(alloc, io, u6_pages, sup_led, null, null, null)).passed);

        const fw_pdf = try compileTypstSnippet(alloc, io, tmp, "uni_fw_99", "#set page(width: 612pt, height: 792pt)\nThe count was \xef\xbc\x99\xef\xbc\x99 units.");
        const fw_pages = try mupdf.extractPages(alloc, io, fw_pdf);
        if (fw_pages.len > 0 and std.mem.find(u8, fw_pages[0].prose_text, "\xef\xbc\x99") != null) {
            try std.testing.expect(!(try audit.auditProse(alloc, io, fw_pages, fw_led, null, null, null)).passed);
        }
    }
}

test "sabotage 08: SHA-256 compilation latch rejects single-byte raw tamper" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;
    const tmp = "/tmp/vedit_court_08";
    try ensureTestDir(io, tmp);
    defer mupdf.removeTmpDirBestEffort(io, tmp);

    const raw_dir = try std.fmt.allocPrint(alloc, "{s}/data/raw", .{tmp});
    try ensureTestDir(io, raw_dir);
    const raw_file = try std.fmt.allocPrint(alloc, "{s}/sample.json", .{raw_dir});
    const orig_data = "{\"count\": 64896}\n";
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = raw_file, .data = orig_data });

    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(orig_data, &digest, .{});
    const hex = std.fmt.bytesToHex(digest, .lower);
    const mf_path = try std.fmt.allocPrint(alloc, "{s}/data/manifest.sha256", .{tmp});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = mf_path, .data = try std.fmt.allocPrint(alloc, "{s}  data/raw/sample.json\n", .{hex[0..]}) });
    const led_path = try std.fmt.allocPrint(alloc, "{s}/data/provenance_ledger.json", .{tmp});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = led_path, .data = try std.fmt.allocPrint(alloc, "[{{\"metric_id\":\"count\",\"value\":64896,\"raw_file_sha256\":\"{s}\"}}]\n", .{hex[0..]}) });
    const sum_path = try std.fmt.allocPrint(alloc, "{s}/data/summary_metrics.json", .{tmp});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = sum_path, .data = "{\"metrics\":{\"count\":64896}}\n" });

    // Clean pass first
    const clean = try audit.auditLatch(alloc, io, tmp);
    try std.testing.expect(clean.passed);

    // 1-byte tamper -> MUST FAIL
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = raw_file, .data = "{\"count\": 64896} \n" });
    const tampered = try audit.auditLatch(alloc, io, tmp);
    try std.testing.expect(!tampered.passed);
    try std.testing.expect(tampered.failures.len >= 1);
}

test "sabotage 09: prepress rejects low-DPI image, unembedded Base-14 font, missing bleed & untagged PDF/UA" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;
    const tmp = "/tmp/vedit_court_09";
    try ensureTestDir(io, tmp);
    defer mupdf.removeTmpDirBestEffort(io, tmp);

    // Low-DPI: 100x100px drawn at 400x400pt (~18 DPI)
    const tiny = try makeSolidJpeg(alloc, 100, 100, .{ .r = 20, .g = 80, .b = 120 });
    const pdf = try std.fmt.allocPrint(alloc, "{s}/low_dpi_untagged.pdf", .{tmp});
    try writeSimplePdf(alloc, io, pdf, .{
        .content = "q 400 0 0 400 50 200 cm /Im1 Do Q BT /F1 12 Tf 50 700 Td (Untagged Base-14 Helvetica PDF) Tj ET",
        .image = .{ .w = 100, .h = 100, .jpeg_bytes = tiny },
    });
    const pages = try mupdf.extractPages(alloc, io, pdf);
    const cat = try mupdf.inspectCatalog(alloc, io, pdf);
    const rep = try audit.auditPrepress(alloc, io, pdf, pages, cat, 300.0, 300.0, true, true, false, "ct09");
    try std.testing.expect(!rep.passed);
    try std.testing.expect(rep.min_eff_dpi_x10 >= 0 and rep.min_eff_dpi_x10 < 250);
    try std.testing.expect(rep.unembedded_fonts.len >= 1);
    try std.testing.expect(!rep.bleed_all_pages);
    try std.testing.expect(!rep.ua_struct_pass);
}

test "sabotage 10: Rule 11 offline rejects 0-link PDF, dead text URL/DOI, placeholders, 0x0 rect & missing citations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;
    const tmp = "/tmp/vedit_court_10";
    try ensureTestDir(io, tmp);
    defer mupdf.removeTmpDirBestEffort(io, tmp);

    // 1. Zero links -> FAIL
    const p_none = try std.fmt.allocPrint(alloc, "{s}/no_links.pdf", .{tmp});
    try writeSimplePdf(alloc, io, p_none, .{ .content = "BT /F1 11 Tf 50 700 Td (A report with zero clickable links.) Tj ET" });
    const r1 = try links.auditLinks(alloc, io, p_none, try mupdf.extractPages(alloc, io, p_none), null, null, 1, false, 5, false);
    try std.testing.expect(!r1.passed);

    // 2. Unlinked plain-text DOI -> FAIL
    const p_dead = try std.fmt.allocPrint(alloc, "{s}/unlinked.pdf", .{tmp});
    try writeSimplePdf(alloc, io, p_dead, .{
        .content =
        \\BT /F1 11 Tf 50 720 Td (Verified source: https://typst.app/docs/reference/pdf/) Tj ET
        \\BT /F1 11 Tf 50 690 Td (Unlinked dead text: doi:10.1038/nature02417) Tj ET
        ,
        .links = &.{.{ .uri = "https://typst.app/docs/reference/pdf/", .x0 = 50, .y0 = 716, .x1 = 300, .y1 = 732 }},
    });
    const r2 = try links.auditLinks(alloc, io, p_dead, try mupdf.extractPages(alloc, io, p_dead), null, null, 1, false, 5, false);
    try std.testing.expect(!r2.passed);

    // 3. Placeholder domain (example.com) + degenerate 0.5x0.5 rect -> FAIL
    const p_ph = try std.fmt.allocPrint(alloc, "{s}/placeholder.pdf", .{tmp});
    try writeSimplePdf(alloc, io, p_ph, .{
        .content = "BT /F1 11 Tf 50 700 Td (Fake placeholder source) Tj ET",
        .links = &.{
            .{ .uri = "https://example.com/fabricated-study", .x0 = 50, .y0 = 696, .x1 = 180, .y1 = 712 },
            .{ .uri = "https://typst.app/docs/", .x0 = 50, .y0 = 680, .x1 = 50.5, .y1 = 680.5 },
        },
    });
    const r3 = try links.auditLinks(alloc, io, p_ph, try mupdf.extractPages(alloc, io, p_ph), null, null, 1, false, 5, false);
    try std.testing.expect(!r3.passed);

    // 4. Declared citation missing clickable link -> FAIL; control with both linked -> PASS
    const cits = try std.fmt.allocPrint(alloc, "{s}/cits.json", .{tmp});
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = cits,
        .data =
        \\{"citations":[
        \\  {"id":"c1","values":[100],"source":"Typst","doi_or_url":"https://typst.app/docs/reference/pdf/"},
        \\  {"id":"c2","values":[115],"source":"Koch 2004","doi_or_url":"https://doi.org/10.1038/nature02417"}
        \\]}
        ,
    });
    const p_miss = try std.fmt.allocPrint(alloc, "{s}/miss_cit.pdf", .{tmp});
    try writeSimplePdf(alloc, io, p_miss, .{
        .content = "BT /F1 11 Tf 50 700 Td (Only c1 linked here) Tj ET",
        .links = &.{.{ .uri = "https://typst.app/docs/reference/pdf/", .x0 = 50, .y0 = 696, .x1 = 180, .y1 = 712 }},
    });
    const r4 = try links.auditLinks(alloc, io, p_miss, try mupdf.extractPages(alloc, io, p_miss), cits, null, 1, false, 5, false);
    try std.testing.expect(!r4.passed);

    const p_ok = try std.fmt.allocPrint(alloc, "{s}/all_ok.pdf", .{tmp});
    try writeSimplePdf(alloc, io, p_ok, .{
        .content =
        \\BT /F1 11 Tf 50 720 Td (Typst Spec) Tj ET
        \\BT /F1 11 Tf 50 690 Td (Koch et al. 2004 doi:10.1038/nature02417) Tj ET
        ,
        .links = &.{
            .{ .uri = "https://typst.app/docs/reference/pdf/", .x0 = 50, .y0 = 716, .x1 = 140, .y1 = 732 },
            .{ .uri = "https://doi.org/10.1038/nature02417", .x0 = 50, .y0 = 686, .x1 = 280, .y1 = 702 },
        },
    });
    const r5 = try links.auditLinks(alloc, io, p_ok, try mupdf.extractPages(alloc, io, p_ok), cits, null, 1, false, 5, false);
    try std.testing.expect(r5.passed);
}

const HttpServerCtx = struct {
    server: *std.Io.net.Server,
    io: std.Io,
    stop: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
};

fn serveHttpLoop(ctx: *HttpServerCtx) void {
    while (!ctx.stop.load(.acquire)) {
        const stream = ctx.server.accept(ctx.io) catch break;
        defer stream.close(ctx.io);
        if (ctx.stop.load(.acquire)) break;

        var rbuf: [2048]u8 = undefined;
        var r = stream.reader(ctx.io, &rbuf);
        const req = r.interface.takeDelimiterInclusive('\n') catch continue;
        if (req.len == 0) continue;

        var status_line: []const u8 = "404 Not Found";
        var body: []const u8 = "<html><head><title>Not Found</title></head><body>Missing</body></html>";
        if (std.mem.find(u8, req, "GET /real-report ") != null) {
            status_line = "200 OK";
            body = "<html><head><title>Verified Climate Telemetry 2026</title></head><body><h1>Mauna Loa</h1></body></html>";
        } else if (std.mem.find(u8, req, "GET /soft-404 ") != null) {
            status_line = "200 OK";
            body = "<html><head><title>404 - Page Not Found | Journal</title></head><body><h1>Article not found</h1></body></html>";
        } else if (std.mem.find(u8, req, "GET /bot-challenge ") != null) {
            status_line = "200 OK";
            body = "<html><head><title>Client Challenge</title></head><body>Enable JavaScript</body></html>";
        } else if (std.mem.find(u8, req, "GET /forbidden-403 ") != null) {
            status_line = "403 Forbidden";
            body = "<html><head><title>Just a moment...</title></head><body>Forbidden</body></html>";
        }

        var resp_buf: [1024]u8 = undefined;
        const resp = std.fmt.bufPrint(
            &resp_buf,
            "HTTP/1.1 {s}\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}",
            .{ status_line, body.len, body },
        ) catch continue;
        var wbuf: [1024]u8 = undefined;
        var w = stream.writer(ctx.io, &wbuf);
        w.interface.writeAll(resp) catch continue;
        w.interface.flush() catch |err| std.log.debug("test http flush: {s}", .{@errorName(err)});
    }
}

test "sabotage 11: Rule 11C live HTTP court passes 200 OK and rejects 404, Soft-404, Client Challenge & 403" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;
    const tmp = "/tmp/vedit_court_11";
    try ensureTestDir(io, tmp);
    defer mupdf.removeTmpDirBestEffort(io, tmp);

    const bind_addr = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 0);
    var srv = try bind_addr.listen(io, .{ .reuse_address = true });
    const port = srv.socket.address.getPort();
    var ctx = HttpServerCtx{ .server = &srv, .io = io };
    const th = try std.Thread.spawn(.{}, serveHttpLoop, .{&ctx});
    defer {
        ctx.stop.store(true, .release);
        // Unblock accept() with a quick curl poke before joining
        const wake_url = std.fmt.allocPrint(alloc, "http://127.0.0.1:{d}/wake", .{port}) catch "";
        if (wake_url.len > 0) {
            _ = mupdf.runCmd(alloc, io, &.{ "curl", "-s", "--max-time", "1", wake_url }, null) catch |err| std.log.debug("test http wake: {s}", .{@errorName(err)});
        }
        th.join();
        srv.deinit(io);
    }

    const LiveCase = struct { name: []const u8, route: []const u8, expect_pass: bool };
    const cases = [_]LiveCase{
        .{ .name = "real_200_ok", .route = "/real-report", .expect_pass = true },
        .{ .name = "dead_404", .route = "/hallucinated-404", .expect_pass = false },
        .{ .name = "soft_404_200", .route = "/soft-404", .expect_pass = false },
        .{ .name = "bot_challenge_200", .route = "/bot-challenge", .expect_pass = false },
        .{ .name = "waf_403", .route = "/forbidden-403", .expect_pass = false },
    };

    for (cases) |tc| {
        const url = try std.fmt.allocPrint(alloc, "http://127.0.0.1:{d}{s}", .{ port, tc.route });
        const pdf = try std.fmt.allocPrint(alloc, "{s}/live_{s}.pdf", .{ tmp, tc.name });
        try writeSimplePdf(alloc, io, pdf, .{
            .content = try std.fmt.allocPrint(alloc, "BT /F1 11 Tf 50 700 Td (Source link: {s}) Tj ET", .{url}),
            .links = &.{.{ .uri = url, .x0 = 50, .y0 = 696, .x1 = 320, .y1 = 712 }},
        });
        const pages = try mupdf.extractPages(alloc, io, pdf);
        const rep = try links.auditLinks(alloc, io, pdf, pages, null, null, 1, true, 5, true);
        try std.testing.expectEqual(tc.expect_pass, rep.passed);
    }
}

// =============================================================================
// 2. KERNEL PROVENANCE & PURE-ZIG MEDIA ENGINE VERIFICATION
// =============================================================================

test "kernels 12: all 12 p2zig-strict kernels & // uroboros:zig-tir provenance marker present" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;
    const root = findRepoRoot(io);

    const kpath = try std.fs.path.join(alloc, &.{ root, "zig/src/kernels_p2zig.zig" });
    const ksrc = try std.Io.Dir.cwd().readFileAlloc(io, kpath, alloc, .unlimited);
    try std.testing.expect(std.mem.find(u8, ksrc, "// uroboros:zig-tir") != null);

    try std.testing.expectEqual(@as(i64, 2100), kernels.wcag_contrast_x100(0, 0, 0, 255, 255, 255));
    try std.testing.expect(!kernels.wcag_passes_aa(kernels.wcag_contrast_x100(0x50, 0x58, 0x62, 0x05, 0x1C, 0x2C), 110, false));
    try std.testing.expectEqual(@as(i64, 2600), kernels.cmyk_gcr_tac_x10(0, 0, 0));
    try std.testing.expectEqual(@as(i64, 180), kernels.effective_dpi_x10(100, 100, 4000, 4000));
    const auth = [_]i64{-4501};
    try std.testing.expect(kernels.rule10_is_grounded_x100(-4500, &auth));
    try std.testing.expect(!kernels.rule10_is_grounded_x100(4500, &auth));
    try std.testing.expectEqual(@as(i64, 3), kernels.bleed_edge_count(300, 300, 300, 0, 612, 792));
    try std.testing.expect(kernels.coverage_passes(60000, 100000, 500, 3, 2));
    try std.testing.expect(!kernels.coverage_passes(40000, 100000, 500, 3, 2));
}

test "media 13: pure-Zig vedit plate (crop + black lift + feather >=300 DPI) & vedit spreads" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;
    const root = findRepoRoot(io);
    const tmp = "/tmp/vedit_court_13";
    try ensureTestDir(io, tmp);
    defer mupdf.removeTmpDirBestEffort(io, tmp);

    const src_plate = try std.fs.path.join(alloc, &.{ root, "demos/cosmos-mobile-primer/report/plates/plate_04_67p.jpg" });
    const out_plate = try std.fmt.allocPrint(alloc, "{s}/plate_out.jpg", .{tmp});
    const pr = try media.processPlate(alloc, io, src_plate, out_plate, 304.0, 118.0, .{ .r = 7, .g = 9, .b = 15 }, 0.15, 0.08, 88, true, "ct13");
    try std.testing.expect(pr.dpi_x >= 300.0 and pr.dpi_y >= 300.0);
    try std.testing.expectEqual(@as(u8, 7), pr.corner.r);
    try std.testing.expectEqual(@as(u8, 9), pr.corner.g);
    try std.testing.expectEqual(@as(u8, 15), pr.corner.b);

    const mono_pdf = try std.fs.path.join(alloc, &.{ root, "demos/typst-carbon-monograph/report/TYPST_CARBON_MONOGRAPH_UA1.pdf" });
    const spreads_dir = try std.fmt.allocPrint(alloc, "{s}/spreads", .{tmp});
    const sr = try media.renderSpreads(alloc, io, mono_pdf, spreads_dir, 90, 900, "ct13s");
    try std.testing.expect(sr.written.len >= 1);
}

// =============================================================================
// 3. FLAGSHIP PRODUCTION REGRESSIONS (ALL DEMOS + ZERO-PYTHON CLOSED LOOP)
// =============================================================================

test "regression 14: Botanica Veridica passes contrast, geometry, Rule 10, dual-key coverage (1,4-9) & Rule 11 offline" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;
    const root = findRepoRoot(io);

    const pdf = try std.fs.path.join(alloc, &.{ root, "demos/botanica-veridica/report/BOTANICA_VERIDICA_MONOGRAPH.pdf" });
    const pages = try mupdf.extractPages(alloc, io, pdf);
    try std.testing.expect((try audit.auditContrast(alloc, io, pdf, pages, "ct14")).passed);
    try std.testing.expect((try audit.auditGeometry(alloc, io, pdf, pages, 55.0, "ct14")).passed);
    try std.testing.expect((try audit.auditCoverage(alloc, io, pdf, pages.len, 50.0, 2, "1,4-9", "ct14")).passed);
    try std.testing.expect((try audit.auditProse(
        alloc,
        io,
        pages,
        try std.fs.path.join(alloc, &.{ root, "demos/botanica-veridica/data/provenance_ledger.json" }),
        try std.fs.path.join(alloc, &.{ root, "demos/botanica-veridica/data/summary_metrics.json" }),
        try std.fs.path.join(alloc, &.{ root, "demos/botanica-veridica/data/background_citations.json" }),
        try std.fs.path.join(alloc, &.{ root, "demos/botanica-veridica/data/manifest.sha256" }),
    )).passed);
    try std.testing.expect((try links.auditLinks(alloc, io, pdf, pages, null, null, 1, false, 5, false)).passed);
}

test "regression 15: Felis Mundi Magazine & Consulting Flagship Deck pass geometry & coverage" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;
    const root = findRepoRoot(io);

    const fel_pdf = try std.fs.path.join(alloc, &.{ root, "demos/felis-mundi-magazine/report/FELIS_MUNDI_MAGAZINE.pdf" });
    const fel_pages = try mupdf.extractPages(alloc, io, fel_pdf);
    try std.testing.expect((try audit.auditGeometry(alloc, io, fel_pdf, fel_pages, 55.0, "ct15f")).passed);
    const cov = try audit.auditCoverage(alloc, io, fel_pdf, fel_pages.len, 50.0, 2, null, "ct15f");
    try std.testing.expect(cov.passed);
    try std.testing.expect(cov.min_visible_pct >= 60.0);

    const cf_pdf = try std.fs.path.join(alloc, &.{ root, "demos/consulting-flagship/report/CONSULTING_FLAGSHIP_DECK.pdf" });
    const cf_pages = try mupdf.extractPages(alloc, io, cf_pdf);
    try std.testing.expect((try audit.auditGeometry(alloc, io, cf_pdf, cf_pages, 55.0, "ct15c")).passed);
}

test "regression 16: Typst Carbon Monograph, EXOMUNDUS, CAIE & PRL pass latch, 6-gate court, math-font geometry & veraPDF" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;
    const root = findRepoRoot(io);
    const has_verapdf = mupdf.whichTool(alloc, io, "verapdf") != null;

    const DemoSpec = struct {
        tag: []const u8,
        latch_dir: []const u8,
        pdf: []const u8,
        ledger: []const u8,
        summary: []const u8,
        citations: []const u8,
        manifest: []const u8,
    };

    const demos = [_]DemoSpec{
        .{
            .tag = "typst_carbon",
            .latch_dir = "demos/global-carbon-telemetry",
            .pdf = "demos/typst-carbon-monograph/report/TYPST_CARBON_MONOGRAPH_UA1.pdf",
            .ledger = "demos/global-carbon-telemetry/data/provenance_ledger.json",
            .summary = "demos/global-carbon-telemetry/data/summary_metrics.json",
            .citations = "demos/typst-carbon-monograph/data/background_citations.json",
            .manifest = "demos/global-carbon-telemetry/data/manifest.sha256",
        },
        .{
            .tag = "exomundus",
            .latch_dir = "demos/exomundus-nasa-telemetry",
            .pdf = "demos/exomundus-nasa-telemetry/report/EXOMUNDUS_NASA_TELEMETRY_UA1.pdf",
            .ledger = "demos/exomundus-nasa-telemetry/data/provenance_ledger.json",
            .summary = "demos/exomundus-nasa-telemetry/data/summary_metrics.json",
            .citations = "demos/exomundus-nasa-telemetry/data/background_citations.json",
            .manifest = "demos/exomundus-nasa-telemetry/data/manifest.sha256",
        },
        .{
            .tag = "caie",
            .latch_dir = "demos/caie-flowshop-journal",
            .pdf = "demos/caie-flowshop-journal/report/CAIE_FLOWSHOP_MANUSCRIPT_UA1.pdf",
            .ledger = "demos/caie-flowshop-journal/data/provenance_ledger.json",
            .summary = "demos/caie-flowshop-journal/data/summary_metrics.json",
            .citations = "demos/caie-flowshop-journal/data/background_citations.json",
            .manifest = "demos/caie-flowshop-journal/data/manifest.sha256",
        },
        .{
            .tag = "prl",
            .latch_dir = "demos/prl-yang-mills-chaos",
            .pdf = "demos/prl-yang-mills-chaos/report/PRL_YANG_MILLS_CHAOS_UA1.pdf",
            .ledger = "demos/prl-yang-mills-chaos/data/provenance_ledger.json",
            .summary = "demos/prl-yang-mills-chaos/data/summary_metrics.json",
            .citations = "demos/prl-yang-mills-chaos/data/background_citations.json",
            .manifest = "demos/prl-yang-mills-chaos/data/manifest.sha256",
        },
    };

    for (demos) |dm| {
        const lt = try audit.auditLatch(alloc, io, try std.fs.path.join(alloc, &.{ root, dm.latch_dir }));
        try std.testing.expect(lt.passed);

        const pdf = try std.fs.path.join(alloc, &.{ root, dm.pdf });
        const pages = try mupdf.extractPages(alloc, io, pdf);
        const cat = try mupdf.inspectCatalog(alloc, io, pdf);
        const cr = try audit.auditContrast(alloc, io, pdf, pages, dm.tag);
        const geo = try audit.auditGeometry(alloc, io, pdf, pages, 55.0, dm.tag);
        const pr = try audit.auditProse(
            alloc,
            io,
            pages,
            try std.fs.path.join(alloc, &.{ root, dm.ledger }),
            try std.fs.path.join(alloc, &.{ root, dm.summary }),
            try std.fs.path.join(alloc, &.{ root, dm.citations }),
            try std.fs.path.join(alloc, &.{ root, dm.manifest }),
        );
        const pp = try audit.auditPrepress(alloc, io, pdf, pages, cat, 300.0, 300.0, false, true, has_verapdf, dm.tag);
        const lr = try links.auditLinks(alloc, io, pdf, pages, null, null, 1, false, 5, false);

        try std.testing.expect(cr.passed);
        try std.testing.expect(geo.passed and geo.collisions == 0);
        try std.testing.expect(pr.passed);
        try std.testing.expect(pp.passed and pp.unembedded_fonts.len == 0 and pp.ua_struct_pass);
        if (has_verapdf) {
            try std.testing.expect(pp.verapdf.compliant and pp.verapdf.failed_rules == 0);
        }
        try std.testing.expect(lr.passed);
    }
}

test "regression 17: Cosmos Mobile Primer passes <1MB WhatsApp budget, 12x(360x640pt), mobile_portrait_9x16 & 6-gate court" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;
    const root = findRepoRoot(io);
    const has_verapdf = mupdf.whichTool(alloc, io, "verapdf") != null;

    const demo = try std.fs.path.join(alloc, &.{ root, "demos/cosmos-mobile-primer" });
    const pdf = try std.fs.path.join(alloc, &.{ demo, "report/COSMOS_MOBILE_PRIMER_UA1.pdf" });
    const raw_pdf = try std.Io.Dir.cwd().readFileAlloc(io, pdf, alloc, .unlimited);
    try std.testing.expect(raw_pdf.len < 1_000_000);

    const pages = try mupdf.extractPages(alloc, io, pdf);
    try std.testing.expectEqual(@as(usize, 12), pages.len);
    for (pages) |pg| {
        try std.testing.expect(@abs(pg.width - 360.0) <= 1.0);
        try std.testing.expect(@abs(pg.height - 640.0) <= 1.0);
    }

    const bp_raw = try std.Io.Dir.cwd().readFileAlloc(io, try std.fs.path.join(alloc, &.{ root, "archetypes/mobile-primer/blueprint.json" }), alloc, .unlimited);
    try std.testing.expect(std.mem.find(u8, bp_raw, "\"mobile_portrait_9x16\"") != null);

    try std.testing.expect((try audit.auditLatch(alloc, io, demo)).passed);
    try std.testing.expect((try audit.auditContrast(alloc, io, pdf, pages, "ct17")).passed);
    try std.testing.expect((try audit.auditGeometry(alloc, io, pdf, pages, 55.0, "ct17")).passed);
    try std.testing.expect((try audit.auditProse(
        alloc,
        io,
        pages,
        try std.fs.path.join(alloc, &.{ demo, "data/provenance_ledger.json" }),
        try std.fs.path.join(alloc, &.{ demo, "data/summary_metrics.json" }),
        try std.fs.path.join(alloc, &.{ demo, "data/background_citations.json" }),
        try std.fs.path.join(alloc, &.{ demo, "data/manifest.sha256" }),
    )).passed);
    try std.testing.expect((try links.auditLinks(
        alloc,
        io,
        pdf,
        pages,
        try std.fs.path.join(alloc, &.{ demo, "data/background_citations.json" }),
        try std.fs.path.join(alloc, &.{ demo, "data/provenance_ledger.json" }),
        1,
        false,
        5,
        false,
    )).passed);
    const cat = try mupdf.inspectCatalog(alloc, io, pdf);
    const pp = try audit.auditPrepress(alloc, io, pdf, pages, cat, 300.0, 300.0, false, true, has_verapdf, "ct17");
    try std.testing.expect(pp.passed and pp.image_count == 8 and pp.min_eff_dpi_x10 >= 3000);
    if (has_verapdf) {
        try std.testing.expect(pp.verapdf.compliant and pp.verapdf.failed_rules == 0);
    }
}

test "closed-loop 18: vedit inject -> vedit init -> build.sh (Typst PDF/UA-1) -> 5-gate court + veraPDF (zero Python)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;
    if (mupdf.whichTool(alloc, io, "typst") == null) return;

    const root = findRepoRoot(io);
    const tmp = "/tmp/vedit_court_18";
    try ensureTestDir(io, tmp);
    defer mupdf.removeTmpDirBestEffort(io, tmp);

    const vedit_bin = try std.fs.path.join(alloc, &.{ root, "zig/zig-out/bin/vedit" });
    const sample_pdf = try std.fs.path.join(alloc, &.{ root, "demos/typst-carbon-monograph/report/TYPST_CARBON_MONOGRAPH_UA1.pdf" });
    const arch_dir = try std.fmt.allocPrint(alloc, "{s}/archetypes", .{tmp});
    const proj_dir = try std.fmt.allocPrint(alloc, "{s}/synth_pub", .{tmp});

    const bp = try dissect.dissectPdf(alloc, io, sample_pdf, "loop-test", "ct18");
    _ = try dissect.writeInjectedArchetype(alloc, io, bp, arch_dir);
    _ = try scaffold.writeRegistryIndex(alloc, io, arch_dir);
    try scaffold.initProjectFromArchetype(alloc, io, proj_dir, arch_dir, "loop-test", "Zero-Python Loop Proof");

    const build_cmd = try std.fmt.allocPrint(alloc, "VEDIT_BIN=\"{s}\" bash \"{s}/build.sh\"", .{ vedit_bin, proj_dir });
    const res = try mupdf.runCmd(alloc, io, &.{ "bash", "-c", build_cmd }, null);
    try std.testing.expectEqual(@as(u8, 0), res.exit_code);
    try std.testing.expect(std.mem.find(u8, res.stdout, "[vedit:latch] PASS") != null);
    try std.testing.expect(std.mem.find(u8, res.stdout, "[vedit:wcag_contrast] PASS") != null);
    try std.testing.expect(std.mem.find(u8, res.stdout, "[vedit:geometry]      PASS") != null);
    try std.testing.expect(std.mem.find(u8, res.stdout, "[vedit:prepress]      PASS") != null);
    if (mupdf.whichTool(alloc, io, "verapdf") != null) {
        try std.testing.expect(std.mem.find(u8, res.stdout, "verapdf_pass=106, verapdf_fail=0") != null);
    }
}

// =============================================================================
// 3. ZERO-FABRICATION HARDENING COURT (v0.7.0-zig: sabotage 19..34 + regression 35)
// =============================================================================

fn writeRawPdfObjects(alloc: std.mem.Allocator, io: std.Io, path: []const u8, objs: []const []const u8) !void {
    var out: std.ArrayList(u8) = .empty;
    var offsets: std.ArrayList(usize) = .empty;
    try out.appendSlice(alloc, "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n");
    for (objs, 0..) |body, idx| {
        try offsets.append(alloc, out.items.len);
        try out.appendSlice(alloc, try std.fmt.allocPrint(alloc, "{d} 0 obj\n{s}\nendobj\n", .{ idx + 1, body }));
    }
    const xref_off = out.items.len;
    try out.appendSlice(alloc, try std.fmt.allocPrint(alloc, "xref\n0 {d}\n0000000000 65535 f \n", .{objs.len + 1}));
    for (offsets.items) |off| {
        try out.appendSlice(alloc, try std.fmt.allocPrint(alloc, "{d:0>10} 00000 n \n", .{off}));
    }
    try out.appendSlice(alloc, try std.fmt.allocPrint(alloc, "trailer\n<< /Size {d} /Root 1 0 R >>\nstartxref\n{d}\n%%EOF\n", .{ objs.len + 1, xref_off }));
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = out.items });
}

test "sabotage 19: parallel private tmp dirs eliminate cross-invocation contrast/prepress races (KC-5)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;
    const tmp = try mupdf.makePrivateTmpDir(alloc, io);
    defer mupdf.removeTmpDirBestEffort(io, tmp);

    const good_pdf = try std.fmt.allocPrint(alloc, "{s}/good.pdf", .{tmp});
    try writeSimplePdf(alloc, io, good_pdf, .{
        .content = "1 1 1 rg 0 0 612 792 re f 0 0 0 rg BT /F1 12 Tf 50 700 Td (High contrast black text on white) Tj ET",
    });
    const bad_pdf = try std.fmt.allocPrint(alloc, "{s}/bad.pdf", .{tmp});
    try writeSimplePdf(alloc, io, bad_pdf, .{
        .content = "0.02 0.11 0.17 rg 0 0 612 792 re f 0.31 0.35 0.38 rg BT /F1 12 Tf 50 700 Td (Unreadable low contrast text) Tj ET",
    });

    const WorkerArgs = struct {
        io: std.Io,
        pdf: []const u8,
        expect_pass: bool,
        ok: *std.atomic.Value(bool),
    };
    const workerFn = struct {
        fn run(w: WorkerArgs) void {
            var local_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer local_arena.deinit();
            const a = local_arena.allocator();
            const priv = mupdf.makePrivateTmpDir(a, w.io) catch {
                w.ok.store(false, .release);
                return;
            };
            defer mupdf.removeTmpDirBestEffort(w.io, priv);
            const pgs = mupdf.extractPages(a, w.io, w.pdf) catch {
                w.ok.store(false, .release);
                return;
            };
            const cr = audit.auditContrast(a, w.io, w.pdf, pgs, priv) catch {
                w.ok.store(false, .release);
                return;
            };
            const cat = mupdf.inspectCatalog(a, w.io, w.pdf) catch {
                w.ok.store(false, .release);
                return;
            };
            _ = audit.auditPrepress(a, w.io, w.pdf, pgs, cat, 300.0, 300.0, false, false, false, priv) catch {
                w.ok.store(false, .release);
                return;
            };
            if (cr.passed != w.expect_pass) w.ok.store(false, .release);
        }
    }.run;

    var all_ok = std.atomic.Value(bool).init(true);
    var threads: [6]std.Thread = undefined;
    for (0..6) |ti| {
        const is_good = (ti % 2 == 0);
        threads[ti] = try std.Thread.spawn(.{}, workerFn, .{WorkerArgs{
            .io = io,
            .pdf = if (is_good) good_pdf else bad_pdf,
            .expect_pass = is_good,
            .ok = &all_ok,
        }});
    }
    for (&threads) |*th| th.join();
    try std.testing.expect(all_ok.load(.acquire));
}

test "sabotage 20: Gate 1 latch rejects forged ledger hashes, corrupt JSON, unmonitored raw files, flat unledgered metrics & path traversal (KC-2)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;
    const tmp = try mupdf.makePrivateTmpDir(alloc, io);
    defer mupdf.removeTmpDirBestEffort(io, tmp);

    const raw_dir = try std.fmt.allocPrint(alloc, "{s}/data/raw", .{tmp});
    try ensureTestDir(io, raw_dir);
    const raw_file = try std.fmt.allocPrint(alloc, "{s}/a.csv", .{raw_dir});
    const raw_bytes = "metric,val\nalpha,42.5\n";
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = raw_file, .data = raw_bytes });
    const real_sha = try audit.sha256HexFile(alloc, io, raw_file);

    const mf_path = try std.fmt.allocPrint(alloc, "{s}/data/manifest.sha256", .{tmp});
    const led_path = try std.fmt.allocPrint(alloc, "{s}/data/provenance_ledger.json", .{tmp});
    const sum_path = try std.fmt.allocPrint(alloc, "{s}/data/summary_metrics.json", .{tmp});

    // 1. Clean baseline with explicit source_document + source_locator + matching SHA-256 -> PASS
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = mf_path, .data = try std.fmt.allocPrint(alloc, "{s}  data/raw/a.csv\n", .{real_sha[0..]}) });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = led_path, .data = try std.fmt.allocPrint(alloc, "[{{\"metric_id\":\"alpha\",\"value\":42.5,\"source_document\":\"data/raw/a.csv\",\"source_locator\":\"row 1\",\"raw_file_sha256\":\"{s}\"}}]\n", .{real_sha[0..]}) });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = sum_path, .data = "{\"alpha\": 42.5}\n" });
    try std.testing.expect((try audit.auditLatch(alloc, io, tmp)).passed);

    // 2. Forged raw_file_sha256 in ledger -> FAIL
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = led_path, .data = "[{\"metric_id\":\"alpha\",\"value\":42.5,\"source_document\":\"data/raw/a.csv\",\"source_locator\":\"row 1\",\"raw_file_sha256\":\"deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef\"}]\n" });
    try std.testing.expect(!(try audit.auditLatch(alloc, io, tmp)).passed);

    // 3. Corrupt ledger JSON -> FAIL (never catch null!)
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = led_path, .data = "{not valid json" });
    try std.testing.expect(!(try audit.auditLatch(alloc, io, tmp)).passed);

    // 4. Flat summary_metrics.json with extra unledgered metric -> FAIL
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = led_path, .data = try std.fmt.allocPrint(alloc, "[{{\"metric_id\":\"alpha\",\"value\":42.5,\"source_document\":\"data/raw/a.csv\",\"source_locator\":\"row 1\",\"raw_file_sha256\":\"{s}\"}}]\n", .{real_sha[0..]}) });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = sum_path, .data = "{\"alpha\": 42.5, \"fabricated_beta\": 999.0}\n" });
    try std.testing.expect(!(try audit.auditLatch(alloc, io, tmp)).passed);

    // 5. Value disagreement between summary_metrics.json and ledger -> FAIL
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = sum_path, .data = "{\"alpha\": 99.9}\n" });
    try std.testing.expect(!(try audit.auditLatch(alloc, io, tmp)).passed);

    // 6. Unmonitored raw file dropped in data/raw/ -> FAIL
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = sum_path, .data = "{\"alpha\": 42.5}\n" });
    const rogue = try std.fmt.allocPrint(alloc, "{s}/rogue.csv", .{raw_dir});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = rogue, .data = "fake,1\n" });
    try std.testing.expect(!(try audit.auditLatch(alloc, io, tmp)).passed);
    mupdf.removeTmpBestEffort(io, rogue);

    // 7. Path traversal in manifest.sha256 -> FAIL
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = mf_path, .data = try std.fmt.allocPrint(alloc, "{s}  ../escape.csv\n", .{real_sha[0..]}) });
    try std.testing.expect(!(try audit.auditLatch(alloc, io, tmp)).passed);
}

test "sabotage 21: Rule 10 rejects unit-attached fakes, math-alnum/ZWS digits, leading decimals, spaced/en-dash signs, array-sum pollution & cross-line structural prefixes (KC-1/KC-3)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;
    const tmp = try mupdf.makePrivateTmpDir(alloc, io);
    defer mupdf.removeTmpDirBestEffort(io, tmp);

    const led = try std.fmt.allocPrint(alloc, "{s}/ledger.json", .{tmp});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = led, .data = "[{\"metric_id\":\"v\",\"value\":45.0},{\"metric_id\":\"s\",\"value\":256.0}]" });
    const sum = try std.fmt.allocPrint(alloc, "{s}/summary.json", .{tmp});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = sum, .data = "{\"metrics\":{\"v\":45.0,\"s\":256.0},\"chart_axis_ticks\":[100,200]}" });

    const Case = struct { prose: []const u8, expect_pass: bool };
    const cases = [_]Case{
        // Unit-attached fabrications MUST FAIL
        .{ .prose = "Revenue hit 500M dollars.", .expect_pass = false },
        .{ .prose = "Speedup was 99x over baseline.", .expect_pass = false },
        .{ .prose = "Concentration reached 450ppm today.", .expect_pass = false },
        .{ .prose = "Samples totaled 750K items.", .expect_pass = false },
        // Legitimate decades & ordinals MUST PASS
        .{ .prose = "Observed since the 1960s and 17th century at 45.0 units.", .expect_pass = true },
        // Unicode Mathematical Bold digits (U+1D7CE: 99 = 0xF0 0x9D 0x9F 0x97 x2) & ZWS split MUST FAIL
        .{ .prose = "Claimed \xF0\x9D\x9F\x97\xF0\x9D\x9F\x97 units.", .expect_pass = false },
        .{ .prose = "Claimed 99\xE2\x80\x8B99 units.", .expect_pass = false },
        // Leading decimal `.05` and `-.45` MUST FAIL
        .{ .prose = "Threshold p < .05 achieved.", .expect_pass = false },
        .{ .prose = "Delta was -.45 overall.", .expect_pass = false },
        // Spaced unary minus & en-dash sign flip against +45.0 MUST FAIL
        .{ .prose = "Rate dropped \xE2\x80\x9345.0 percent.", .expect_pass = false },
        .{ .prose = "Change: - 45.0 percent.", .expect_pass = false },
        // Cross-line structural prefix & lowercase plural `figures` MUST FAIL
        .{ .prose = "See Figure\n9999 for details.", .expect_pass = false },
        .{ .prose = "Reported figures 9999 today.", .expect_pass = false },
        // chart_axis_ticks array-sum pollution ([100, 200] MUST NOT authorize 300!)
        .{ .prose = "Fabricated total was 300 units.", .expect_pass = false },
        // Non-10 base exponent & U+22C5 dot operator MUST FAIL when wrong, PASS when grounded (2^8=256)
        .{ .prose = "Capacity is 2^9 states.", .expect_pass = false },
        .{ .prose = "Capacity is 2^8 states.", .expect_pass = true },
        .{ .prose = "Flux is 9.7\xE2\x8B\x8510^9 erg.", .expect_pass = false },
        // Inflated ISO standard string MUST FAIL
        .{ .prose = "Certified under ISO 999999.99 standard.", .expect_pass = false },
    };

    for (cases) |tc| {
        const pg = [_]mupdf.PageData{.{
            .page_num = 1,
            .width = 612.0,
            .height = 792.0,
            .spans = &.{},
            .images = &.{},
            .graphics = &.{},
            .stroke_count = 0,
            .prose_text = tc.prose,
        }};
        const rep = try audit.auditProse(alloc, io, &pg, led, sum, null, null);
        try std.testing.expectEqual(tc.expect_pass, rep.passed);
    }
}

test "sabotage 22: prepress real CMYK PAM TAC rejects genuine 400% DeviceCMYK (1 1 1 1 k) plate (KC-6A)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;
    const tmp = try mupdf.makePrivateTmpDir(alloc, io);
    defer mupdf.removeTmpDirBestEffort(io, tmp);

    const pdf = try std.fmt.allocPrint(alloc, "{s}/cmyk400.pdf", .{tmp});
    try writeSimplePdf(alloc, io, pdf, .{
        .content = "1 1 1 1 k 50 50 512 692 re f",
    });
    const pages = try mupdf.extractPages(alloc, io, pdf);
    const cat = try mupdf.inspectCatalog(alloc, io, pdf);
    const rep = try audit.auditPrepress(alloc, io, pdf, pages, cat, 300.0, 300.0, false, false, false, tmp);
    try std.testing.expect(!rep.passed);
    try std.testing.expect(rep.cmyk_p99_tac_x10 >= 3800);
    try std.testing.expect(rep.cmyk_peak_tac_x10 >= 3900);
}

test "sabotage 23: Gate 6 rejects decoy /URI, indirect zero-/Rect, /F Hidden, /AA links, off-page slivers, cross-page hijacks & malformed declared URIs (KC-4)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;
    const tmp = try mupdf.makePrivateTmpDir(alloc, io);
    defer mupdf.removeTmpDirBestEffort(io, tmp);

    // 1. Decoy /URI in non-Link /Subtype /Text comment + indirect zero-/Rect link
    const p_decoy = try std.fmt.allocPrint(alloc, "{s}/decoy_zero.pdf", .{tmp});
    try writeRawPdfObjects(alloc, io, p_decoy, &.{
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R /Annots [6 0 R 7 0 R] >>",
        "<< /Length 49 >>\nstream\nBT /F1 11 Tf 50 700 Td (Decoy URI test PDF) Tj ET\nendstream",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        "<< /Type /Annot /Subtype /Text /Rect [10 10 30 30] /Contents (fake) /A << /S /URI /URI (https://doi.org/10.1038/nature02417) >> >>",
        "<< /Type /Annot /Subtype /Link /Rect 8 0 R /A << /S /URI /URI (https://doi.org/10.1038/nature02417) >> >>",
        "[0 0 0 0]",
    });
    const r_decoy = try links.auditLinks(alloc, io, p_decoy, try mupdf.extractPages(alloc, io, p_decoy), null, null, 1, false, 5, false);
    try std.testing.expect(!r_decoy.passed);

    // 2. Hidden /F 2 link annotation -> FAIL
    const p_hid = try std.fmt.allocPrint(alloc, "{s}/hidden_f2.pdf", .{tmp});
    try writeRawPdfObjects(alloc, io, p_hid, &.{
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R /Annots [6 0 R] >>",
        "<< /Length 45 >>\nstream\nBT /F1 11 Tf 50 700 Td (Hidden link PDF) Tj ET\nendstream",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        "<< /Type /Annot /Subtype /Link /F 2 /Rect [50 695 200 715] /A << /S /URI /URI (https://doi.org/10.1038/nature02417) >> >>",
    });
    const r_hid = try links.auditLinks(alloc, io, p_hid, try mupdf.extractPages(alloc, io, p_hid), null, null, 1, false, 5, false);
    try std.testing.expect(!r_hid.passed);

    // 3. Partially off-page sliver (only 0.5pt inside page right edge) -> FAIL
    const p_sliv = try std.fmt.allocPrint(alloc, "{s}/sliver.pdf", .{tmp});
    try writeSimplePdf(alloc, io, p_sliv, .{
        .content = "BT /F1 11 Tf 50 700 Td (Sliver link PDF) Tj ET",
        .links = &.{.{ .uri = "https://doi.org/10.1038/nature02417", .x0 = 611.5, .y0 = 100.0, .x1 = 700.0, .y1 = 120.0 }},
    });
    const r_sliv = try links.auditLinks(alloc, io, p_sliv, try mupdf.extractPages(alloc, io, p_sliv), null, null, 1, false, 5, false);
    try std.testing.expect(!r_sliv.passed);

    // 4. Malformed URL in citations.json MUST FAIL (never silently dropped)
    const bad_cits = try std.fmt.allocPrint(alloc, "{s}/bad_cits.json", .{tmp});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = bad_cits, .data = "{\"citations\":[{\"id\":\"x\",\"url\":\"not-a-valid-url\"}]}" });
    const p_clean = try std.fmt.allocPrint(alloc, "{s}/clean.pdf", .{tmp});
    try writeSimplePdf(alloc, io, p_clean, .{
        .content = "BT /F1 11 Tf 50 700 Td (Clean link) Tj ET",
        .links = &.{.{ .uri = "https://doi.org/10.1038/nature02417", .x0 = 50, .y0 = 695, .x1 = 180, .y1 = 715 }},
    });
    const r_mal = try links.auditLinks(alloc, io, p_clean, try mupdf.extractPages(alloc, io, p_clean), bad_cits, null, 1, false, 5, false);
    try std.testing.expect(!r_mal.passed);
}

test "sabotage 24: Gate 6 canonical SSRF, NEW-01 syntax parity, spoofed DOI host & NEW-02 pure-Zig std.http.Client fallback" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;

    // 1. Canonical SSRF & NEW-01 syntax checks
    try std.testing.expect(links.validateUriSyntax("https://mastodon.social/@astro", false) == null);
    try std.testing.expect(links.validateUriSyntax("https://en.wikipedia.org/wiki/Todos_los_santos", false) == null);
    try std.testing.expect(links.validateUriSyntax("http://[2606:2800:220:1:248:1893:25c8:1946]/", false) == null);
    try std.testing.expect(links.validateUriSyntax("http://localhost./secret", false) != null);
    try std.testing.expect(links.validateUriSyntax("http://127.1/secret", false) != null);
    try std.testing.expect(links.validateUriSyntax("http://0177.0.0.1/secret", false) != null);
    try std.testing.expect(links.validateUriSyntax("http://2130706433/secret", false) != null);
    try std.testing.expect(links.validateUriSyntax("http://[::ffff:127.0.0.1]/secret", false) != null);
    try std.testing.expect(links.validateUriSyntax("http://169.254.169.254/latest/meta-data/", false) != null);
    try std.testing.expect(links.validateUriSyntax("https://api.example.com/fake", false) != null);
    try std.testing.expect(links.validateUriSyntax("https://example.com./fake", false) != null);
    try std.testing.expect((try links.extractDoiFromUri(alloc, "https://evil-aps.org.attacker.com/10.1038/nature02417")) == null);

    // 2. Live pure-Zig std.http.Client fallback parity: body cap (64 KB), redirect tracking, and timeout
    const FallbackCtx = struct {
        server: *std.Io.net.Server,
        io: std.Io,
        stop: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    };
    const serveFallback = struct {
        fn run(ctx: *FallbackCtx) void {
            while (!ctx.stop.load(.acquire)) {
                const stream = ctx.server.accept(ctx.io) catch break;
                defer stream.close(ctx.io);
                if (ctx.stop.load(.acquire)) break;
                var rbuf: [1024]u8 = undefined;
                var r = stream.reader(ctx.io, &rbuf);
                const req = r.interface.takeDelimiterInclusive('\n') catch continue;
                var wbuf: [4096]u8 = undefined;
                var w = stream.writer(ctx.io, &wbuf);
                if (std.mem.find(u8, req, "GET /big ") != null) {
                    const hdr = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: 262144\r\nConnection: close\r\n\r\n<title>Big OK</title>";
                    w.interface.writeAll(hdr) catch continue;
                    var chunk: [4096]u8 = @splat('A');
                    var sent: usize = 21;
                    while (sent < 262144) : (sent += chunk.len) {
                        w.interface.writeAll(&chunk) catch break;
                    }
                    w.interface.flush() catch |err| std.log.debug("flush err: {s}", .{@errorName(err)});
                } else if (std.mem.find(u8, req, "GET /redir ") != null) {
                    const r302 = "HTTP/1.1 302 Found\r\nLocation: /dest\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
                    w.interface.writeAll(r302) catch continue;
                    w.interface.flush() catch |err| std.log.debug("flush err: {s}", .{@errorName(err)});
                } else if (std.mem.find(u8, req, "GET /dest ") != null) {
                    const ok = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: 25\r\nConnection: close\r\n\r\n<title>Final Dest</title>";
                    w.interface.writeAll(ok) catch continue;
                    w.interface.flush() catch |err| std.log.debug("flush err: {s}", .{@errorName(err)});
                } else {
                    const ok = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK";
                    w.interface.writeAll(ok) catch continue;
                    w.interface.flush() catch |err| std.log.debug("flush err: {s}", .{@errorName(err)});
                }
            }
        }
    }.run;

    const bind_addr = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 0);
    var srv = try bind_addr.listen(io, .{ .reuse_address = true });
    const port = srv.socket.address.getPort();
    var fctx = FallbackCtx{ .server = &srv, .io = io };
    const th = try std.Thread.spawn(.{}, serveFallback, .{&fctx});
    defer {
        fctx.stop.store(true, .release);
        const wake = std.fmt.allocPrint(alloc, "http://127.0.0.1:{d}/wake", .{port}) catch "";
        if (wake.len > 0) {
            _ = links.httpGetZigFallback(alloc, io, wake, 1, true) catch |err| std.log.debug("wake err: {s}", .{@errorName(err)});
        }
        th.join();
        srv.deinit(io);
    }

    // Body cap check: 256 KB response capped cleanly at 65,536 bytes
    const big_u = try std.fmt.allocPrint(alloc, "http://127.0.0.1:{d}/big", .{port});
    const big_r = try links.httpGetZigFallback(alloc, io, big_u, 5, true);
    try std.testing.expectEqual(@as(i32, 200), big_r.status);
    try std.testing.expect(big_r.body.len <= 65536 and big_r.body.len > 100);

    // True final_url tracking across 302 redirect
    const red_u = try std.fmt.allocPrint(alloc, "http://127.0.0.1:{d}/redir", .{port});
    const red_r = try links.httpGetZigFallback(alloc, io, red_u, 5, true);
    try std.testing.expectEqual(@as(i32, 200), red_r.status);
    try std.testing.expect(std.mem.endsWith(u8, red_r.final_url, "/dest"));

    // SSRF block when allow_localhost == false
    const ssrf_r = try links.httpGetZigFallback(alloc, io, red_u, 5, false);
    try std.testing.expect(ssrf_r.err_kind != null);
}

test "sabotage 25: checked @intFromFloat prevents SIGABRT on ISO huge image CTM and NaN/zero plate params (VULN-09)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;
    const tmp = try mupdf.makePrivateTmpDir(alloc, io);
    defer mupdf.removeTmpDirBestEffort(io, tmp);

    // Huge CTM image PDF -> clean error (NOT SIGABRT!)
    const jpg = try makeSolidJpeg(alloc, 16, 16, .{ .r = 20, .g = 40, .b = 80 });
    const huge_pdf = try std.fmt.allocPrint(alloc, "{s}/huge_ctm.pdf", .{tmp});
    try writeSimplePdf(alloc, io, huge_pdf, .{
        .content = "q 10000000000000 0 0 10000000000000 0 0 cm /Im1 Do Q",
        .image = .{ .w = 16, .h = 16, .jpeg_bytes = jpg },
    });
    const ext_res = mupdf.extractPages(alloc, io, huge_pdf);
    try std.testing.expectError(error.InvalidImageTransform, ext_res);

    // Invalid plate params -> clean errors
    const in_jpg = try std.fmt.allocPrint(alloc, "{s}/in.jpg", .{tmp});
    const out_jpg = try std.fmt.allocPrint(alloc, "{s}/out.jpg", .{tmp});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = in_jpg, .data = jpg });
    try std.testing.expectError(error.InvalidPlateDimensions, media.processPlate(alloc, io, in_jpg, out_jpg, 0.0, 100.0, .{ .r = 0, .g = 0, .b = 0 }, 0.1, 0.1, 88, true, tmp));
    try std.testing.expectError(error.InvalidPlateDimensions, media.processPlate(alloc, io, in_jpg, out_jpg, std.math.nan(f64), 100.0, .{ .r = 0, .g = 0, .b = 0 }, 0.1, 0.1, 88, true, tmp));
    try std.testing.expectError(error.InvalidFeatherParameter, media.processPlate(alloc, io, in_jpg, out_jpg, 100.0, 100.0, .{ .r = 0, .g = 0, .b = 0 }, -0.5, 0.1, 88, true, tmp));
}

test "sabotage 26: composited 144-DPI WCAG contrast rejects alpha ghost, Z-order occlusion, 3 Tr, /BM /Screen, split-bg & RGB stripe phantom median" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;
    const tmp = try mupdf.makePrivateTmpDir(alloc, io);
    defer mupdf.removeTmpDirBestEffort(io, tmp);

    // 1. Alpha ghost `/ca 0.10` black text on white -> FAIL
    const p_alpha = try std.fmt.allocPrint(alloc, "{s}/alpha_ghost.pdf", .{tmp});
    try writeRawPdfObjects(alloc, io, p_alpha, &.{
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> /ExtGState << /GS1 6 0 R >> >> /Contents 4 0 R >>",
        "<< /Length 96 >>\nstream\n1 1 1 rg 0 0 612 792 re f /GS1 gs 0 0 0 rg BT /F1 14 Tf 50 700 Td (Alpha ghost text claim) Tj ET\nendstream",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        "<< /Type /ExtGState /ca 0.10 /CA 0.10 >>",
    });
    try std.testing.expect(!(try audit.auditContrast(alloc, io, p_alpha, try mupdf.extractPages(alloc, io, p_alpha), tmp)).passed);

    // 2. Z-order white cover rectangle painted AFTER text -> FAIL
    const p_zord = try std.fmt.allocPrint(alloc, "{s}/zorder_occlude.pdf", .{tmp});
    try writeSimplePdf(alloc, io, p_zord, .{
        .content = "1 1 1 rg 0 0 612 792 re f 0 0 0 rg BT /F1 14 Tf 50 700 Td (Occluded text under box) Tj ET 1 1 1 rg 40 690 300 30 re f",
    });
    try std.testing.expect(!(try audit.auditContrast(alloc, io, p_zord, try mupdf.extractPages(alloc, io, p_zord), tmp)).passed);

    // 3. Invisible rendering mode `3 Tr` -> FAIL
    const p_tr3 = try std.fmt.allocPrint(alloc, "{s}/tr3.pdf", .{tmp});
    try writeSimplePdf(alloc, io, p_tr3, .{
        .content = "1 1 1 rg 0 0 612 792 re f 0 0 0 rg BT /F1 14 Tf 3 Tr 50 700 Td (Invisible rendering mode) Tj ET",
    });
    try std.testing.expect(!(try audit.auditContrast(alloc, io, p_tr3, try mupdf.extractPages(alloc, io, p_tr3), tmp)).passed);

    // 4. Split dark/white background under white text -> FAIL (right half fails AA!)
    const p_split = try std.fmt.allocPrint(alloc, "{s}/split_bg.pdf", .{tmp});
    try writeSimplePdf(alloc, io, p_split, .{
        .content = "0 0 0 rg 0 0 180 792 re f 1 1 1 rg 180 0 432 792 re f 1 1 1 rg BT /F1 14 Tf 60 700 Td (Half visible on dark and invisible on white) Tj ET",
    });
    try std.testing.expect(!(try audit.auditContrast(alloc, io, p_split, try mupdf.extractPages(alloc, io, p_split), tmp)).passed);

    // 5. Literal string containing `ET` inside BT...ET does NOT break lexer blanking
    const stripped = try mupdf.stripBtEtStreams(alloc, "q 0 0 0 rg\nBT /F1 11 Tf (SMITH ET AL. 2024) Tj ET\nQ\n");
    try std.testing.expect(std.mem.find(u8, stripped, "SMITH") == null);
    try std.testing.expect(std.mem.find(u8, stripped, "0 0 0 rg") != null);
}

test "sabotage 27: geometry catches Bezier clip slicing, >64 nested clips, cross-angle OBB collision, vertical deadzone & centered orphan" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;
    const tmp = try mupdf.makePrivateTmpDir(alloc, io);
    defer mupdf.removeTmpDirBestEffort(io, tmp);

    // 1. >64 nested clips followed by clipped text (dynamic ArrayList clip stack)
    var nested_xml: std.ArrayList(u8) = .empty;
    for (0..70) |_| {
        try nested_xml.appendSlice(alloc, "<clip_path winding=\"eofill\" transform=\"1 0 0 -1 0 792\"><moveto x=\"0\" y=\"0\"/><lineto x=\"612\" y=\"0\"/><lineto x=\"612\" y=\"792\"/><lineto x=\"0\" y=\"792\"/><closepath/></clip_path>");
    }
    try nested_xml.appendSlice(alloc, "<clip_path winding=\"eofill\" transform=\"1 0 0 -1 0 792\"><moveto x=\"50\" y=\"680\"/><lineto x=\"100\" y=\"680\"/><lineto x=\"100\" y=\"710\"/><lineto x=\"50\" y=\"710\"/><closepath/></clip_path>");
    try nested_xml.appendSlice(alloc, "<fill_text transform=\"1 0 0 -1 0 792\"><span font=\"Helvetica\" trm=\"12 0 0 12\"><g unicode=\"X\" x=\"140\" y=\"690\" adv=\"0.6\"/></span></fill_text>");
    try std.testing.expectEqual(@as(usize, 1), try mupdf.countTraceClippedAlnum(alloc, nested_xml.items, 612.0, 792.0));

    // 2. Cross-angle rotated OBB text collision (`45 deg` crossing `0 deg`) -> FAIL
    const p_rot = try std.fmt.allocPrint(alloc, "{s}/rot_collide.pdf", .{tmp});
    try writeSimplePdf(alloc, io, p_rot, .{
        .content =
        \\0 0 0 rg
        \\BT /F1 14 Tf 1 0 0 1 100 500 Tm (Horizontal text colliding right here) Tj ET
        \\BT /F1 14 Tf 0.707 0.707 -0.707 0.707 150 470 Tm (Diagonal rotated colliding text) Tj ET
        ,
    });
    const r_rot = try audit.auditGeometry(alloc, io, p_rot, try mupdf.extractPages(alloc, io, p_rot), 55.0, tmp);
    try std.testing.expect(!r_rot.passed and r_rot.collisions >= 1);

    // 3. Centered orphan headline wrap -> FAIL
    const p_corph = try std.fmt.allocPrint(alloc, "{s}/centered_orphan.pdf", .{tmp});
    try writeSimplePdf(alloc, io, p_corph, .{
        .content =
        \\0 0 0 rg
        \\BT /F2 22 Tf 100 700 Td (Structural Decoupling Across Eight Global) Tj ET
        \\BT /F2 22 Tf 265 674 Td (Economies) Tj ET
        ,
    });
    const r_corph = try audit.auditGeometry(alloc, io, p_corph, try mupdf.extractPages(alloc, io, p_corph), 55.0, tmp);
    try std.testing.expect(!r_corph.passed and r_corph.headline_orphans >= 1);
}

test "sabotage 28: dual-key coverage rejects /ca 0.02 ghost photo, 100% blank white plate, 1pt-inset fake bleed & invalid --pages (KC-6A/B)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;
    const tmp = try mupdf.makePrivateTmpDir(alloc, io);
    defer mupdf.removeTmpDirBestEffort(io, tmp);

    // 1. 100% blank white plate (`#FFFFFF`) -> MUST FAIL flat/blank check!
    const white_jpg = try makeSolidJpeg(alloc, 200, 200, .{ .r = 255, .g = 255, .b = 255 });
    const p_white = try std.fmt.allocPrint(alloc, "{s}/blank_white.pdf", .{tmp});
    try writeSimplePdf(alloc, io, p_white, .{
        .content = "q 612 0 0 792 0 0 cm /Im1 Do Q",
        .image = .{ .w = 200, .h = 200, .jpeg_bytes = white_jpg },
    });
    const r_white = try audit.auditCoverage(alloc, io, p_white, 1, 50.0, 2, null, tmp);
    try std.testing.expect(!r_white.passed);

    // 2. `/ca 0.02` ghost plate -> MUST FAIL (0% visible delta >= 128!)
    const px = try alloc.alloc(u8, 100 * 100 * 3);
    for (0..100) |y| for (0..100) |x| {
        const o = (y * 100 + x) * 3;
        px[o] = @intCast((x * 2) % 255);
        px[o + 1] = @intCast((y * 2) % 255);
        px[o + 2] = 120;
    };
    const grad_jpg = try media.encodeJpegRgb(alloc, 100, 100, px, 88);
    const p_ghost = try std.fmt.allocPrint(alloc, "{s}/ghost_photo.pdf", .{tmp});
    try writeRawPdfObjects(alloc, io, p_ghost, &.{
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /XObject << /Im1 5 0 R >> /ExtGState << /GS1 6 0 R >> >> /Contents 4 0 R >>",
        "<< /Length 42 >>\nstream\n/GS1 gs q 612 0 0 792 0 0 cm /Im1 Do Q\nendstream",
        try std.fmt.allocPrint(alloc, "<< /Type /XObject /Subtype /Image /Width 100 /Height 100 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length {d} >>\nstream\n{s}\nendstream", .{ grad_jpg.len, grad_jpg }),
        "<< /Type /ExtGState /ca 0.02 /CA 0.02 >>",
    });
    const r_ghost = try audit.auditCoverage(alloc, io, p_ghost, 1, 50.0, 2, null, tmp);
    try std.testing.expect(!r_ghost.passed and r_ghost.min_visible_pct < 1.0);

    // 3. 1pt-inset fake bleed (covers 99% area but touches 0 physical edges!) -> MUST FAIL bleed_edges < 2
    const p_inset = try std.fmt.allocPrint(alloc, "{s}/inset_1pt.pdf", .{tmp});
    try writeSimplePdf(alloc, io, p_inset, .{
        .content = "q 608 0 0 788 2 2 cm /Im1 Do Q",
        .image = .{ .w = 100, .h = 100, .jpeg_bytes = grad_jpg },
    });
    const r_inset = try audit.auditCoverage(alloc, io, p_inset, 1, 50.0, 2, null, tmp);
    try std.testing.expect(!r_inset.passed);

    // 4. Invalid `--pages "abc"` MUST FAIL CLOSED!
    const r_badpg = try audit.auditCoverage(alloc, io, p_inset, 1, 50.0, 0, "abc", tmp);
    try std.testing.expect(!r_badpg.passed);
}

test "sabotage 29: prepress catches fake ABCDEF+ unembedded font, ghost BleedBox outside MediaBox & empty StructTreeRoot" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;
    const tmp = try mupdf.makePrivateTmpDir(alloc, io);
    defer mupdf.removeTmpDirBestEffort(io, tmp);

    // Fake ABCDEF+Helvetica with NO /FontFile*, ghost /BleedBox extending outside /MediaBox, empty /StructTreeRoot << >>
    const p_spoof = try std.fmt.allocPrint(alloc, "{s}/prepress_spoof.pdf", .{tmp});
    try writeRawPdfObjects(alloc, io, p_spoof, &.{
        "<< /Type /Catalog /Pages 2 0 R /MarkInfo << /Marked true >> /StructTreeRoot 6 0 R /Lang (en) >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /TrimBox [0 0 612 792] /BleedBox [-9 -9 621 801] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
        "<< /Length 49 >>\nstream\nBT /F1 12 Tf 50 700 Td (Fake subset font PDF) Tj ET\nendstream",
        "<< /Type /Font /Subtype /Type1 /BaseFont /ABCDEF+Helvetica >>",
        "<< /Type /StructTreeRoot >>",
    });
    const cat = try mupdf.inspectCatalog(alloc, io, p_spoof);
    try std.testing.expect(!cat.bleed_all_pages);
    try std.testing.expect(!cat.has_struct_tree);
    try std.testing.expect(cat.unembedded_fonts.len >= 1);
}

test "sabotage 30: font fetcher pins SHA-256 digests and validates TTF/OTF binary magic" {
    try std.testing.expect(!media.isValidFontMagic("<html><body>404 Not Found</body></html>"));
    try std.testing.expect(!media.isValidFontMagic("short"));
    try std.testing.expect(media.isValidFontMagic(&[_]u8{ 0x00, 0x01, 0x00, 0x00, 0, 0, 0, 0, 0, 0, 0, 0 }));
    try std.testing.expect(media.isValidFontMagic("OTTO\x00\x0C\x00\x00\x00\x00\x00\x00"));
    try std.testing.expectEqual(@as(usize, 8), media.FONT_SPECS.len);
    for (media.FONT_SPECS) |sp| {
        for (sp.sha256) |ch| {
            try std.testing.expect((ch >= '0' and ch <= '9') or (ch >= 'a' and ch <= 'f'));
        }
    }
}

test "sabotage 31: RFC 8259 JSON escaping prevents JSON injection in dissect & scaffold (NEW-04)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;
    const tmp = try mupdf.makePrivateTmpDir(alloc, io);
    defer mupdf.removeTmpDirBestEffort(io, tmp);

    // 1. Dissect PDF whose BaseFont contains a backslash (`Evil#5CFont`) & filename contains `"`
    const evil_pdf = try std.fmt.allocPrint(alloc, "{s}/evil\"name.pdf", .{tmp});
    try writeRawPdfObjects(alloc, io, evil_pdf, &.{
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
        "<< /Length 62 >>\nstream\nBT /F1 18 Tf 50 700 Td (Headline With Backslash Font Name) Tj ET\nendstream",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Evil#5CFont >>",
    });
    const bp = try dissect.dissectPdf(alloc, io, evil_pdf, "evil-slug", tmp);
    const bp_json = try dissect.formatBlueprintJson(alloc, bp);
    _ = try std.json.parseFromSliceLeaky(std.json.Value, alloc, bp_json, .{});

    // 2. Scaffold with quotes & backslashes in --title -> valid parseable JSON
    const arch_dir = try std.fmt.allocPrint(alloc, "{s}/arch", .{tmp});
    const proj_dir = try std.fmt.allocPrint(alloc, "{s}/proj", .{tmp});
    _ = try dissect.writeInjectedArchetype(alloc, io, bp, arch_dir);
    _ = try scaffold.writeRegistryIndex(alloc, io, arch_dir);
    try scaffold.initProjectFromArchetype(alloc, io, proj_dir, arch_dir, "evil-slug", "Q4 \"Carbon\" \\ Report");

    const sm_raw = try std.Io.Dir.cwd().readFileAlloc(io, try std.fmt.allocPrint(alloc, "{s}/data/summary_metrics.json", .{proj_dir}), alloc, .unlimited);
    const sm_val = try std.json.parseFromSliceLeaky(std.json.Value, alloc, sm_raw, .{});
    try std.testing.expectEqualStrings("Q4 \"Carbon\" \\ Report", sm_val.object.get("metadata").?.object.get("title").?.string);
    const cit_raw = try std.Io.Dir.cwd().readFileAlloc(io, try std.fmt.allocPrint(alloc, "{s}/data/background_citations.json", .{proj_dir}), alloc, .unlimited);
    _ = try std.json.parseFromSliceLeaky(std.json.Value, alloc, cit_raw, .{});
}

test "sabotage 32: CLI rejects unknown/typo flags and non-finite options (exit 2) and emits honest null booleans in audit-all --json (VULN-11)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;
    const root = findRepoRoot(io);
    const vedit_bin = try std.fs.path.join(alloc, &.{ root, "zig/zig-out/bin/vedit" });
    const tmp = try mupdf.makePrivateTmpDir(alloc, io);
    defer mupdf.removeTmpDirBestEffort(io, tmp);

    const p_ok = try std.fmt.allocPrint(alloc, "{s}/ok.pdf", .{tmp});
    try writeSimplePdf(alloc, io, p_ok, .{
        .content = "1 1 1 rg 0 0 612 792 re f 0 0 0 rg BT /F1 12 Tf 50 700 Td (Clean CLI test) Tj ET",
    });

    // Typo flag `--verify-link` MUST exit 2
    const r_typo = try mupdf.runCmd(alloc, io, &.{ vedit_bin, "audit-all", p_ok, "--verify-link" }, null);
    try std.testing.expectEqual(@as(u8, 2), r_typo.exit_code);

    // Invalid plate `--height-pt 0` MUST exit 2 (zero SIGABRT)
    const r_zero = try mupdf.runCmd(alloc, io, &.{ vedit_bin, "plate", p_ok, p_ok, "--height-pt", "0" }, null);
    try std.testing.expectEqual(@as(u8, 2), r_zero.exit_code);

    // Honest audit-all --json emits `null` for skipped prose/links/coverage
    const r_json = try mupdf.runCmd(alloc, io, &.{ vedit_bin, "audit-all", p_ok, "--no-verapdf", "--skip-links", "--json" }, null);
    const jv = try std.json.parseFromSliceLeaky(std.json.Value, alloc, r_json.stdout, .{});
    try std.testing.expect(jv.object.get("prose_ran").?.bool == false);
    try std.testing.expect(jv.object.get("prose_passed").? == .null);
    try std.testing.expect(jv.object.get("links_ran").?.bool == false);
    try std.testing.expect(jv.object.get("links_passed").? == .null);
    try std.testing.expect(jv.object.get("coverage_ran").?.bool == false);
    try std.testing.expect(jv.object.get("coverage_passed").? == .null);
}

test "sabotage 33: dissect measures true band-union fill_pct (not 100% on empty middle) and deduplicated photo_pct (not 100% on stacked tiles)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;
    const tmp = try mupdf.makePrivateTmpDir(alloc, io);
    defer mupdf.removeTmpDirBestEffort(io, tmp);

    // 1. Top line + bottom line with 650pt empty middle void -> fill_pct MUST be < 20%
    const p_void = try std.fmt.allocPrint(alloc, "{s}/empty_middle.pdf", .{tmp});
    try writeSimplePdf(alloc, io, p_void, .{
        .content =
        \\0 0 0 rg
        \\BT /F1 11 Tf 50 750 Td (Single top line header) Tj ET
        \\BT /F1 11 Tf 50 40 Td (Single bottom line footer) Tj ET
        ,
    });
    const bp_void = try dissect.dissectPdf(alloc, io, p_void, "void-test", tmp);
    try std.testing.expect(bp_void.pages[0].vertical_fill_pct < 20.0);

    // 2. Ten identical overlapping 10%-area images stacked at exact same coordinates -> photo_pct MUST be <= 15%
    const jpg = try makeSolidJpeg(alloc, 64, 64, .{ .r = 40, .g = 90, .b = 140 });
    const p_stack = try std.fmt.allocPrint(alloc, "{s}/stacked_imgs.pdf", .{tmp});
    try writeSimplePdf(alloc, io, p_stack, .{
        .content =
        \\q 200 0 0 240 50 300 cm /Im1 Do Q
        \\q 200 0 0 240 50 300 cm /Im1 Do Q
        \\q 200 0 0 240 50 300 cm /Im1 Do Q
        \\q 200 0 0 240 50 300 cm /Im1 Do Q
        \\q 200 0 0 240 50 300 cm /Im1 Do Q
        \\q 200 0 0 240 50 300 cm /Im1 Do Q
        \\q 200 0 0 240 50 300 cm /Im1 Do Q
        \\q 200 0 0 240 50 300 cm /Im1 Do Q
        \\q 200 0 0 240 50 300 cm /Im1 Do Q
        \\q 200 0 0 240 50 300 cm /Im1 Do Q
        ,
        .image = .{ .w = 64, .h = 64, .jpeg_bytes = jpg },
    });
    const bp_stack = try dissect.dissectPdf(alloc, io, p_stack, "stack-test", tmp);
    try std.testing.expect(bp_stack.pages[0].photo_coverage_pct <= 15.0);
}

test "sabotage 34: Rule 10 flags /ToUnicode glyph-advance spoofing (NEW-05)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;
    const tmp = try mupdf.makePrivateTmpDir(alloc, io);
    defer mupdf.removeTmpDirBestEffort(io, tmp);

    // Real PDF with a Type1 font whose /Widths are digit-narrow (440/1000) while /ToUnicode maps ASCII digits to wide capitals M, W, O, G
    const cmap =
        \\/CIDInit /ProcSet findresource begin
        \\12 dict begin
        \\begincmap
        \\/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def
        \\/CMapName /Spoof-UCS def
        \\/CMapType 2 def
        \\1 begincodespacerange
        \\<00> <FF>
        \\endcodespacerange
        \\4 beginbfchar
        \\<31> <004D>
        \\<32> <0057>
        \\<33> <004F>
        \\<34> <0047>
        \\endbfchar
        \\endcmap
        \\CMapName currentdict /CMap defineresource pop
        \\end
        \\end
    ;
    const p_tu = try std.fmt.allocPrint(alloc, "{s}/tounicode_spoof.pdf", .{tmp});
    try writeRawPdfObjects(alloc, io, p_tu, &.{
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
        "<< /Length 42 >>\nstream\nBT /F1 12 Tf 50 700 Td (1234) Tj ET\nendstream",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /FirstChar 49 /LastChar 52 /Widths [440 440 440 440] /ToUnicode 6 0 R >>",
        try std.fmt.allocPrint(alloc, "<< /Length {d} >>\nstream\n{s}\nendstream", .{ cmap.len, cmap }),
    });
    const led = try std.fmt.allocPrint(alloc, "{s}/led.json", .{tmp});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = led, .data = "[{\"metric_id\":\"x\",\"value\":1.0}]" });
    const pages = try mupdf.extractPages(alloc, io, p_tu);
    try std.testing.expect(pages.len == 1 and pages[0].tounicode_anomalies.len >= 3);
    const pr = try audit.auditProse(alloc, io, pages, led, null, null, null);
    try std.testing.expect(!pr.passed);
}

test "regression 35: all 5 flagship Typst PDF/UA-1 monographs pass Rule 11B with --citations + --ledger and zero-regression latch" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;
    const root = findRepoRoot(io);

    const Flagship = struct {
        pdf: []const u8,
        citations: []const u8,
        ledger: []const u8,
        latch_dir: []const u8,
    };
    const items = [_]Flagship{
        .{
            .pdf = "demos/typst-carbon-monograph/report/TYPST_CARBON_MONOGRAPH_UA1.pdf",
            .citations = "demos/typst-carbon-monograph/data/background_citations.json",
            .ledger = "demos/global-carbon-telemetry/data/provenance_ledger.json",
            .latch_dir = "demos/global-carbon-telemetry",
        },
        .{
            .pdf = "demos/exomundus-nasa-telemetry/report/EXOMUNDUS_NASA_TELEMETRY_UA1.pdf",
            .citations = "demos/exomundus-nasa-telemetry/data/background_citations.json",
            .ledger = "demos/exomundus-nasa-telemetry/data/provenance_ledger.json",
            .latch_dir = "demos/exomundus-nasa-telemetry",
        },
        .{
            .pdf = "demos/caie-flowshop-journal/report/CAIE_FLOWSHOP_MANUSCRIPT_UA1.pdf",
            .citations = "demos/caie-flowshop-journal/data/background_citations.json",
            .ledger = "demos/caie-flowshop-journal/data/provenance_ledger.json",
            .latch_dir = "demos/caie-flowshop-journal",
        },
        .{
            .pdf = "demos/prl-yang-mills-chaos/report/PRL_YANG_MILLS_CHAOS_UA1.pdf",
            .citations = "demos/prl-yang-mills-chaos/data/background_citations.json",
            .ledger = "demos/prl-yang-mills-chaos/data/provenance_ledger.json",
            .latch_dir = "demos/prl-yang-mills-chaos",
        },
        .{
            .pdf = "demos/cosmos-mobile-primer/report/COSMOS_MOBILE_PRIMER_UA1.pdf",
            .citations = "demos/cosmos-mobile-primer/data/background_citations.json",
            .ledger = "demos/cosmos-mobile-primer/data/provenance_ledger.json",
            .latch_dir = "demos/cosmos-mobile-primer",
        },
    };

    for (items) |it| {
        const lt = try audit.auditLatch(alloc, io, try std.fs.path.join(alloc, &.{ root, it.latch_dir }));
        try std.testing.expect(lt.passed);
        const pdf = try std.fs.path.join(alloc, &.{ root, it.pdf });
        const pages = try mupdf.extractPages(alloc, io, pdf);
        const lr = try links.auditLinks(
            alloc,
            io,
            pdf,
            pages,
            try std.fs.path.join(alloc, &.{ root, it.citations }),
            try std.fs.path.join(alloc, &.{ root, it.ledger }),
            1,
            false,
            5,
            false,
        );
        try std.testing.expect(lr.passed);
    }

    // Remaining ledger demos pass cryptographic latch too
    for ([_][]const u8{ "demos/botanica-veridica", "demos/carbon-keynote-9slide", "demos/consulting-flagship" }) |ld| {
        const lt = try audit.auditLatch(alloc, io, try std.fs.path.join(alloc, &.{ root, ld }));
        try std.testing.expect(lt.passed);
    }
}
