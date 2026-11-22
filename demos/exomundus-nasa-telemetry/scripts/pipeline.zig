//! Pure Zig 0.17.0 Zero-Python Open-Data Reality Compiler, SHA-256 Sealer & Vector SVG Engine
//! for `EXOMUNDUS — Census of Confirmed Exoplanets (1992–2026)` (NASA Exoplanet Archive TAP API).
//!
//! Compile & run:
//!   zig run -O ReleaseSafe scripts/pipeline.zig -- <demo_dir>

const std = @import("std");

const CensusRow = struct {
    disc_year: ?i64 = null,
    discoverymethod: []const u8 = "",
    n: i64 = 0,
};

const ValleyRow = struct {
    pl_rade: f64,
    pl_orbper: f64,
};

const MassRadRow = struct {
    pl_name: []const u8 = "",
    discoverymethod: []const u8 = "",
    pl_rade: f64,
    pl_bmasse: f64,
    pl_orbper: ?f64 = null,
};

const BenchmarkRow = struct {
    pl_name: []const u8,
    discoverymethod: []const u8,
    disc_year: i64,
    pl_orbper: ?f64 = null,
    pl_rade: ?f64 = null,
    pl_bmasse: ?f64 = null,
    pl_eqt: ?f64 = null,
    sy_dist: ?f64 = null,
    st_teff: ?f64 = null,
};

const CompletenessRow = struct {
    n_total: i64,
    n_with_rad: i64,
    n_with_mass: i64,
    n_with_eqt: i64,
    min_yr: i64,
    max_yr: i64,
};

const LedgerEntry = struct {
    metric_id: []const u8,
    value: f64,
    is_int: bool,
    unit: []const u8,
    source_document: []const u8,
    source_locator: []const u8,
    raw_file_sha256: [64]u8,
};

const YearBucket = struct {
    year: i64,
    transit: i64 = 0,
    rv: i64 = 0,
    micro: i64 = 0,
    other: i64 = 0,
    pub fn total(self: YearBucket) i64 {
        return self.transit + self.rv + self.micro + self.other;
    }
};

fn sha256Hex(bytes: []const u8) [64]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    const hex = "0123456789abcdef";
    var out: [64]u8 = undefined;
    for (digest, 0..) |b, i| {
        out[i * 2] = hex[b >> 4];
        out[i * 2 + 1] = hex[b & 0x0f];
    }
    return out;
}

fn round2(v: f64) f64 {
    return @round(v * 100.0) / 100.0;
}

fn round1(v: f64) f64 {
    return @round(v * 10.0) / 10.0;
}

fn addMetric(
    alloc: std.mem.Allocator,
    ledger: *std.ArrayList(LedgerEntry),
    id: []const u8,
    val: f64,
    is_int: bool,
    unit: []const u8,
    src_doc: []const u8,
    locator: []const u8,
    sha: [64]u8,
) !void {
    try ledger.append(alloc, .{
        .metric_id = id,
        .value = val,
        .is_int = is_int,
        .unit = unit,
        .source_document = src_doc,
        .source_locator = locator,
        .raw_file_sha256 = sha,
    });
}

fn formatJsonOptFloat(alloc: std.mem.Allocator, v: ?f64) ![]const u8 {
    if (v) |fv| return std.fmt.allocPrint(alloc, "{d:.3}", .{fv});
    return "null";
}

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(alloc);
    const demo_dir: []const u8 = if (args.len >= 2) args[1] else ".";

    const raw_files = [_][]const u8{
        "nasa_benchmarks.json",
        "nasa_census_by_year_method.json",
        "nasa_completeness.json",
        "nasa_mass_radius.json",
        "nasa_radius_valley.json",
    };

    var raw_bytes: [5][]u8 = undefined;
    var raw_shas: [5][64]u8 = undefined;
    var manifest_buf: std.ArrayList(u8) = .empty;

    for (raw_files, 0..) |fname, idx| {
        const fpath = try std.fmt.allocPrint(alloc, "{s}/data/raw/{s}", .{ demo_dir, fname });
        raw_bytes[idx] = try std.Io.Dir.cwd().readFileAlloc(io, fpath, alloc, .unlimited);
        raw_shas[idx] = sha256Hex(raw_bytes[idx]);
        try manifest_buf.appendSlice(alloc, try std.fmt.allocPrint(alloc, "{s}  data/raw/{s}\n", .{ raw_shas[idx][0..64], fname }));
    }

    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = try std.fmt.allocPrint(alloc, "{s}/data/manifest.sha256", .{demo_dir}),
        .data = manifest_buf.items,
    });

    // Parse all 5 immutable NASA JSON datasets
    const benchmarks = try std.json.parseFromSliceLeaky([]BenchmarkRow, alloc, raw_bytes[0], .{ .ignore_unknown_fields = true });
    const census_rows = try std.json.parseFromSliceLeaky([]CensusRow, alloc, raw_bytes[1], .{ .ignore_unknown_fields = true });
    const comp_rows = try std.json.parseFromSliceLeaky([]CompletenessRow, alloc, raw_bytes[2], .{ .ignore_unknown_fields = true });
    const mr_rows = try std.json.parseFromSliceLeaky([]MassRadRow, alloc, raw_bytes[3], .{ .ignore_unknown_fields = true });
    const rv_rows = try std.json.parseFromSliceLeaky([]ValleyRow, alloc, raw_bytes[4], .{ .ignore_unknown_fields = true });

    // =========================================================================
    // RULE 2: ASTROPHYSICAL REALITY & ACCOUNTING INVARIANT COMPILER (FAIL CLOSED)
    // =========================================================================
    if (comp_rows.len != 1) return error.InvalidCompletenessTable;
    const comp = comp_rows[0];
    if (comp.n_total <= 0 or comp.n_with_rad > comp.n_total or comp.n_with_mass > comp.n_total or comp.n_with_eqt > comp.n_total) {
        return error.CompletenessInvariantViolated;
    }
    if (comp.min_yr < 1990 or comp.max_yr > 2027 or comp.min_yr > comp.max_yr) {
        return error.YearDomainViolated;
    }

    var sum_census: i64 = 0;
    var cnt_transit: i64 = 0;
    var cnt_rv: i64 = 0;
    var cnt_micro: i64 = 0;
    var cnt_imaging: i64 = 0;
    var cnt_other: i64 = 0;

    // Year buckets 1992..2026 (35 years)
    const yr_min: i64 = comp.min_yr;
    const yr_max: i64 = comp.max_yr;
    const n_years: usize = @intCast(yr_max - yr_min + 1);
    const years = try alloc.alloc(YearBucket, n_years);
    for (years, 0..) |*yb, i| {
        yb.* = .{ .year = yr_min + @as(i64, @intCast(i)) };
    }

    for (census_rows) |row| {
        if (row.n < 0) return error.NegativePlanetCount;
        sum_census += row.n;
        const is_tr = std.mem.eql(u8, row.discoverymethod, "Transit");
        const is_rv = std.mem.eql(u8, row.discoverymethod, "Radial Velocity");
        const is_mi = std.mem.eql(u8, row.discoverymethod, "Microlensing");
        const is_im = std.mem.eql(u8, row.discoverymethod, "Imaging");
        if (is_tr) cnt_transit += row.n else if (is_rv) cnt_rv += row.n else if (is_mi) cnt_micro += row.n else if (is_im) cnt_imaging += row.n else cnt_other += row.n;

        if (row.disc_year) |dy| {
            if (dy >= yr_min and dy <= yr_max) {
                const yi: usize = @intCast(dy - yr_min);
                if (is_tr) years[yi].transit += row.n else if (is_rv) years[yi].rv += row.n else if (is_mi) years[yi].micro += row.n else years[yi].other += row.n;
            }
        }
    }
    if (sum_census != comp.n_total) return error.CrossTableCensusMismatch;

    var peak_year: i64 = yr_min;
    var peak_year_n: i64 = 0;
    for (years) |yb| {
        if (yb.total() > peak_year_n) {
            peak_year_n = yb.total();
            peak_year = yb.year;
        }
    }

    // Validate Fulton Radius Valley sample & bin into 18 log-spaced bins across [0.6, 5.5] R_earth
    const n_bins: usize = 18;
    const log_r_min: f64 = @log10(0.6);
    const log_r_max: f64 = @log10(5.5);
    const bin_step: f64 = (log_r_max - log_r_min) / @as(f64, @floatFromInt(n_bins));
    var bin_counts: [n_bins]i64 = @splat(0);
    var bin_centers: [n_bins]f64 = undefined;
    for (0..n_bins) |bi| {
        const mid_log = log_r_min + (@as(f64, @floatFromInt(bi)) + 0.5) * bin_step;
        bin_centers[bi] = std.math.pow(f64, 10.0, mid_log);
    }

    var n_super_earth_zone: i64 = 0; // 1.0..1.6 R_e
    var n_valley_zone: i64 = 0; // 1.6..2.0 R_e
    var n_sub_neptune_zone: i64 = 0; // 2.0..3.5 R_e
    for (rv_rows) |rv| {
        if (rv.pl_rade < 0.5 or rv.pl_rade > 6.0 or rv.pl_orbper <= 0.0 or rv.pl_orbper > 100.0) {
            return error.RadiusValleyBoundViolated;
        }
        if (rv.pl_rade >= 1.0 and rv.pl_rade < 1.6) n_super_earth_zone += 1 else if (rv.pl_rade >= 1.6 and rv.pl_rade <= 2.0) n_valley_zone += 1 else if (rv.pl_rade > 2.0 and rv.pl_rade <= 3.5) n_sub_neptune_zone += 1;

        if (rv.pl_rade >= 0.6 and rv.pl_rade <= 5.5) {
            const lr = @log10(rv.pl_rade);
            const raw_bi: i64 = @intFromFloat(@floor((lr - log_r_min) / bin_step));
            const bi: usize = @intCast(std.math.clamp(raw_bi, 0, @as(i64, n_bins - 1)));
            bin_counts[bi] += 1;
        }
    }

    var se_peak_re: f64 = 1.3;
    var se_peak_cnt: i64 = 0;
    var val_trough_re: f64 = 1.8;
    var val_trough_cnt: i64 = 999999;
    var sn_peak_re: f64 = 2.4;
    var sn_peak_cnt: i64 = 0;
    for (0..n_bins) |bi| {
        const rc = bin_centers[bi];
        const bc = bin_counts[bi];
        if (rc >= 1.0 and rc <= 1.65 and bc > se_peak_cnt) {
            se_peak_cnt = bc;
            se_peak_re = rc;
        }
        if (rc > 1.65 and rc <= 2.05 and bc < val_trough_cnt) {
            val_trough_cnt = bc;
            val_trough_re = rc;
        }
        if (rc > 2.05 and rc <= 3.2 and bc > sn_peak_cnt) {
            sn_peak_cnt = bc;
            sn_peak_re = rc;
        }
    }

    // Validate Mass-Radius sample
    for (mr_rows) |mr| {
        if (mr.pl_rade <= 0.0 or mr.pl_rade > 100.0 or mr.pl_bmasse <= 0.0 or mr.pl_bmasse > 50000.0) {
            return error.MassRadiusBoundViolated;
        }
    }
    const n_both: i64 = @intCast(mr_rows.len);
    const n_valley_sample: i64 = @intCast(rv_rows.len);

    // Sort benchmarks by sy_dist ascending (null distance placed at end)
    std.mem.sort(BenchmarkRow, benchmarks, {}, struct {
        fn lessThan(_: void, a: BenchmarkRow, b: BenchmarkRow) bool {
            const da = a.sy_dist orelse 1e9;
            const db = b.sy_dist orelse 1e9;
            return da < db;
        }
    }.lessThan);

    // =========================================================================
    // RULE 4: BUILD 1:1 ATOMIC PROVENANCE LEDGER & SUMMARY METRICS JSON
    // =========================================================================
    var ledger: std.ArrayList(LedgerEntry) = .empty;
    const tot_f: f64 = @floatFromInt(comp.n_total);
    const tr_pct = round1((@as(f64, @floatFromInt(cnt_transit)) / tot_f) * 100.0);
    const rv_pct = round1((@as(f64, @floatFromInt(cnt_rv)) / tot_f) * 100.0);
    const mi_pct = round1((@as(f64, @floatFromInt(cnt_micro)) / tot_f) * 100.0);
    const im_pct = round1((@as(f64, @floatFromInt(cnt_imaging)) / tot_f) * 100.0);
    const oth_pct = round1((@as(f64, @floatFromInt(cnt_other)) / tot_f) * 100.0);

    const rad_pct = round1((@as(f64, @floatFromInt(comp.n_with_rad)) / tot_f) * 100.0);
    const mass_pct = round1((@as(f64, @floatFromInt(comp.n_with_mass)) / tot_f) * 100.0);
    const both_pct = round1((@as(f64, @floatFromInt(n_both)) / tot_f) * 100.0);
    const eqt_pct = round1((@as(f64, @floatFromInt(comp.n_with_eqt)) / tot_f) * 100.0);
    const miss_rad = comp.n_total - comp.n_with_rad;
    const miss_mass = comp.n_total - comp.n_with_mass;
    const miss_mass_pct = round1((@as(f64, @floatFromInt(miss_mass)) / tot_f) * 100.0);

    const sha_comp = raw_shas[2];
    const sha_cens = raw_shas[1];
    const sha_mr = raw_shas[3];
    const sha_rv = raw_shas[4];
    const sha_bm = raw_shas[0];

    try addMetric(alloc, &ledger, "total_confirmed_planets", tot_f, true, "planets", "data/raw/nasa_completeness.json", "ps default_flag=1 count(*)", sha_comp);
    try addMetric(alloc, &ledger, "planets_with_radius", @floatFromInt(comp.n_with_rad), true, "planets", "data/raw/nasa_completeness.json", "count(pl_rade)", sha_comp);
    try addMetric(alloc, &ledger, "planets_with_mass", @floatFromInt(comp.n_with_mass), true, "planets", "data/raw/nasa_completeness.json", "count(pl_bmasse)", sha_comp);
    try addMetric(alloc, &ledger, "planets_with_both_mr", @floatFromInt(n_both), true, "planets", "data/raw/nasa_mass_radius.json", "len(non-null pl_rade & pl_bmasse)", sha_mr);
    try addMetric(alloc, &ledger, "planets_with_eqt", @floatFromInt(comp.n_with_eqt), true, "planets", "data/raw/nasa_completeness.json", "count(pl_eqt)", sha_comp);
    try addMetric(alloc, &ledger, "missing_radius_count", @floatFromInt(miss_rad), true, "planets", "data/raw/nasa_completeness.json", "n_total - n_with_rad", sha_comp);
    try addMetric(alloc, &ledger, "missing_mass_count", @floatFromInt(miss_mass), true, "planets", "data/raw/nasa_completeness.json", "n_total - n_with_mass", sha_comp);
    try addMetric(alloc, &ledger, "missing_mass_pct", miss_mass_pct, false, "%", "data/raw/nasa_completeness.json", "missing_mass / n_total * 100", sha_comp);
    try addMetric(alloc, &ledger, "radius_completeness_pct", rad_pct, false, "%", "data/raw/nasa_completeness.json", "n_with_rad / n_total * 100", sha_comp);
    try addMetric(alloc, &ledger, "mass_completeness_pct", mass_pct, false, "%", "data/raw/nasa_completeness.json", "n_with_mass / n_total * 100", sha_comp);
    try addMetric(alloc, &ledger, "both_mr_completeness_pct", both_pct, false, "%", "data/raw/nasa_mass_radius.json", "n_both / n_total * 100", sha_mr);
    try addMetric(alloc, &ledger, "eqt_completeness_pct", eqt_pct, false, "%", "data/raw/nasa_completeness.json", "n_with_eqt / n_total * 100", sha_comp);
    try addMetric(alloc, &ledger, "transit_count", @floatFromInt(cnt_transit), true, "planets", "data/raw/nasa_census_by_year_method.json", "sum(discoverymethod='Transit')", sha_cens);
    try addMetric(alloc, &ledger, "transit_share_pct", tr_pct, false, "%", "data/raw/nasa_census_by_year_method.json", "transit / total * 100", sha_cens);
    try addMetric(alloc, &ledger, "rv_count", @floatFromInt(cnt_rv), true, "planets", "data/raw/nasa_census_by_year_method.json", "sum(discoverymethod='Radial Velocity')", sha_cens);
    try addMetric(alloc, &ledger, "rv_share_pct", rv_pct, false, "%", "data/raw/nasa_census_by_year_method.json", "rv / total * 100", sha_cens);
    try addMetric(alloc, &ledger, "microlensing_count", @floatFromInt(cnt_micro), true, "planets", "data/raw/nasa_census_by_year_method.json", "sum(discoverymethod='Microlensing')", sha_cens);
    try addMetric(alloc, &ledger, "microlensing_share_pct", mi_pct, false, "%", "data/raw/nasa_census_by_year_method.json", "microlensing / total * 100", sha_cens);
    try addMetric(alloc, &ledger, "imaging_count", @floatFromInt(cnt_imaging), true, "planets", "data/raw/nasa_census_by_year_method.json", "sum(discoverymethod='Imaging')", sha_cens);
    try addMetric(alloc, &ledger, "imaging_share_pct", im_pct, false, "%", "data/raw/nasa_census_by_year_method.json", "imaging / total * 100", sha_cens);
    try addMetric(alloc, &ledger, "other_methods_count", @floatFromInt(cnt_other), true, "planets", "data/raw/nasa_census_by_year_method.json", "sum(other methods)", sha_cens);
    try addMetric(alloc, &ledger, "other_methods_share_pct", oth_pct, false, "%", "data/raw/nasa_census_by_year_method.json", "other / total * 100", sha_cens);
    try addMetric(alloc, &ledger, "peak_discovery_year", @floatFromInt(peak_year), true, "year", "data/raw/nasa_census_by_year_method.json", "argmax annual sum", sha_cens);
    try addMetric(alloc, &ledger, "peak_discovery_count", @floatFromInt(peak_year_n), true, "planets", "data/raw/nasa_census_by_year_method.json", "max annual sum", sha_cens);
    try addMetric(alloc, &ledger, "valley_sample_count", @floatFromInt(n_valley_sample), true, "planets", "data/raw/nasa_radius_valley.json", "0.5..6.0 R_e, P<=100d", sha_rv);
    try addMetric(alloc, &ledger, "super_earth_peak_re", round2(se_peak_re), false, "R_earth", "data/raw/nasa_radius_valley.json", "log-bin mode [1.0,1.65]", sha_rv);
    try addMetric(alloc, &ledger, "super_earth_zone_count", @floatFromInt(n_super_earth_zone), true, "planets", "data/raw/nasa_radius_valley.json", "count(1.0<=R<1.6)", sha_rv);
    try addMetric(alloc, &ledger, "valley_trough_re", round2(val_trough_re), false, "R_earth", "data/raw/nasa_radius_valley.json", "log-bin min (1.65,2.05]", sha_rv);
    try addMetric(alloc, &ledger, "valley_zone_count", @floatFromInt(n_valley_zone), true, "planets", "data/raw/nasa_radius_valley.json", "count(1.6<=R<=2.0)", sha_rv);
    try addMetric(alloc, &ledger, "sub_neptune_peak_re", round2(sn_peak_re), false, "R_earth", "data/raw/nasa_radius_valley.json", "log-bin mode (2.05,3.2]", sha_rv);
    try addMetric(alloc, &ledger, "sub_neptune_zone_count", @floatFromInt(n_sub_neptune_zone), true, "planets", "data/raw/nasa_radius_valley.json", "count(2.0<R<=3.5)", sha_rv);
    try addMetric(alloc, &ledger, "benchmark_count", @floatFromInt(benchmarks.len), true, "planets", "data/raw/nasa_benchmarks.json", "len(benchmarks)", sha_bm);

    // Register benchmark planet metrics for 100% Rule 10 prose coverage
    for (benchmarks) |bm| {
        if (bm.pl_rade != null and bm.pl_bmasse != null) {
            const rad = bm.pl_rade.?;
            const mass = bm.pl_bmasse.?;
            const rho_gcm3 = round2(5.514 * (mass / (rad * rad * rad)));
            var key_buf: [64]u8 = undefined;
            var klen: usize = 0;
            for (bm.pl_name) |ch| {
                if (klen >= 48) break;
                if ((ch >= 'A' and ch <= 'Z')) {
                    key_buf[klen] = ch + 32;
                    klen += 1;
                } else if ((ch >= 'a' and ch <= 'z') or (ch >= '0' and ch <= '9')) {
                    key_buf[klen] = ch;
                    klen += 1;
                } else {
                    key_buf[klen] = '_';
                    klen += 1;
                }
            }
            const mid = try std.fmt.allocPrint(alloc, "rho_{s}_gcm3", .{key_buf[0..klen]});
            try addMetric(alloc, &ledger, mid, rho_gcm3, false, "g/cm3", "data/raw/nasa_benchmarks.json", bm.pl_name, sha_bm);
        }
    }

    // Write data/provenance_ledger.json
    var led_buf: std.ArrayList(u8) = .empty;
    try led_buf.appendSlice(alloc, "[\n");
    for (ledger.items, 0..) |ent, i| {
        const comma: []const u8 = if (i + 1 < ledger.items.len) "," else "";
        const val_s = if (ent.is_int)
            try std.fmt.allocPrint(alloc, "{d}", .{@as(i64, @intFromFloat(@round(ent.value)))})
        else
            try std.fmt.allocPrint(alloc, "{d:.2}", .{ent.value});
        try led_buf.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\  {{ "metric_id": "{s}", "value": {s}, "unit": "{s}", "source_document": "{s}", "source_locator": "{s}", "raw_file_sha256": "{s}" }}{s}
            \\
        , .{ ent.metric_id, val_s, ent.unit, ent.source_document, ent.source_locator, ent.raw_file_sha256[0..64], comma }));
    }
    try led_buf.appendSlice(alloc, "]\n");
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = try std.fmt.allocPrint(alloc, "{s}/data/provenance_ledger.json", .{demo_dir}),
        .data = led_buf.items,
    });

    // Write data/summary_metrics.json
    var sum_buf: std.ArrayList(u8) = .empty;
    try sum_buf.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\{{
        \\  "metadata": {{
        \\    "title": "EXOMUNDUS: Census of Confirmed Exoplanets, {d}–{d}",
        \\    "source": "NASA Exoplanet Archive (Caltech IPAC) TAP API — ps (default_flag=1)",
        \\    "min_year": {d},
        \\    "max_year": {d},
        \\    "raw_file_hashes": {{
        \\      "nasa_benchmarks.json": "{s}",
        \\      "nasa_census_by_year_method.json": "{s}",
        \\      "nasa_completeness.json": "{s}",
        \\      "nasa_mass_radius.json": "{s}",
        \\      "nasa_radius_valley.json": "{s}"
        \\    }}
        \\  }},
        \\  "metrics": {{
        \\
    , .{ comp.min_yr, comp.max_yr, comp.min_yr, comp.max_yr, raw_shas[0][0..64], raw_shas[1][0..64], raw_shas[2][0..64], raw_shas[3][0..64], raw_shas[4][0..64] }));

    for (ledger.items, 0..) |ent, i| {
        const comma: []const u8 = if (i + 1 < ledger.items.len) "," else "";
        const val_s = if (ent.is_int)
            try std.fmt.allocPrint(alloc, "{d}", .{@as(i64, @intFromFloat(@round(ent.value)))})
        else
            try std.fmt.allocPrint(alloc, "{d:.2}", .{ent.value});
        try sum_buf.appendSlice(alloc, try std.fmt.allocPrint(alloc, "    \"{s}\": {s}{s}\n", .{ ent.metric_id, val_s, comma }));
    }
    try sum_buf.appendSlice(alloc, "  },\n  \"methods\": [\n");
    try sum_buf.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\    {{ "name": "Transit", "count": {d}, "share_pct": {d:.1}, "note": "Kepler, K2, TESS photometric dips" }},
        \\    {{ "name": "Radial Velocity", "count": {d}, "share_pct": {d:.1}, "note": "HARPS, HIRES, ESPRESSO Doppler wobble" }},
        \\    {{ "name": "Microlensing", "count": {d}, "share_pct": {d:.1}, "note": "OGLE, MOA gravitational lensing" }},
        \\    {{ "name": "Direct Imaging", "count": {d}, "share_pct": {d:.1}, "note": "VLT/SPHERE, Gemini, JWST coronagraphy" }},
        \\    {{ "name": "Other Methods", "count": {d}, "share_pct": {d:.1}, "note": "TTV, Astrometry, Pulsar & Eclipse Timing" }}
        \\  ],
        \\  "benchmarks": [
        \\
    , .{ cnt_transit, tr_pct, cnt_rv, rv_pct, cnt_micro, mi_pct, cnt_imaging, im_pct, cnt_other, oth_pct }));

    for (benchmarks, 0..) |bm, i| {
        const comma: []const u8 = if (i + 1 < benchmarks.len) "," else "";
        const rho_opt: ?f64 = if (bm.pl_rade != null and bm.pl_bmasse != null)
            round2(5.514 * (bm.pl_bmasse.? / (bm.pl_rade.? * bm.pl_rade.? * bm.pl_rade.?)))
        else
            null;
        try sum_buf.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\    {{ "name": "{s}", "method": "{s}", "year": {d}, "dist_pc": {s}, "period_d": {s}, "radius_re": {s}, "mass_me": {s}, "rho_gcm3": {s}, "eqt_k": {s}, "st_teff_k": {s} }}{s}
            \\
        , .{
            bm.pl_name,
            bm.discoverymethod,
            bm.disc_year,
            try formatJsonOptFloat(alloc, bm.sy_dist),
            try formatJsonOptFloat(alloc, bm.pl_orbper),
            try formatJsonOptFloat(alloc, bm.pl_rade),
            try formatJsonOptFloat(alloc, bm.pl_bmasse),
            try formatJsonOptFloat(alloc, rho_opt),
            try formatJsonOptFloat(alloc, bm.pl_eqt),
            try formatJsonOptFloat(alloc, bm.st_teff),
            comma,
        }));
    }
    try sum_buf.appendSlice(alloc, "  ]\n}\n");
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = try std.fmt.allocPrint(alloc, "{s}/data/summary_metrics.json", .{demo_dir}),
        .data = sum_buf.items,
    });

    // =========================================================================
    // PURE-ZIG VECTOR SVG EXHIBIT 1: ANNUAL DISCOVERY CADENCE + FULTON VALLEY
    // =========================================================================
    const svg1 = try renderCensusValleySvg(alloc, years, peak_year, peak_year_n, comp.n_total, &bin_centers, &bin_counts, n_valley_sample);
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = try std.fmt.allocPrint(alloc, "{s}/report/assets/fig_census_valley.svg", .{demo_dir}),
        .data = svg1,
    });

    // =========================================================================
    // PURE-ZIG VECTOR SVG EXHIBIT 2: LOG-LOG MASS-RADIUS + RULE 5 COMPLETENESS
    // =========================================================================
    const svg2 = try renderMassRadiusSvg(alloc, mr_rows, benchmarks, comp, n_both);
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = try std.fmt.allocPrint(alloc, "{s}/report/assets/fig_mass_radius.svg", .{demo_dir}),
        .data = svg2,
    });

    const msg = try std.fmt.allocPrint(alloc,
        \\[pipeline.zig] Verified {d} NASA exoplanets ({d}-{d}) | 5 raw files SHA-256 sealed | {d} ledger tuples | 2 pure-vector SVGs emitted
        \\  Transit={d} ({d:.1}%) | RV={d} ({d:.1}%) | Radius={d} ({d:.1}%) | Mass={d} ({d:.1}%) | Both={d} ({d:.1}%)
        \\  Fulton Valley (N={d}): Super-Earth peak ~{d:.2} R_e | Trough ~{d:.2} R_e | Sub-Neptune peak ~{d:.2} R_e
        \\
    , .{
        comp.n_total,
        comp.min_yr,
        comp.max_yr,
        ledger.items.len,
        cnt_transit,
        tr_pct,
        cnt_rv,
        rv_pct,
        comp.n_with_rad,
        rad_pct,
        comp.n_with_mass,
        mass_pct,
        n_both,
        both_pct,
        n_valley_sample,
        se_peak_re,
        val_trough_re,
        sn_peak_re,
    });
    try std.Io.File.stdout().writeStreamingAll(io, msg);
}

fn renderCensusValleySvg(
    alloc: std.mem.Allocator,
    years: []const YearBucket,
    peak_year: i64,
    peak_n: i64,
    total_n: i64,
    bin_centers: []const f64,
    bin_counts: []const i64,
    valley_n: i64,
) ![]u8 {
    const w: f64 = 504.0;
    const h: f64 = 186.0;
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\<svg xmlns="http://www.w3.org/2000/svg" width="{d:.0}pt" height="{d:.0}pt" viewBox="0 0 {d:.0} {d:.0}">
        \\<rect width="{d:.0}" height="{d:.0}" fill="#FAF9F6" />
        \\
    , .{ w, h, w, h, w, h }));

    // --- PANEL A: Annual Discoveries Stacked Bars (x: 34..304, y: 24..150) ---
    const lx0: f64 = 34.0;
    const ly0: f64 = 24.0;
    const lw: f64 = 270.0;
    const lh: f64 = 126.0;
    const y_max: f64 = @max(1600.0, @ceil(@as(f64, @floatFromInt(peak_n)) / 400.0) * 400.0);

    try out.appendSlice(alloc,
        \\<text x="34" y="12" font-family="Inter, sans-serif" font-size="6.8" font-weight="700" letter-spacing="0.8" fill="#0E243D">A · ANNUAL DISCOVERIES BY METHOD (1992–2026)</text>
        \\
    );
    const yticks = [_]i64{ 0, 400, 800, 1200, 1600 };
    for (yticks) |yt| {
        const fy = ly0 + lh - (@as(f64, @floatFromInt(yt)) / y_max) * lh;
        const stroke_col: []const u8 = if (yt == 0) "#45525E" else "#DCD5C6";
        const sw: f64 = if (yt == 0) 0.7 else 0.45;
        try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\<line x1="{d:.1}" y1="{d:.1}" x2="{d:.1}" y2="{d:.1}" stroke="{s}" stroke-width="{d:.2}" />
            \\<text x="{d:.1}" y="{d:.1}" text-anchor="end" font-family="Inter, sans-serif" font-size="6.0" fill="#45525E">{d}</text>
            \\
        , .{ lx0, fy, lx0 + lw, fy, stroke_col, sw, lx0 - 4.0, fy + 2.2, yt }));
    }

    const bar_step = lw / @as(f64, @floatFromInt(years.len));
    const bar_w = @max(2.5, bar_step - 1.6);
    for (years, 0..) |yb, idx| {
        const bx = lx0 + @as(f64, @floatFromInt(idx)) * bar_step + 0.8;
        var cur_y = ly0 + lh;
        const segs = [_]struct { n: i64, col: []const u8 }{
            .{ .n = yb.transit, .col = "#0B5CAD" },
            .{ .n = yb.rv, .col = "#0E243D" },
            .{ .n = yb.micro, .col = "#A34808" },
            .{ .n = yb.other, .col = "#146646" },
        };
        for (segs) |sg| {
            if (sg.n <= 0) continue;
            const sh = (@as(f64, @floatFromInt(sg.n)) / y_max) * lh;
            cur_y -= sh;
            try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
                \\<rect x="{d:.1}" y="{d:.1}" width="{d:.1}" height="{d:.1}" fill="{s}" />
                \\
            , .{ bx, cur_y, bar_w, sh, sg.col }));
        }
        if (yb.year == peak_year) {
            try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
                \\<text x="{d:.1}" y="{d:.1}" text-anchor="middle" font-family="Inter, sans-serif" font-size="6.2" font-weight="700" fill="#0B5CAD">{d}: {d}</text>
                \\
            , .{ bx + bar_w * 0.5, cur_y - 4.0, peak_year, peak_n }));
        }
        if (yb.year == 1995 or yb.year == 2005 or yb.year == 2015 or yb.year == 2025) {
            try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
                \\<text x="{d:.1}" y="{d:.1}" text-anchor="middle" font-family="Inter, sans-serif" font-size="6.0" fill="#45525E">{d}</text>
                \\
            , .{ bx + bar_w * 0.5, ly0 + lh + 11.0, yb.year }));
        }
    }

    // Compact legend in upper-left empty space
    try out.appendSlice(alloc,
        \\<rect x="42" y="30" width="6.5" height="6.5" fill="#0B5CAD" rx="1" />
        \\<text x="52" y="35.5" font-family="Inter, sans-serif" font-size="6.0" fill="#141A20">Transit (Kepler / TESS)</text>
        \\<rect x="42" y="41" width="6.5" height="6.5" fill="#0E243D" rx="1" />
        \\<text x="52" y="46.5" font-family="Inter, sans-serif" font-size="6.0" fill="#141A20">Radial Velocity</text>
        \\<rect x="42" y="52" width="6.5" height="6.5" fill="#A34808" rx="1" />
        \\<text x="52" y="57.5" font-family="Inter, sans-serif" font-size="6.0" fill="#141A20">Microlensing</text>
        \\<rect x="42" y="63" width="6.5" height="6.5" fill="#146646" rx="1" />
        \\<text x="52" y="68.5" font-family="Inter, sans-serif" font-size="6.0" fill="#141A20">Imaging &amp; Other</text>
        \\
    );

    // --- PANEL B: Fulton Radius Valley (x: 332..498, y: 24..150) ---
    const rx0: f64 = 332.0;
    const ry0: f64 = 24.0;
    const rw: f64 = 166.0;
    const rh: f64 = 126.0;
    try out.appendSlice(alloc,
        \\<text x="332" y="12" font-family="Inter, sans-serif" font-size="6.8" font-weight="700" letter-spacing="0.8" fill="#0E243D">B · FULTON RADIUS VALLEY (P ≤ 100d)</text>
        \\
    );

    var max_bin: i64 = 1;
    for (bin_counts) |bc| if (bc > max_bin) {
        max_bin = bc;
    };
    const max_bf = @as(f64, @floatFromInt(max_bin)) * 1.18;

    // Shaded photoevaporation gap band (1.6..2.0 R_earth)
    const log_min = @log10(0.6);
    const log_max = @log10(5.5);
    const gap_x0 = rx0 + ((@log10(1.6) - log_min) / (log_max - log_min)) * rw;
    const gap_x1 = rx0 + ((@log10(2.0) - log_min) / (log_max - log_min)) * rw;
    try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\<rect x="{d:.1}" y="{d:.1}" width="{d:.1}" height="{d:.1}" fill="#A34808" fill-opacity="0.10" />
        \\<text x="{d:.1}" y="{d:.1}" text-anchor="middle" font-family="Inter, sans-serif" font-size="5.6" font-weight="700" fill="#A34808">VALLEY</text>
        \\
    , .{ gap_x0, ry0 + 4.0, gap_x1 - gap_x0, rh - 4.0, (gap_x0 + gap_x1) * 0.5, ry0 + 13.0 }));

    const bw_r = rw / @as(f64, @floatFromInt(bin_counts.len));
    for (bin_counts, 0..) |bc, bi| {
        const bx = rx0 + @as(f64, @floatFromInt(bi)) * bw_r + 1.0;
        const bh = (@as(f64, @floatFromInt(bc)) / max_bf) * rh;
        const by = ry0 + rh - bh;
        const rc = bin_centers[bi];
        const col: []const u8 = if (rc >= 1.6 and rc <= 2.0) "#A34808" else if (rc < 1.6) "#146646" else "#0B5CAD";
        try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\<rect x="{d:.1}" y="{d:.1}" width="{d:.1}" height="{d:.1}" fill="{s}" rx="1.0" />
            \\
        , .{ bx, by, @max(2.0, bw_r - 2.0), bh, col }));
    }
    try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\<line x1="{d:.1}" y1="{d:.1}" x2="{d:.1}" y2="{d:.1}" stroke="#45525E" stroke-width="0.7" />
        \\
    , .{ rx0, ry0 + rh, rx0 + rw, ry0 + rh }));

    const rticks = [_]struct { v: f64, lbl: []const u8 }{
        .{ .v = 0.7, .lbl = "0.7" },
        .{ .v = 1.0, .lbl = "1.0" },
        .{ .v = 1.8, .lbl = "1.8" },
        .{ .v = 3.0, .lbl = "3.0" },
        .{ .v = 5.0, .lbl = "5.0 R<tspan font-size=\"4.2\" dy=\"1.2\">⊕</tspan>" },
    };
    for (rticks) |rt| {
        const tx = rx0 + ((@log10(rt.v) - log_min) / (log_max - log_min)) * rw;
        try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\<line x1="{d:.1}" y1="{d:.1}" x2="{d:.1}" y2="{d:.1}" stroke="#45525E" stroke-width="0.6" />
            \\<text x="{d:.1}" y="{d:.1}" text-anchor="middle" font-family="Inter, sans-serif" font-size="5.8" fill="#45525E">{s}</text>
            \\
        , .{ tx, ry0 + rh, tx, ry0 + rh + 3.0, tx, ry0 + rh + 11.0, rt.lbl }));
    }

    try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\<text x="500" y="182" text-anchor="end" font-family="Source Serif 4, Georgia, serif" font-style="italic" font-size="6.3" fill="#45525E">Source: NASA Exoplanet Archive (ps default_flag=1; Total N = {d}, Fulton Valley N = {d} close-in worlds).</text>
        \\</svg>
        \\
    , .{ total_n, valley_n }));
    return out.toOwnedSlice(alloc);
}

fn renderMassRadiusSvg(
    alloc: std.mem.Allocator,
    mr_rows: []const MassRadRow,
    benchmarks: []const BenchmarkRow,
    comp: CompletenessRow,
    n_both: i64,
) ![]u8 {
    const w: f64 = 504.0;
    const h: f64 = 188.0;
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\<svg xmlns="http://www.w3.org/2000/svg" width="{d:.0}pt" height="{d:.0}pt" viewBox="0 0 {d:.0} {d:.0}">
        \\<rect width="{d:.0}" height="{d:.0}" fill="#FAF9F6" />
        \\
    , .{ w, h, w, h, w, h }));

    // --- PANEL A: Log-Log Mass vs Radius (x: 34..304, y: 24..152) ---
    const lx0: f64 = 34.0;
    const ly0: f64 = 24.0;
    const lw: f64 = 270.0;
    const lh: f64 = 128.0;
    const lm_min: f64 = @log10(0.2);
    const lm_max: f64 = @log10(10000.0);
    const lr_min: f64 = @log10(0.5);
    const lr_max: f64 = @log10(26.0);

    try out.appendSlice(alloc,
        \\<text x="34" y="12" font-family="Inter, sans-serif" font-size="6.8" font-weight="700" letter-spacing="0.8" fill="#0E243D">A · OBSERVED MASS–RADIUS POPULATION (LOG–LOG)</text>
        \\
    );

    const r_ticks = [_]f64{ 1.0, 2.0, 4.0, 10.0, 20.0 };
    for (r_ticks) |rt| {
        const py = ly0 + lh - ((@log10(rt) - lr_min) / (lr_max - lr_min)) * lh;
        try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\<line x1="{d:.1}" y1="{d:.1}" x2="{d:.1}" y2="{d:.1}" stroke="#E2DBC9" stroke-width="0.45" />
            \\<text x="{d:.1}" y="{d:.1}" text-anchor="end" font-family="Inter, sans-serif" font-size="5.8" fill="#45525E">{d:.0}</text>
            \\
        , .{ lx0, py, lx0 + lw, py, lx0 - 4.0, py + 2.0, rt }));
    }
    const m_ticks = [_]struct { v: f64, lbl: []const u8 }{
        .{ .v = 1.0, .lbl = "1" },
        .{ .v = 10.0, .lbl = "10" },
        .{ .v = 100.0, .lbl = "100" },
        .{ .v = 1000.0, .lbl = "1,000 M<tspan font-size=\"4.2\" dy=\"1.2\">⊕</tspan>" },
    };
    for (m_ticks) |mt| {
        const px = lx0 + ((@log10(mt.v) - lm_min) / (lm_max - lm_min)) * lw;
        try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\<line x1="{d:.1}" y1="{d:.1}" x2="{d:.1}" y2="{d:.1}" stroke="#E2DBC9" stroke-width="0.45" />
            \\<text x="{d:.1}" y="{d:.1}" text-anchor="middle" font-family="Inter, sans-serif" font-size="5.8" fill="#45525E">{s}</text>
            \\
        , .{ px, ly0, px, ly0 + lh, px, ly0 + lh + 11.0, mt.lbl }));
    }

    // Iso-density dashed curves: Earth rock (R = M^(1/3)) and Gas Giant (rho = 1.33 g/cm3 -> R = (5.514/1.33 * M)^(1/3))
    const x_rock0 = lx0 + ((@log10(0.3) - lm_min) / (lm_max - lm_min)) * lw;
    const y_rock0 = ly0 + lh - ((@log10(std.math.pow(f64, 0.3, 1.0 / 3.0)) - lr_min) / (lr_max - lr_min)) * lh;
    const x_rock1 = lx0 + ((@log10(25.0) - lm_min) / (lm_max - lm_min)) * lw;
    const y_rock1 = ly0 + lh - ((@log10(std.math.pow(f64, 25.0, 1.0 / 3.0)) - lr_min) / (lr_max - lr_min)) * lh;
    try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\<line x1="{d:.1}" y1="{d:.1}" x2="{d:.1}" y2="{d:.1}" stroke="#146646" stroke-width="0.85" stroke-dasharray="3,2" />
        \\<text x="{d:.1}" y="{d:.1}" font-family="Inter, sans-serif" font-size="5.5" font-weight="600" fill="#146646">Earth density (5.5 g/cm³)</text>
        \\
    , .{ x_rock0, y_rock0, x_rock1, y_rock1, x_rock1 + 3.0, y_rock1 + 3.0 }));

    // Scatter points (every observed mass+radius planet in range)
    for (mr_rows) |mr| {
        if (mr.pl_bmasse < 0.2 or mr.pl_bmasse > 10000.0 or mr.pl_rade < 0.5 or mr.pl_rade > 26.0) continue;
        const px = lx0 + ((@log10(mr.pl_bmasse) - lm_min) / (lm_max - lm_min)) * lw;
        const py = ly0 + lh - ((@log10(mr.pl_rade) - lr_min) / (lr_max - lr_min)) * lh;
        const col: []const u8 = if (std.mem.eql(u8, mr.discoverymethod, "Transit")) "#0B5CAD" else "#A34808";
        try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\<circle cx="{d:.1}" cy="{d:.1}" r="1.35" fill="{s}" fill-opacity="0.32" />
            \\
        , .{ px, py, col }));
    }

    // Highlight iconic benchmark planets with observed M & R
    const callouts = [_]struct { name: []const u8, dx: f64, dy: f64, anchor: []const u8 }{
        .{ .name = "TRAPPIST-1 e", .dx = 5.0, .dy = 11.0, .anchor = "start" },
        .{ .name = "LHS 1140 b", .dx = -5.0, .dy = -5.0, .anchor = "end" },
        .{ .name = "K2-18 b", .dx = -5.0, .dy = -5.0, .anchor = "end" },
        .{ .name = "HD 209458 b", .dx = -6.0, .dy = -5.0, .anchor = "end" },
    };
    for (benchmarks) |bm| {
        if (bm.pl_rade == null or bm.pl_bmasse == null) continue;
        for (callouts) |co| {
            if (!std.mem.eql(u8, bm.pl_name, co.name)) continue;
            const px = lx0 + ((@log10(bm.pl_bmasse.?) - lm_min) / (lm_max - lm_min)) * lw;
            const py = ly0 + lh - ((@log10(bm.pl_rade.?) - lr_min) / (lr_max - lr_min)) * lh;
            try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
                \\<circle cx="{d:.1}" cy="{d:.1}" r="2.9" fill="#FAF9F6" stroke="#0E243D" stroke-width="1.2" />
                \\<text x="{d:.1}" y="{d:.1}" text-anchor="{s}" font-family="Inter, sans-serif" font-size="5.8" font-weight="700" fill="#0E243D">{s}</text>
                \\
            , .{ px, py, px + co.dx, py + co.dy, co.anchor, bm.pl_name }));
        }
    }
    try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\<line x1="{d:.1}" y1="{d:.1}" x2="{d:.1}" y2="{d:.1}" stroke="#45525E" stroke-width="0.7" />
        \\<line x1="{d:.1}" y1="{d:.1}" x2="{d:.1}" y2="{d:.1}" stroke="#45525E" stroke-width="0.7" />
        \\<text x="12" y="{d:.1}" transform="rotate(-90 12 {d:.1})" text-anchor="middle" font-family="Inter, sans-serif" font-size="6.0" fill="#45525E">Radius (R<tspan font-size="4.3" dy="1.2">⊕</tspan><tspan dy="-1.2">)</tspan></text>
        \\
    , .{ lx0, ly0 + lh, lx0 + lw, ly0 + lh, lx0, ly0, lx0, ly0 + lh, ly0 + lh * 0.5, ly0 + lh * 0.5 }));

    // --- PANEL B: Rule 5 Observational Completeness Bars (x: 332..498, y: 24..152) ---
    const rx0: f64 = 332.0;
    const rw: f64 = 166.0;
    const tot_f: f64 = @floatFromInt(comp.n_total);
    try out.appendSlice(alloc,
        \\<text x="332" y="12" font-family="Inter, sans-serif" font-size="6.8" font-weight="700" letter-spacing="0.8" fill="#0E243D">B · OBSERVED VS. [N/A] GAPS (RULE 5)</text>
        \\
    );

    const bars = [_]struct { lbl: []const u8, cnt: i64, col: []const u8 }{
        .{ .lbl = "Observed Radius", .cnt = comp.n_with_rad, .col = "#0B5CAD" },
        .{ .lbl = "Observed Mass", .cnt = comp.n_with_mass, .col = "#0E243D" },
        .{ .lbl = "Both Mass &amp; Radius", .cnt = n_both, .col = "#146646" },
        .{ .lbl = "Equilibrium Temp", .cnt = comp.n_with_eqt, .col = "#A34808" },
    };
    for (bars, 0..) |b, idx| {
        const by = 32.0 + @as(f64, @floatFromInt(idx)) * 31.0;
        const pct = (@as(f64, @floatFromInt(b.cnt)) / tot_f) * 100.0;
        const fw = (pct / 100.0) * rw;
        try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\<text x="{d:.1}" y="{d:.1}" font-family="Inter, sans-serif" font-size="6.4" font-weight="600" fill="#141A20">{s}</text>
            \\<text x="{d:.1}" y="{d:.1}" text-anchor="end" font-family="IBM Plex Mono, monospace" font-size="6.3" font-weight="700" fill="{s}">{d:.1}% ({d})</text>
            \\<rect x="{d:.1}" y="{d:.1}" width="{d:.1}" height="10" fill="#E3DDD0" rx="1.5" />
            \\<rect x="{d:.1}" y="{d:.1}" width="{d:.1}" height="10" fill="{s}" rx="1.5" />
            \\
        , .{ rx0, by, b.lbl, rx0 + rw, by, b.col, pct, b.cnt, rx0, by + 4.0, rw, rx0, by + 4.0, fw, b.col }));
    }

    try out.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\<text x="500" y="183" text-anchor="end" font-family="Source Serif 4, Georgia, serif" font-style="italic" font-size="6.3" fill="#45525E">Source: NASA Exoplanet Archive (ps default_flag=1; N = {d} observed M+R worlds; grey tracks = unmeasured [N/A]).</text>
        \\</svg>
        \\
    , .{n_both}));
    return out.toOwnedSlice(alloc);
}
