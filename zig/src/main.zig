//! Sovereign Zig 0.17.0 Agent Harness CLI (`vedit`).
//! Zero-Python verification court, PDF sample dissector/injector, and archetype project scaffolder,
//! powered by `p2zig --strict`-transpiled mathematical kernels (`kernels_p2zig.zig`).

const std = @import("std");
const kernels = @import("kernels_p2zig.zig");
const mupdf = @import("mupdf.zig");
const audit = @import("audit.zig");
const links = @import("links.zig");
const dissect = @import("dissect.zig");
const scaffold = @import("scaffold.zig");

const VERSION = "0.5.0-zig";

fn writeOut(io: std.Io, s: []const u8) !void {
    try std.Io.File.stdout().writeStreamingAll(io, s);
}

fn writeErr(io: std.Io, s: []const u8) void {
    std.Io.File.stderr().writeStreamingAll(io, s) catch {};
}

fn printUsage(io: std.Io) !void {
    try writeOut(io,
        \\vedit (Sovereign Zig 0.17.0 Editorial Harness v0.5.0-zig)
        \\
        \\Commands:
        \\  vedit inject <sample.pdf> --name <slug> [--out-dir archetypes] [--json]
        \\      Dissect any reference PDF into Design DNA (blueprint.json + skeleton.typ + AGENT_CARD.md)
        \\  vedit inspect <pdf> [--json]
        \\      Print dissected structural/chromatic/typographic telemetry for AI agents
        \\  vedit archetypes [--dir archetypes] [--json]
        \\      List all injected/registered PDF archetypes in the harness
        \\  vedit init <target_dir> --archetype <slug> [--dir archetypes] [--title "..."]
        \\      Scaffold a SHA-256-sealed, Rule-6-latched Typst PDF/UA-1 project from an injected archetype
        \\  vedit latch <project_dir> [--json]
        \\      Pure-Zig SHA-256 manifest + Rule 4 provenance ledger compilation latch
        \\  vedit contrast <pdf> [--json]
        \\      Background-sampled WCAG 2.1 AA contrast gate (p2zig kernel)
        \\  vedit geometry <pdf> [--max-rms 55] [--json]
        \\      AABB collision, W/W* clip-path slicing, trim overflow, headline orphan & photo-texture gate
        \\  vedit coverage <pdf> [--min-pct 50] [--min-bleed 2] [--pages "1,4-9"] [--json]
        \\      Exact clip-aware dual-key pixel-diff visible photography coverage gate (p2zig kernel)
        \\  vedit prose <pdf> [--ledger F] [--summary F] [--citations F] [--manifest F] [--json]
        \\      Rule 10 post-render signed + superscript-safe prose grounding gate (half-ULP f64)
        \\  vedit links <pdf> [--citations F] [--ledger F] [--min-links 1] [--offline] [--timeout 10] [--json]
        \\      Rule 11 clickable PDF resource link coverage & live anti-hallucination verifier
        \\  vedit prepress <pdf> [--min-dpi 300] [--require-bleed] [--require-ua] [--no-verapdf] [--json]
        \\      Effective DPI, font embedding, Trim/BleedBox, CMYK GCR TAC & live veraPDF ISO 14289-1 gate
        \\  vedit audit-all <pdf> [--ledger F] [--summary F] [--citations F] [--manifest F] [--plate-pages "1,4-9"] [--min-dpi 300] [--require-bleed] [--require-ua] [--verify-links|--check-links-offline] [--no-verapdf] [--json]
        \\      Run all applicable verification gates in one invocation (exits non-zero on any failure)
        \\  vedit version
        \\
    );
}

fn hasFlag(args: []const [:0]const u8, flag: []const u8) bool {
    for (args) |a| {
        if (std.mem.eql(u8, a, flag)) return true;
    }
    return false;
}

fn getOpt(args: []const [:0]const u8, flag: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i + 1 < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], flag)) return args[i + 1];
    }
    return null;
}

fn sanitizeSlug(alloc: std.mem.Allocator, raw: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    for (raw) |ch| {
        if ((ch >= 'a' and ch <= 'z') or (ch >= '0' and ch <= '9') or ch == '-' or ch == '_') {
            try out.append(alloc, ch);
        } else if (ch >= 'A' and ch <= 'Z') {
            try out.append(alloc, ch + 32);
        } else if (ch == ' ' or ch == '.') {
            try out.append(alloc, '-');
        }
    }
    if (out.items.len == 0) try out.appendSlice(alloc, "sample");
    return out.toOwnedSlice(alloc);
}

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    const io = init.io;
    const all_args = try init.minimal.args.toSlice(alloc);
    if (all_args.len < 2) {
        try printUsage(io);
        return;
    }

    const cmd = all_args[1];
    const sub_args = all_args[2..];
    const as_json = hasFlag(sub_args, "--json");
    const tmp_tag = "zig017";

    if (std.mem.eql(u8, cmd, "version") or std.mem.eql(u8, cmd, "--version")) {
        try writeOut(io, try std.fmt.allocPrint(alloc, "vedit {s} (Zig 0.17.0 + p2zig-strict kernels)\n", .{VERSION}));
        return;
    }
    if (std.mem.eql(u8, cmd, "-h") or std.mem.eql(u8, cmd, "--help") or std.mem.eql(u8, cmd, "help")) {
        try printUsage(io);
        return;
    }

    // -------------------------------------------------------------------------
    // INJECT / INSPECT (Pillar #6: PDF Sample Dissection & Archetype Injection)
    // -------------------------------------------------------------------------
    if (std.mem.eql(u8, cmd, "inject") or std.mem.eql(u8, cmd, "inspect")) {
        if (sub_args.len < 1) {
            writeErr(io, "usage: vedit inject <sample.pdf> [--name <slug>] [--out-dir archetypes] [--json]\n");
            std.process.exit(2);
        }
        const pdf_path = sub_args[0];
        const base = std.fs.path.stem(pdf_path);
        const raw_slug = getOpt(sub_args, "--name") orelse base;
        const slug = try sanitizeSlug(alloc, raw_slug);
        const out_dir = getOpt(sub_args, "--out-dir") orelse "archetypes";

        const bp = try dissect.dissectPdf(alloc, io, pdf_path, slug, tmp_tag);
        if (std.mem.eql(u8, cmd, "inspect")) {
            const j = try dissect.formatBlueprintJson(alloc, bp);
            try writeOut(io, j);
            return;
        }

        const written_dir = try dissect.writeInjectedArchetype(alloc, io, bp, out_dir);
        const reg_count = try scaffold.writeRegistryIndex(alloc, io, out_dir);
        if (as_json) {
            const j = try dissect.formatBlueprintJson(alloc, bp);
            try writeOut(io, j);
        } else {
            var h_bg: [7]u8 = undefined;
            var h_a1: [7]u8 = undefined;
            try writeOut(io, try std.fmt.allocPrint(alloc,
                \\[vedit:inject] REGISTERED '{s}' -> {s}/ (registry total: {d})
                \\  source={s} | format={s} ({d:.0}x{d:.0}pt) | polarity={s} | pages={d}
                \\  palette: bg={s} accent={s} (ink_cr={d:.2}:1) | fill={d:.1}% photo={d:.1}%
                \\  emitted: blueprint.json, skeleton.typ, AGENT_CARD.md
                \\
            , .{
                bp.slug,
                written_dir,
                reg_count,
                bp.source_pdf,
                bp.format_class,
                bp.trim_w_pt,
                bp.trim_h_pt,
                bp.polarity,
                bp.page_count,
                bp.canvas_bg.formatHex(&h_bg),
                bp.accent_primary.formatHex(&h_a1),
                @as(f64, @floatFromInt(bp.ink_contrast_x100)) / 100.0,
                bp.avg_fill_pct,
                bp.avg_photo_pct,
            }));
        }
        return;
    }

    // -------------------------------------------------------------------------
    // ARCHETYPES & INIT (Pillar #2: Sovereign Zig CLI Scaffolding)
    // -------------------------------------------------------------------------
    if (std.mem.eql(u8, cmd, "archetypes")) {
        const dir = getOpt(sub_args, "--dir") orelse "archetypes";
        const entries = try scaffold.listArchetypes(alloc, io, dir);
        if (as_json) {
            var buf: std.ArrayList(u8) = .empty;
            try buf.appendSlice(alloc, "[\n");
            for (entries, 0..) |e, idx| {
                const comma: []const u8 = if (idx + 1 < entries.len) "," else "";
                try buf.appendSlice(alloc, try std.fmt.allocPrint(alloc,
                    \\  {{ "slug": "{s}", "source_pdf": "{s}", "format_class": "{s}", "polarity": "{s}", "pages": {d}, "canvas_bg": "{s}", "accent_primary": "{s}" }}{s}
                    \\
                , .{ e.slug, e.source_pdf, e.format_class, e.polarity, e.page_count, e.canvas_bg, e.accent_primary, comma }));
            }
            try buf.appendSlice(alloc, "]\n");
            try writeOut(io, buf.items);
        } else {
            try writeOut(io, try std.fmt.allocPrint(alloc, "[vedit:archetypes] {d} registered archetype(s) in '{s}':\n", .{ entries.len, dir }));
            for (entries) |e| {
                try writeOut(io, try std.fmt.allocPrint(alloc, "  - {s:<24} {s:<16} {s:<5} {d}p  bg={s} acc={s}  (from {s})\n", .{
                    e.slug, e.format_class, e.polarity, e.page_count, e.canvas_bg, e.accent_primary, e.source_pdf,
                }));
            }
        }
        return;
    }

    if (std.mem.eql(u8, cmd, "init")) {
        if (sub_args.len < 1) {
            writeErr(io, "usage: vedit init <target_dir> --archetype <slug> [--dir archetypes] [--title \"...\"]\n");
            std.process.exit(2);
        }
        const target_dir = sub_args[0];
        const arch = getOpt(sub_args, "--archetype") orelse {
            writeErr(io, "error: --archetype <slug> is required\n");
            std.process.exit(2);
        };
        const dir = getOpt(sub_args, "--dir") orelse "archetypes";
        const title = getOpt(sub_args, "--title") orelse "Verified Archetype Report";
        try scaffold.initProjectFromArchetype(alloc, io, target_dir, dir, arch, title);
        try writeOut(io, try std.fmt.allocPrint(alloc,
            \\[vedit:init] Scaffolded verified Typst PDF/UA-1 project -> {s}
            \\  archetype={s} | SHA-256 manifest sealed | Rule 4 ledger populated
            \\  next: bash {s}/build.sh
            \\
        , .{ target_dir, arch, target_dir }));
        return;
    }

    // -------------------------------------------------------------------------
    // LATCH (Pure-Zig Rule 4 + Rule 6 SHA-256 Compilation Latch)
    // -------------------------------------------------------------------------
    if (std.mem.eql(u8, cmd, "latch")) {
        if (sub_args.len < 1) {
            writeErr(io, "usage: vedit latch <project_dir> [--json]\n");
            std.process.exit(2);
        }
        const rep = try audit.auditLatch(alloc, io, sub_args[0]);
        if (as_json) {
            try writeOut(io, try std.fmt.allocPrint(alloc,
                \\{{ "gate": "latch", "passed": {}, "manifest_files": {d}, "manifest_verified": {d}, "ledger_records": {d}, "metrics_verified": {d}, "failures": {d} }}
                \\
            , .{ rep.passed, rep.manifest_files, rep.manifest_verified, rep.ledger_records, rep.metrics_verified, rep.failures.len }));
        } else {
            const st: []const u8 = if (rep.passed) "PASS" else "FAIL";
            try writeOut(io, try std.fmt.allocPrint(alloc, "[vedit:latch] {s} -> {s}\n  manifest={d}/{d} SHA-256 verified | ledger={d} records | metrics_covered={d}\n", .{
                st, sub_args[0], rep.manifest_verified, rep.manifest_files, rep.ledger_records, rep.metrics_verified,
            }));
            for (rep.failures) |f| {
                try writeOut(io, try std.fmt.allocPrint(alloc, "  [!] {s}\n", .{f}));
            }
        }
        if (!rep.passed) std.process.exit(1);
        return;
    }

    // -------------------------------------------------------------------------
    // VERIFICATION COURT GATES: contrast / geometry / prose / prepress / audit-all
    // -------------------------------------------------------------------------
    if (sub_args.len < 1) {
        try printUsage(io);
        std.process.exit(2);
    }
    const pdf_path = sub_args[0];
    const pdf_name = std.fs.path.basename(pdf_path);
    const pages = try mupdf.extractPages(alloc, io, pdf_path);

    if (std.mem.eql(u8, cmd, "contrast")) {
        const rep = try audit.auditContrast(alloc, io, pdf_path, pages, tmp_tag);
        if (as_json) {
            try writeOut(io, try std.fmt.allocPrint(alloc,
                \\{{ "gate": "wcag_contrast", "pdf": "{s}", "passed": {}, "spans": {d}, "worst_cr": {d:.2}, "violations": {d} }}
                \\
            , .{ pdf_name, rep.passed, rep.total_spans, @as(f64, @floatFromInt(rep.worst_cr_x100)) / 100.0, rep.total_violations }));
        } else {
            const st: []const u8 = if (rep.passed) "PASS" else "FAIL";
            try writeOut(io, try std.fmt.allocPrint(alloc, "[vedit:wcag_contrast] {s} -> {s}\n  spans={d} | worst_cr={d:.2}:1 | violations={d}\n", .{
                st, pdf_name, rep.total_spans, @as(f64, @floatFromInt(rep.worst_cr_x100)) / 100.0, rep.total_violations,
            }));
            for (rep.violations[0..@min(rep.violations.len, 8)]) |v| {
                try writeOut(io, try std.fmt.allocPrint(alloc, "  [!] p.{d} {d:.2}:1 < {d:.1}:1 ({s} on {s}) '{s}'\n", .{
                    v.page, @as(f64, @floatFromInt(v.ratio_x100)) / 100.0, @as(f64, @floatFromInt(v.required_x100)) / 100.0, v.fg_hex[0..7], v.bg_hex[0..7], v.text,
                }));
            }
        }
        if (!rep.passed) std.process.exit(1);
        return;
    }

    if (std.mem.eql(u8, cmd, "geometry")) {
        const max_rms: f64 = if (getOpt(sub_args, "--max-rms")) |v| std.fmt.parseFloat(f64, v) catch 55.0 else 55.0;
        const rep = try audit.auditGeometry(alloc, io, pdf_path, pages, max_rms, tmp_tag);
        if (as_json) {
            try writeOut(io, try std.fmt.allocPrint(alloc,
                \\{{ "gate": "geometry", "pdf": "{s}", "passed": {}, "collisions": {d}, "clipped": {d}, "overflow": {d}, "orphans": {d}, "noisy_overlays": {d}, "worst_rms": {d:.1} }}
                \\
            , .{ pdf_name, rep.passed, rep.collisions, rep.clipped, rep.trim_overflow, rep.headline_orphans, rep.noisy_overlays, rep.worst_rms }));
        } else {
            const st: []const u8 = if (rep.passed) "PASS" else "FAIL";
            try writeOut(io, try std.fmt.allocPrint(alloc, "[vedit:geometry] {s} -> {s}\n  collisions={d} | clipped={d} | overflow={d} | orphans={d} | noisy_overlays={d} (worst_rms={d:.1})\n", .{
                st, pdf_name, rep.collisions, rep.clipped, rep.trim_overflow, rep.headline_orphans, rep.noisy_overlays, rep.worst_rms,
            }));
            for (rep.issues[0..@min(rep.issues.len, 10)]) |iss| {
                try writeOut(io, try std.fmt.allocPrint(alloc, "  [!] p.{d} {s}: {s}\n", .{ iss.page, iss.kind, iss.detail }));
            }
        }
        if (!rep.passed) std.process.exit(1);
        return;
    }

    if (std.mem.eql(u8, cmd, "coverage")) {
        const min_pct: f64 = if (getOpt(sub_args, "--min-pct")) |v| std.fmt.parseFloat(f64, v) catch 50.0 else 50.0;
        const min_bl: i64 = if (getOpt(sub_args, "--min-bleed")) |v| std.fmt.parseInt(i64, v, 10) catch 2 else 2;
        const rep = try audit.auditCoverage(alloc, io, pdf_path, pages.len, min_pct, min_bl, getOpt(sub_args, "--pages"), tmp_tag);
        if (as_json) {
            try writeOut(io, try std.fmt.allocPrint(alloc,
                \\{{ "gate": "photo_coverage", "pdf": "{s}", "passed": {}, "enforced_pages": {d}, "min_visible_pct": {d:.2}, "avg_visible_pct": {d:.2}, "failures": {d} }}
                \\
            , .{ pdf_name, rep.passed, rep.enforced_count, rep.min_visible_pct, rep.avg_visible_pct, rep.failures.len }));
        } else {
            const st: []const u8 = if (rep.passed) "PASS" else "FAIL";
            try writeOut(io, try std.fmt.allocPrint(alloc, "[vedit:photo_coverage] {s} -> {s}\n  enforced={d} pages | min_visible={d:.1}% | avg_visible={d:.1}%\n", .{
                st, pdf_name, rep.enforced_count, rep.min_visible_pct, rep.avg_visible_pct,
            }));
            for (rep.failures) |f| {
                try writeOut(io, try std.fmt.allocPrint(alloc, "  [!] {s}\n", .{f}));
            }
        }
        if (!rep.passed) std.process.exit(1);
        return;
    }

    if (std.mem.eql(u8, cmd, "prose")) {
        const rep = try audit.auditProse(
            alloc,
            io,
            pages,
            getOpt(sub_args, "--ledger"),
            getOpt(sub_args, "--summary"),
            getOpt(sub_args, "--citations"),
            getOpt(sub_args, "--manifest"),
        );
        if (as_json) {
            try writeOut(io, try std.fmt.allocPrint(alloc,
                \\{{ "gate": "rule10_prose", "pdf": "{s}", "passed": {}, "numbers_checked": {d}, "authorized_pool": {d}, "ungrounded": {d} }}
                \\
            , .{ pdf_name, rep.passed, rep.numbers_checked, rep.authorized_pool, rep.ungrounded_count }));
        } else {
            const st: []const u8 = if (rep.passed) "PASS" else "FAIL";
            try writeOut(io, try std.fmt.allocPrint(alloc, "[vedit:rule10_prose] {s} -> {s}\n  numbers_checked={d} | authorized_pool={d} | ungrounded={d}\n", .{
                st, pdf_name, rep.numbers_checked, rep.authorized_pool, rep.ungrounded_count,
            }));
            for (rep.ungrounded[0..@min(rep.ungrounded.len, 10)]) |u| {
                try writeOut(io, try std.fmt.allocPrint(alloc, "  [!] p.{d} UNGROUNDED '{s}' in: ...{s}...\n", .{ u.page, u.token, u.context }));
            }
        }
        if (!rep.passed) std.process.exit(1);
        return;
    }

    if (std.mem.eql(u8, cmd, "links")) {
        const min_l: usize = if (getOpt(sub_args, "--min-links")) |v| std.fmt.parseInt(usize, v, 10) catch 1 else 1;
        const tout: u32 = if (getOpt(sub_args, "--timeout")) |v| std.fmt.parseInt(u32, v, 10) catch 10 else 10;
        const live = !hasFlag(sub_args, "--offline");
        const allow_local = hasFlag(sub_args, "--allow-localhost");
        const rep = try links.auditLinks(
            alloc,
            io,
            pdf_path,
            pages,
            getOpt(sub_args, "--citations"),
            getOpt(sub_args, "--ledger"),
            min_l,
            live,
            tout,
            allow_local,
        );
        if (as_json) {
            try writeOut(io, try std.fmt.allocPrint(alloc,
                \\{{ "gate": "rule11_links", "pdf": "{s}", "passed": {}, "clickable_links": {d}, "unique_uris": {d}, "text_resources": {d}, "declared_resources": {d}, "live_checked": {}, "failures": {d} }}
                \\
            , .{ pdf_name, rep.passed, rep.clickable_links, rep.unique_uris, rep.text_resources, rep.declared_resources, rep.live_checked, rep.failures.len }));
        } else {
            const st: []const u8 = if (rep.passed) "PASS" else "FAIL";
            const mode_s: []const u8 = if (rep.live_checked) "live" else "offline";
            try writeOut(io, try std.fmt.allocPrint(alloc, "[vedit:rule11_links] {s} -> {s}\n  clickable={d} | unique={d} | text_urls={d} | declared={d} | mode={s} | failures={d}\n", .{
                st, pdf_name, rep.clickable_links, rep.unique_uris, rep.text_resources, rep.declared_resources, mode_s, rep.failures.len,
            }));
            for (rep.live_results) |lr| {
                const mk: []const u8 = if (lr.passed) "OK" else "!";
                try writeOut(io, try std.fmt.allocPrint(alloc, "  [{s}] {s} -> {s} ({s})\n", .{
                    mk, lr.uri, lr.verdict, lr.title[0..@min(lr.title.len, 64)],
                }));
            }
            for (rep.failures[0..@min(rep.failures.len, 16)]) |f| {
                try writeOut(io, try std.fmt.allocPrint(alloc, "  [!] p.{d} {s}: {s}\n", .{ f.page, f.kind, f.detail }));
            }
        }
        if (!rep.passed) std.process.exit(1);
        return;
    }

    if (std.mem.eql(u8, cmd, "prepress")) {
        const cat = try mupdf.inspectCatalog(alloc, io, pdf_path);
        const min_dpi: f64 = if (getOpt(sub_args, "--min-dpi")) |v| std.fmt.parseFloat(f64, v) catch 300.0 else 300.0;
        const max_tac: f64 = if (getOpt(sub_args, "--max-tac")) |v| std.fmt.parseFloat(f64, v) catch 300.0 else 300.0;
        const rep = try audit.auditPrepress(alloc, io, pdf_path, pages, cat, min_dpi, max_tac, hasFlag(sub_args, "--require-bleed"), hasFlag(sub_args, "--require-ua"), !hasFlag(sub_args, "--no-verapdf"), tmp_tag);
        if (as_json) {
            try writeOut(io, try std.fmt.allocPrint(alloc,
                \\{{ "gate": "prepress", "pdf": "{s}", "passed": {}, "images": {d}, "unembedded_fonts": {d}, "bleed_all": {}, "cmyk_p99_tac": {d:.1}, "ua_struct": {}, "verapdf_available": {}, "verapdf_compliant": {}, "verapdf_pass": {d}, "verapdf_fail": {d} }}
                \\
            , .{ pdf_name, rep.passed, rep.image_count, rep.unembedded_fonts.len, rep.bleed_all_pages, @as(f64, @floatFromInt(rep.cmyk_p99_tac_x10)) / 10.0, rep.ua_struct_pass, rep.verapdf.available, rep.verapdf.compliant, rep.verapdf.passed_rules, rep.verapdf.failed_rules }));
        } else {
            const st: []const u8 = if (rep.passed) "PASS" else "FAIL";
            const dpi_s = if (rep.min_eff_dpi_x10 >= 0) try std.fmt.allocPrint(alloc, "{d:.1}", .{@as(f64, @floatFromInt(rep.min_eff_dpi_x10)) / 10.0}) else "n/a(vector)";
            const vp_s = if (rep.verapdf.available) try std.fmt.allocPrint(alloc, "compliant={} (pass={d}, fail={d})", .{ rep.verapdf.compliant, rep.verapdf.passed_rules, rep.verapdf.failed_rules }) else "not-installed";
            try writeOut(io, try std.fmt.allocPrint(alloc, "[vedit:prepress] {s} -> {s}\n  images={d} | min_dpi={s} | unembedded_fonts={d} | bleed_all={} | cmyk_p99_tac={d:.1}% | ua_struct={} | verapdf={s}\n", .{
                st, pdf_name, rep.image_count, dpi_s, rep.unembedded_fonts.len, rep.bleed_all_pages, @as(f64, @floatFromInt(rep.cmyk_p99_tac_x10)) / 10.0, rep.ua_struct_pass, vp_s,
            }));
            for (rep.failures) |f| {
                try writeOut(io, try std.fmt.allocPrint(alloc, "  [!] {s}\n", .{f}));
            }
        }
        if (!rep.passed) std.process.exit(1);
        return;
    }

    if (std.mem.eql(u8, cmd, "audit-all")) {
        var all_ok = true;
        const cr = try audit.auditContrast(alloc, io, pdf_path, pages, tmp_tag);
        if (!cr.passed) all_ok = false;
        const geo = try audit.auditGeometry(alloc, io, pdf_path, pages, 55.0, tmp_tag);
        if (!geo.passed) all_ok = false;

        var prose_ran = false;
        var prose_ok = true;
        var prose_checked: usize = 0;
        var prose_ungr: usize = 0;
        const lp = getOpt(sub_args, "--ledger");
        const sp = getOpt(sub_args, "--summary");
        if (lp != null or sp != null) {
            prose_ran = true;
            const pr = try audit.auditProse(alloc, io, pages, lp, sp, getOpt(sub_args, "--citations"), getOpt(sub_args, "--manifest"));
            prose_ok = pr.passed;
            prose_checked = pr.numbers_checked;
            prose_ungr = pr.ungrounded_count;
            if (!pr.passed) all_ok = false;
            if (!as_json) {
                try writeOut(io, try std.fmt.allocPrint(alloc, "[vedit:rule10_prose] {s} -> {s}\n  numbers_checked={d} | authorized_pool={d} | ungrounded={d}\n", .{
                    if (pr.passed) "PASS" else "FAIL", pdf_name, pr.numbers_checked, pr.authorized_pool, pr.ungrounded_count,
                }));
                for (pr.ungrounded[0..@min(pr.ungrounded.len, 8)]) |u| {
                    try writeOut(io, try std.fmt.allocPrint(alloc, "  [!] p.{d} UNGROUNDED '{s}' in: ...{s}...\n", .{ u.page, u.token, u.context }));
                }
            }
        }

        var cov_ran = false;
        var cov_ok = true;
        var cov_min_pct: f64 = 0.0;
        if (getOpt(sub_args, "--plate-pages")) |pspec| {
            cov_ran = true;
            const cov_min: f64 = if (getOpt(sub_args, "--min-photo-pct")) |v| std.fmt.parseFloat(f64, v) catch 50.0 else 50.0;
            const cov = try audit.auditCoverage(alloc, io, pdf_path, pages.len, cov_min, 2, pspec, tmp_tag);
            cov_ok = cov.passed;
            cov_min_pct = cov.min_visible_pct;
            if (!cov.passed) all_ok = false;
            if (!as_json) {
                try writeOut(io, try std.fmt.allocPrint(alloc, "[vedit:photo_coverage] {s} -> {s} (enforced={d}, min_visible={d:.1}%, avg={d:.1}%)\n", .{
                    if (cov.passed) "PASS" else "FAIL", pdf_name, cov.enforced_count, cov.min_visible_pct, cov.avg_visible_pct,
                }));
                for (cov.failures) |f| {
                    try writeOut(io, try std.fmt.allocPrint(alloc, "  [!] coverage: {s}\n", .{f}));
                }
            }
        }

        const cat = try mupdf.inspectCatalog(alloc, io, pdf_path);
        const min_dpi: f64 = if (getOpt(sub_args, "--min-dpi")) |v| std.fmt.parseFloat(f64, v) catch 300.0 else 300.0;
        const pp = try audit.auditPrepress(alloc, io, pdf_path, pages, cat, min_dpi, 300.0, hasFlag(sub_args, "--require-bleed"), hasFlag(sub_args, "--require-ua"), !hasFlag(sub_args, "--no-verapdf"), tmp_tag);
        if (!pp.passed) all_ok = false;

        const verify_links = hasFlag(sub_args, "--verify-links");
        const check_links_off = hasFlag(sub_args, "--check-links-offline");
        if (verify_links or check_links_off) {
            const min_l: usize = if (getOpt(sub_args, "--min-links")) |v| std.fmt.parseInt(usize, v, 10) catch 1 else 1;
            const lr = try links.auditLinks(
                alloc,
                io,
                pdf_path,
                pages,
                getOpt(sub_args, "--citations"),
                lp,
                min_l,
                verify_links,
                10,
                hasFlag(sub_args, "--allow-localhost"),
            );
            if (!lr.passed) all_ok = false;
            if (!as_json) {
                try writeOut(io, try std.fmt.allocPrint(alloc, "[vedit:rule11_links] {s} -> {s} (clickable={d}, unique={d}, mode={s}, failures={d})\n", .{
                    if (lr.passed) "PASS" else "FAIL",
                    pdf_name,
                    lr.clickable_links,
                    lr.unique_uris,
                    if (lr.live_checked) "live" else "offline",
                    lr.failures.len,
                }));
                for (lr.failures[0..@min(lr.failures.len, 10)]) |f| {
                    try writeOut(io, try std.fmt.allocPrint(alloc, "  [!] links p.{d} {s}: {s}\n", .{ f.page, f.kind, f.detail }));
                }
            }
        }

        if (as_json) {
            try writeOut(io, try std.fmt.allocPrint(alloc,
                \\{{ "gate": "audit_all", "pdf": "{s}", "passed": {}, "contrast_passed": {}, "worst_cr": {d:.2}, "geometry_passed": {}, "clipped": {d}, "coverage_ran": {}, "coverage_passed": {}, "min_photo_pct": {d:.1}, "prose_ran": {}, "prose_passed": {}, "prose_checked": {d}, "prose_ungrounded": {d}, "prepress_passed": {}, "verapdf_compliant": {} }}
                \\
            , .{ pdf_name, all_ok, cr.passed, @as(f64, @floatFromInt(cr.worst_cr_x100)) / 100.0, geo.passed, geo.clipped, cov_ran, cov_ok, cov_min_pct, prose_ran, prose_ok, prose_checked, prose_ungr, pp.passed, pp.verapdf.compliant }));
        } else {
            try writeOut(io, try std.fmt.allocPrint(alloc,
                \\[vedit:wcag_contrast] {s} -> {s} (spans={d}, worst_cr={d:.2}:1, violations={d})
                \\[vedit:geometry]      {s} -> {s} (collisions={d}, clipped={d}, overflow={d}, orphans={d}, noisy={d})
                \\[vedit:prepress]      {s} -> {s} (images={d}, unembedded={d}, cmyk_p99={d:.1}%, ua_struct={}, verapdf_pass={d}, verapdf_fail={d})
                \\
            , .{
                if (cr.passed) "PASS" else "FAIL",
                pdf_name,
                cr.total_spans,
                @as(f64, @floatFromInt(cr.worst_cr_x100)) / 100.0,
                cr.total_violations,
                if (geo.passed) "PASS" else "FAIL",
                pdf_name,
                geo.collisions,
                geo.clipped,
                geo.trim_overflow,
                geo.headline_orphans,
                geo.noisy_overlays,
                if (pp.passed) "PASS" else "FAIL",
                pdf_name,
                pp.image_count,
                pp.unembedded_fonts.len,
                @as(f64, @floatFromInt(pp.cmyk_p99_tac_x10)) / 10.0,
                pp.ua_struct_pass,
                pp.verapdf.passed_rules,
                pp.verapdf.failed_rules,
            }));
            for (pp.failures) |f| {
                try writeOut(io, try std.fmt.allocPrint(alloc, "  [!] prepress: {s}\n", .{f}));
            }
        }
        if (!all_ok) std.process.exit(1);
        return;
    }

    writeErr(io, "unknown command. Run `vedit --help`.\n");
    std.process.exit(2);
}

// =============================================================================
// UNIT & p2zig DIFFERENTIAL PARITY TESTS (Debug + -OReleaseSafe)
// =============================================================================
test "p2zig kernels: WCAG contrast, CMYK TAC, collisions, orphans, Rule 10, DPI, grid & archetype" {
    // 1. Pure black on pure white == 21.00:1
    try std.testing.expectEqual(@as(i64, 2100), kernels.wcag_contrast_x100(0, 0, 0, 255, 255, 255));
    // Low-contrast sabotage (#505862 on #051C2C) MUST fail AA
    const bad_cr = kernels.wcag_contrast_x100(0x50, 0x58, 0x62, 0x05, 0x1C, 0x2C);
    try std.testing.expect(bad_cr < 300);
    try std.testing.expect(!kernels.wcag_passes_aa(bad_cr, 110, false));
    // Archival ink (#141A20 on #FAF9F6) MUST pass AA
    const good_cr = kernels.wcag_contrast_x100(0x14, 0x1A, 0x20, 0xFA, 0xF9, 0xF6);
    try std.testing.expect(good_cr > 1500);
    try std.testing.expect(kernels.wcag_passes_aa(good_cr, 92, false));

    // 2. CMYK GCR TAC: pure white = 0%, pure black = 260.0%
    try std.testing.expectEqual(@as(i64, 0), kernels.cmyk_gcr_tac_x10(255, 255, 255));
    try std.testing.expectEqual(@as(i64, 2600), kernels.cmyk_gcr_tac_x10(0, 0, 0));

    // 3. AABB collision kernel: overlapping vs non-overlapping
    try std.testing.expectEqual(@as(i64, 2), kernels.span_collision_kind(800, 1800, 2500, 1940, 950, 1810, 2600, 1950, false));
    try std.testing.expectEqual(@as(i64, 0), kernels.span_collision_kind(800, 1000, 2500, 1140, 800, 1400, 2500, 1540, false));

    // 4. Orphan headline wrap
    try std.testing.expect(kernels.is_orphan_headline(3400, 900, 1, 9));
    try std.testing.expect(!kernels.is_orphan_headline(3400, 2200, 3, 7));

    // 5. Rule 10 signed grounding (catches sign flip -45.0 vs +45.0!)
    const auth = [_]i64{ -4501, 6489600 };
    try std.testing.expect(kernels.rule10_is_grounded_x100(-4500, &auth));
    try std.testing.expect(!kernels.rule10_is_grounded_x100(4500, &auth));
    try std.testing.expect(!kernels.rule10_is_grounded_x100(1499900, &auth));

    // 6. Effective DPI: 100x100px placed at 400x400pt -> 18.0 DPI (180 x10)
    try std.testing.expectEqual(@as(i64, 180), kernels.effective_dpi_x10(100, 100, 4000, 4000));
    // 1200x900px placed at 288x216pt (4x3in) -> 300.0 DPI (3000 x10)
    try std.testing.expectEqual(@as(i64, 3000), kernels.effective_dpi_x10(1200, 900, 2880, 2160));

    // 7. Grid column detector & page archetype classifier
    const x0s = [_]i64{ 54, 54, 54, 330, 330, 330 };
    const x1s = [_]i64{ 290, 290, 290, 558, 558, 558 };
    try std.testing.expectEqual(@as(i64, 2), kernels.detect_grid_columns(&x0s, &x1s, 612));
    try std.testing.expectEqual(@as(i64, 0), kernels.classify_page_archetype(100, 25, 280, 2, 1, 4));
    try std.testing.expectEqual(@as(i64, 1), kernels.classify_page_archetype(950, 8, 220, 1, 4, 8));

    // 8. Bleed edge counter & clip-aware coverage gate
    try std.testing.expectEqual(@as(i64, 3), kernels.bleed_edge_count(300, 300, 300, 0, 612, 792));
    try std.testing.expect(kernels.coverage_passes(60000, 100000, 500, 3, 2));
    try std.testing.expect(!kernels.coverage_passes(40000, 100000, 500, 3, 2));
    try std.testing.expect(!kernels.coverage_passes(60000, 100000, 500, 1, 2));
}

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(mupdf);
    std.testing.refAllDecls(audit);
    std.testing.refAllDecls(links);
    std.testing.refAllDecls(dissect);
    std.testing.refAllDecls(scaffold);
}
