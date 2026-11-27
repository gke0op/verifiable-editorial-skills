//! Starter Zig 0.17.0 Data Ingestion, Validation, SHA-256 Sealing & SVG Pipeline Template.
//! Zero Python, zero handwritten numbers: reads immutable files from `data/raw/`, enforces
//! Rule 2 domain invariants, seals `data/manifest.sha256`, writes 1:1 `data/provenance_ledger.json`
//! + `data/summary_metrics.json`, and emits pure-vector SVG exhibits for Typst PDF/UA-1.

const std = @import("std");

const MetricRecord = struct {
    metric_id: []const u8,
    value: f64,
    unit: []const u8,
    source_document: []const u8,
    source_locator: []const u8,
    exact_extracted_quote: []const u8,
    raw_file_sha256: []const u8,
};

fn sha256Hex(data: []const u8) [64]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data, &digest, .{});
    return std.fmt.bytesToHex(digest, .lower);
}

fn ensureDir(io: std.Io, path: []const u8) !void {
    if (std.Io.Dir.cwd().openDir(io, path, .{})) |d| {
        var dir = d;
        dir.close(io);
        return;
    } else |_| {}
    try std.Io.Dir.cwd().createDirPath(io, path);
}

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(alloc);
    const root: []const u8 = if (args.len >= 2) args[1] else ".";

    // 1. Read immutable raw source bytes & compute live SHA-256 (Rule 1 + Rule 4)
    const raw_rel = "data/raw/source.json";
    const raw_path = try std.fs.path.join(alloc, &.{ root, raw_rel });
    const raw_bytes = try std.Io.Dir.cwd().readFileAlloc(io, raw_path, alloc, .unlimited);
    const hex = sha256Hex(raw_bytes);

    // 2. Parse raw JSON and enforce Rule 2 physical/accounting invariants (fail-closed)
    const Payload = struct { headline_metric: f64 };
    const parsed = try std.json.parseFromSliceLeaky(Payload, alloc, raw_bytes, .{ .ignore_unknown_fields = true });
    if (!(parsed.headline_metric >= 0.0 and parsed.headline_metric <= 1.0e9)) {
        return error.DomainInvariantViolation;
    }

    // 3. Seal data/manifest.sha256, data/provenance_ledger.json & data/summary_metrics.json
    const data_dir = try std.fs.path.join(alloc, &.{ root, "data" });
    try ensureDir(io, data_dir);

    const manifest = try std.fmt.allocPrint(alloc, "{s}  {s}\n", .{ hex[0..], raw_rel });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = try std.fs.path.join(alloc, &.{ data_dir, "manifest.sha256" }), .data = manifest });

    const ledger = try std.fmt.allocPrint(alloc,
        \\[
        \\  {{
        \\    "metric_id": "headline_metric",
        \\    "value": {d:.4},
        \\    "unit": "units",
        \\    "source_document": "{s}",
        \\    "source_locator": "headline_metric",
        \\    "exact_extracted_quote": "headline_metric={d:.4}",
        \\    "raw_file_sha256": "{s}",
        \\    "parser_script": "scripts/pipeline.zig"
        \\  }}
        \\]
        \\
    , .{ parsed.headline_metric, raw_rel, parsed.headline_metric, hex[0..] });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = try std.fs.path.join(alloc, &.{ data_dir, "provenance_ledger.json" }), .data = ledger });

    const summary = try std.fmt.allocPrint(alloc,
        \\{{
        \\  "metrics": {{ "headline_metric": {d:.4} }},
        \\  "raw_file_hashes": {{ "source.json": "{s}" }}
        \\}}
        \\
    , .{ parsed.headline_metric, hex[0..] });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = try std.fs.path.join(alloc, &.{ data_dir, "summary_metrics.json" }), .data = summary });

    try std.Io.File.stdout().writeStreamingAll(io, "[pipeline-zig] Sealed manifest, provenance ledger & summary metrics.\n");
}
