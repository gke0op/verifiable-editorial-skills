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
    } else |_| {}
    return "..";
}

fn ensureTestDir(io: std.Io, path: []const u8) !void {
    if (std.Io.Dir.cwd().openDir(io, path, .{})) |d| {
        var dir = d;
        dir.close(io);
        return;
    } else |_| {}
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
    defer std.Io.Dir.cwd().deleteTree(io, tmp) catch {};

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
    defer std.Io.Dir.cwd().deleteTree(io, tmp) catch {};

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
    defer std.Io.Dir.cwd().deleteTree(io, tmp) catch {};

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
    defer std.Io.Dir.cwd().deleteTree(io, tmp) catch {};

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
    defer std.Io.Dir.cwd().deleteTree(io, tmp) catch {};

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
    defer std.Io.Dir.cwd().deleteTree(io, tmp) catch {};

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
    defer std.Io.Dir.cwd().deleteTree(io, tmp) catch {};

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

    // Real Unicode superscript (10⁷ vs 10⁶) & fullwidth digits (９９) via Typst if available
    if (mupdf.whichTool(alloc, io, "typst") != null) {
        const u7_pdf = try compileTypstSnippet(alloc, io, tmp, "uni_sup_7", "#set page(width: 612pt, height: 792pt)\nWe sampled 10\xe2\x81\xb7 points.");
        const u7_pages = try mupdf.extractPages(alloc, io, u7_pdf);
        try std.testing.expect(!(try audit.auditProse(alloc, io, u7_pages, sup_led, null, null, null)).passed);

        const u6_pdf = try compileTypstSnippet(alloc, io, tmp, "uni_sup_6", "#set page(width: 612pt, height: 792pt)\nWe sampled 10\xe2\x81\xb6 points.");
        const u6_pages = try mupdf.extractPages(alloc, io, u6_pdf);
        try std.testing.expect((try audit.auditProse(alloc, io, u6_pages, sup_led, null, null, null)).passed);

        const fw_led = try std.fmt.allocPrint(alloc, "{s}/fw.json", .{tmp});
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = fw_led, .data = "{\"k0\":{\"value\":45.0}}" });
        const fw_pdf = try compileTypstSnippet(alloc, io, tmp, "uni_fw_99", "#set page(width: 612pt, height: 792pt)\nThe count was \xef\xbc\x99\xef\xbc\x99 units.");
        const fw_pages = try mupdf.extractPages(alloc, io, fw_pdf);
        try std.testing.expect(!(try audit.auditProse(alloc, io, fw_pages, fw_led, null, null, null)).passed);
    }
}

test "sabotage 08: SHA-256 compilation latch rejects single-byte raw tamper" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;
    const tmp = "/tmp/vedit_court_08";
    try ensureTestDir(io, tmp);
    defer std.Io.Dir.cwd().deleteTree(io, tmp) catch {};

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
    defer std.Io.Dir.cwd().deleteTree(io, tmp) catch {};

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
    defer std.Io.Dir.cwd().deleteTree(io, tmp) catch {};

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
        w.interface.flush() catch {};
    }
}

test "sabotage 11: Rule 11C live HTTP court passes 200 OK and rejects 404, Soft-404, Client Challenge & 403" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;
    const tmp = "/tmp/vedit_court_11";
    try ensureTestDir(io, tmp);
    defer std.Io.Dir.cwd().deleteTree(io, tmp) catch {};

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
            _ = mupdf.runCmd(alloc, io, &.{ "curl", "-s", "--max-time", "1", wake_url }, null) catch {};
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
    defer std.Io.Dir.cwd().deleteTree(io, tmp) catch {};

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
    defer std.Io.Dir.cwd().deleteTree(io, tmp) catch {};

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
