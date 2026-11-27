//! Pillar #2 (Native Zig CLI Tooling): Archetype Registry Listing & Project Scaffolder.
//! `vedit archetypes` lists all dissected/injected PDF archetypes in the harness.
//! `vedit init <target_dir> --archetype <slug>` creates a complete, SHA-256-sealed, Rule-6-latched
//! Typst PDF/UA-1 editorial project cloning the dissected sample's exact Design DNA — ZERO Python required.

const std = @import("std");
const audit = @import("audit.zig");
const mupdf = @import("mupdf.zig");

pub const ArchetypeEntry = struct {
    slug: []const u8,
    source_pdf: []const u8,
    format_class: []const u8,
    polarity: []const u8,
    page_count: i64,
    canvas_bg: []const u8,
    accent_primary: []const u8,
};

pub fn listArchetypes(alloc: std.mem.Allocator, io: std.Io, archetypes_dir: []const u8) ![]ArchetypeEntry {
    var out: std.ArrayList(ArchetypeEntry) = .empty;
    var dir = std.Io.Dir.cwd().openDir(io, archetypes_dir, .{ .iterate = true }) catch return &.{};
    defer dir.close(io);

    var it = dir.iterate();
    while (try it.next(io)) |ent| {
        if (ent.kind != .directory) continue;
        const bp_path = try std.fmt.allocPrint(alloc, "{s}/{s}/blueprint.json", .{ archetypes_dir, ent.name });
        const raw = std.Io.Dir.cwd().readFileAlloc(io, bp_path, alloc, .unlimited) catch continue;
        const parsed = std.json.parseFromSliceLeaky(std.json.Value, alloc, raw, .{}) catch continue;
        if (parsed != .object) continue;
        const obj = parsed.object;
        const src_pdf = if (obj.get("source_pdf")) |v| (if (v == .string) v.string else "") else "";
        const fmt_cls = if (obj.get("format_class")) |v| (if (v == .string) v.string else "") else "";
        const pol = if (obj.get("polarity")) |v| (if (v == .string) v.string else "") else "";
        const pg_cnt: i64 = if (obj.get("page_count")) |v| (if (v == .integer) v.integer else 0) else 0;
        var bg: []const u8 = "#FAF9F6";
        var a1: []const u8 = "#035E9E";
        if (obj.get("palette_60_30_10")) |pv| {
            if (pv == .object) {
                if (pv.object.get("canvas_bg")) |cv| if (cv == .string) {
                    bg = cv.string;
                };
                if (pv.object.get("accent_primary")) |av| if (av == .string) {
                    a1 = av.string;
                };
            }
        }
        try out.append(alloc, .{
            .slug = try alloc.dupe(u8, ent.name),
            .source_pdf = try alloc.dupe(u8, src_pdf),
            .format_class = try alloc.dupe(u8, fmt_cls),
            .polarity = try alloc.dupe(u8, pol),
            .page_count = pg_cnt,
            .canvas_bg = try alloc.dupe(u8, bg),
            .accent_primary = try alloc.dupe(u8, a1),
        });
    }
    std.mem.sort(ArchetypeEntry, out.items, {}, struct {
        fn lessThan(_: void, a: ArchetypeEntry, b: ArchetypeEntry) bool {
            return std.mem.order(u8, a.slug, b.slug) == .lt;
        }
    }.lessThan);
    return out.toOwnedSlice(alloc);
}

/// Update `archetypes/registry.json` index so agents can discover every injected archetype in 1 read.
pub fn writeRegistryIndex(alloc: std.mem.Allocator, io: std.Io, archetypes_dir: []const u8) !usize {
    const entries = try listArchetypes(alloc, io, archetypes_dir);
    var buf: std.ArrayList(u8) = .empty;
    try buf.appendSlice(alloc, "{\n  \"schema_version\": \"vedit.registry.v1\",\n  \"archetypes\": [\n");
    for (entries, 0..) |e, idx| {
        const comma: []const u8 = if (idx + 1 < entries.len) "," else "";
        const bp_rel = try std.fmt.allocPrint(alloc, "{s}/blueprint.json", .{e.slug});
        const sk_rel = try std.fmt.allocPrint(alloc, "{s}/skeleton.typ", .{e.slug});
        const ac_rel = try std.fmt.allocPrint(alloc, "{s}/AGENT_CARD.md", .{e.slug});
        try buf.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\    {{ "slug": {s}, "source_pdf": {s}, "format_class": {s}, "polarity": {s}, "page_count": {d}, "canvas_bg": {s}, "accent_primary": {s}, "blueprint": {s}, "skeleton": {s}, "agent_card": {s} }}{s}
            \\
        , .{
            try mupdf.jsonString(alloc, e.slug),
            try mupdf.jsonString(alloc, e.source_pdf),
            try mupdf.jsonString(alloc, e.format_class),
            try mupdf.jsonString(alloc, e.polarity),
            e.page_count,
            try mupdf.jsonString(alloc, e.canvas_bg),
            try mupdf.jsonString(alloc, e.accent_primary),
            try mupdf.jsonString(alloc, bp_rel),
            try mupdf.jsonString(alloc, sk_rel),
            try mupdf.jsonString(alloc, ac_rel),
            comma,
        }));
    }
    try buf.appendSlice(alloc, "  ]\n}\n");
    const reg_path = try std.fmt.allocPrint(alloc, "{s}/registry.json", .{archetypes_dir});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = reg_path, .data = buf.items });
    return entries.len;
}

/// Scaffold a brand-new verified, SHA-256-sealed, Rule-6-latched editorial project from an injected archetype.
pub fn initProjectFromArchetype(
    alloc: std.mem.Allocator,
    io: std.Io,
    target_dir: []const u8,
    archetypes_dir: []const u8,
    archetype_slug: []const u8,
    title: []const u8,
) !void {
    const skel_path = try std.fmt.allocPrint(alloc, "{s}/{s}/skeleton.typ", .{ archetypes_dir, archetype_slug });
    const skel_src = std.Io.Dir.cwd().readFileAlloc(io, skel_path, alloc, .unlimited) catch return error.ArchetypeNotFound;

    var trim_w_int: i64 = 612;
    var trim_h_int: i64 = 792;
    const bp_path = try std.fmt.allocPrint(alloc, "{s}/{s}/blueprint.json", .{ archetypes_dir, archetype_slug });
    if (std.Io.Dir.cwd().readFileAlloc(io, bp_path, alloc, .unlimited)) |bp_raw| {
        if (std.json.parseFromSliceLeaky(std.json.Value, alloc, bp_raw, .{})) |bp_val| {
            if (bp_val == .object) {
                if (bp_val.object.get("trim_pt")) |tp| {
                    if (tp == .array and tp.array.items.len >= 2) {
                        trim_w_int = switch (tp.array.items[0]) {
                            .float => |f| mupdf.checkedRoundInt(i64, f, 36.0, 20000.0) catch trim_w_int,
                            .integer => |i| i,
                            else => trim_w_int,
                        };
                        trim_h_int = switch (tp.array.items[1]) {
                            .float => |f| mupdf.checkedRoundInt(i64, f, 36.0, 20000.0) catch trim_h_int,
                            .integer => |i| i,
                            else => trim_h_int,
                        };
                    }
                }
            }
        } else |err| return err;
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    }

    const raw_dir = try std.fmt.allocPrint(alloc, "{s}/data/raw", .{target_dir});
    const rep_dir = try std.fmt.allocPrint(alloc, "{s}/report", .{target_dir});
    try std.Io.Dir.cwd().createDirPath(io, raw_dir);
    try std.Io.Dir.cwd().createDirPath(io, rep_dir);

    // 1. Immutable raw seed dataset + real cryptographic SHA-256 manifest computed by Zig std.crypto
    const raw_csv =
        \\metric_id,value,unit,note
        \\primary_index,142.8,pts,Audited baseline observation
        \\delta_yoy_pct,18.4,%,Year-over-year structural shift
        \\verification_coverage_pct,100.0,%,Provenance ledger match rate
        \\
    ;
    const raw_csv_path = try std.fmt.allocPrint(alloc, "{s}/seed_telemetry.csv", .{raw_dir});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = raw_csv_path, .data = raw_csv });
    const raw_sha = try audit.sha256HexFile(alloc, io, raw_csv_path);

    const manifest_txt = try std.fmt.allocPrint(alloc, "{s}  data/raw/seed_telemetry.csv\n", .{raw_sha[0..64]});
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = try std.fmt.allocPrint(alloc, "{s}/data/manifest.sha256", .{target_dir}),
        .data = manifest_txt,
    });

    // 2. Sealed summary_metrics.json + 1:1 Rule 4 provenance_ledger.json (RFC 8259 escaped)
    const j_title = try mupdf.jsonString(alloc, title);
    const sub_raw = try std.fmt.allocPrint(alloc, "Synthesized directly from dissected PDF archetype '{s}' via Sovereign Zig vedit harness.", .{archetype_slug});
    const j_sub = try mupdf.jsonString(alloc, sub_raw);
    const kick_raw = try std.fmt.allocPrint(alloc, "VERIFIED ARCHETYPE PUBLICATION · {s}", .{archetype_slug});
    const j_kick = try mupdf.jsonString(alloc, kick_raw);
    const summary_json = try std.fmt.allocPrint(alloc,
        \\{{
        \\  "metadata": {{
        \\    "title": {s},
        \\    "subtitle": {s},
        \\    "author": "Verifiable Editorial Zig Harness",
        \\    "kicker": {s}
        \\  }},
        \\  "kpis": [
        \\    {{ "label": "Primary Index", "display_value": "142.8 pts", "note": "Audited baseline" }},
        \\    {{ "label": "Annual Shift", "display_value": "+18.4%", "note": "Verified delta" }},
        \\    {{ "label": "Ledger Coverage", "display_value": "100.0%", "note": "SHA-256 sealed" }}
        \\  ],
        \\  "metrics": {{
        \\    "primary_index": 142.8,
        \\    "delta_yoy_pct": 18.4,
        \\    "verification_coverage_pct": 100.0
        \\  }}
        \\}}
        \\
    , .{ j_title, j_sub, j_kick });
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = try std.fmt.allocPrint(alloc, "{s}/data/summary_metrics.json", .{target_dir}),
        .data = summary_json,
    });

    const ledger_json = try std.fmt.allocPrint(alloc,
        \\[
        \\  {{
        \\    "metric_id": "primary_index",
        \\    "value": 142.8,
        \\    "unit": "pts",
        \\    "source_document": "data/raw/seed_telemetry.csv",
        \\    "source_locator": "row 1",
        \\    "raw_file_sha256": "{s}"
        \\  }},
        \\  {{
        \\    "metric_id": "delta_yoy_pct",
        \\    "value": 18.4,
        \\    "unit": "%",
        \\    "source_document": "data/raw/seed_telemetry.csv",
        \\    "source_locator": "row 2",
        \\    "raw_file_sha256": "{s}"
        \\  }},
        \\  {{
        \\    "metric_id": "verification_coverage_pct",
        \\    "value": 100.0,
        \\    "unit": "%",
        \\    "source_document": "data/raw/seed_telemetry.csv",
        \\    "source_locator": "row 3",
        \\    "raw_file_sha256": "{s}"
        \\  }}
        \\]
        \\
    , .{ raw_sha[0..64], raw_sha[0..64], raw_sha[0..64] });
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = try std.fmt.allocPrint(alloc, "{s}/data/provenance_ledger.json", .{target_dir}),
        .data = ledger_json,
    });

    const ctx_raw = try std.fmt.allocPrint(alloc, "Dissected trim width and height in PostScript points ({d}x{d} pt) from archetype '{s}', plus 12-char SHA-256 ledger digest prefix length.", .{ trim_w_int, trim_h_int, archetype_slug });
    const src_raw = try std.fmt.allocPrint(alloc, "archetypes/{s}/blueprint.json", .{archetype_slug});
    const citations_json = try std.fmt.allocPrint(alloc,
        \\{{
        \\  "publication": {s},
        \\  "purpose": "Structural page-trim metadata cloned from archetype blueprint.json for Rule 10 provenance grounding.",
        \\  "citations": [
        \\    {{
        \\      "id": "archetype_trim_dimensions",
        \\      "values": [{d}, {d}, 12],
        \\      "context": {s},
        \\      "source": {s},
        \\      "doi_or_url": "https://github.com/gke0op/verifiable-editorial-skills"
        \\    }}
        \\  ]
        \\}}
        \\
    , .{ j_title, trim_w_int, trim_h_int, try mupdf.jsonString(alloc, ctx_raw), try mupdf.jsonString(alloc, src_raw) });
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = try std.fmt.allocPrint(alloc, "{s}/data/background_citations.json", .{target_dir}),
        .data = citations_json,
    });

    // 3. Copy archetype Typst skeleton -> report/main.typ + zero-Python build.sh
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = try std.fmt.allocPrint(alloc, "{s}/main.typ", .{rep_dir}),
        .data = skel_src,
    });

    const build_sh =
        \\#!/usr/bin/env bash
        \\set -euo pipefail
        \\DIR="$(cd "$(dirname "$0")" && pwd)"
        \\VEDIT_BIN="${VEDIT_BIN:-vedit}"
        \\FONT_DIR="${VEDIT_FONT_DIR:-$HOME/.cache/verifiable-editorial/fonts}"
        \\"$VEDIT_BIN" latch "$DIR"
        \\typst compile --root "$DIR" --font-path "$FONT_DIR" --pdf-standard ua-1 \
        \\  "$DIR/report/main.typ" "$DIR/report/OUTPUT_UA1.pdf"
        \\"$VEDIT_BIN" audit-all "$DIR/report/OUTPUT_UA1.pdf" \
        \\  --ledger "$DIR/data/provenance_ledger.json" \
        \\  --summary "$DIR/data/summary_metrics.json" \
        \\  --citations "$DIR/data/background_citations.json" \
        \\  --manifest "$DIR/data/manifest.sha256" \
        \\  --check-links-offline \
        \\  --require-ua
        \\
    ;
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = try std.fmt.allocPrint(alloc, "{s}/build.sh", .{target_dir}),
        .data = build_sh,
    });
}
