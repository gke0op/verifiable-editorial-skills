//! Pure-Zig 0.17.0 Pure-Vector SVG Chart Generator for `demos/typst-carbon-monograph`.
//! Reads verified NOAA + World Bank `summary_metrics.json` and emits infinite-DPI vector SVGs
//! (`fig_keeling_vector.svg` and `fig_divergence_vector.svg`) with zero Python dependencies.

const std = @import("std");

const NAVY = "#0F2942";
const COBALT = "#035E9E";
const AMBER = "#9A4A0B";
const EMERALD = "#146346";
const SLATE = "#45525E";
const GRID = "#DDD7CB";
const BG = "#FAF9F6";
const INK = "#141A20";

const DecadalItem = struct {
    label: []const u8,
    ppm_per_yr: f64,
};

const NoaaSeries = struct {
    decimal_dates: []const f64,
    average_ppm: []const f64,
    deseasonalized_ppm: []const f64,
    decadal_growth: []const DecadalItem,
};

const Metrics = struct {
    noaa_observation_count: i64,
};

const Economy = struct {
    name: []const u8,
    bloc: []const u8,
    co2_series_2000_2024: []const f64,
    carbon_intensity_change_pct: f64,
};

const SummaryData = struct {
    metrics: Metrics,
    noaa_series: NoaaSeries,
    economies: []const Economy,
};

fn escapeXml(alloc: std.mem.Allocator, s: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    for (s) |ch| {
        switch (ch) {
            '&' => try out.appendSlice(alloc, "&amp;"),
            '<' => try out.appendSlice(alloc, "&lt;"),
            '>' => try out.appendSlice(alloc, "&gt;"),
            '"' => try out.appendSlice(alloc, "&quot;"),
            else => try out.append(alloc, ch),
        }
    }
    return out.toOwnedSlice(alloc);
}

fn shortDecadeLabel(alloc: std.mem.Allocator, lbl: []const u8) ![]u8 {
    if (std.mem.find(u8, lbl, "2020") != null) return alloc.dupe(u8, "'20\xe2\x80\x9325");
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < lbl.len) {
        if (i + 1 < lbl.len and ((lbl[i] == '1' and lbl[i + 1] == '9') or (lbl[i] == '2' and lbl[i + 1] == '0'))) {
            try out.append(alloc, '\'');
            i += 2;
        } else {
            try out.append(alloc, lbl[i]);
            i += 1;
        }
    }
    return out.toOwnedSlice(alloc);
}

fn mapKeeling(xv: f64, yv: f64) [2]f64 {
    const lx0: f64 = 36.0;
    const ly0: f64 = 24.0;
    const lw: f64 = 290.0;
    const lh: f64 = 124.0;
    const xmin: f64 = 1958.0;
    const xmax: f64 = 2027.0;
    const ymin: f64 = 310.0;
    const ymax: f64 = 440.0;
    return .{
        lx0 + ((xv - xmin) / (xmax - xmin)) * lw,
        ly0 + ((ymax - yv) / (ymax - ymin)) * lh,
    };
}

fn buildKeelingSvg(alloc: std.mem.Allocator, data: SummaryData) ![]u8 {
    const w: f64 = 504.0;
    const h: f64 = 178.0;
    const lx0: f64 = 36.0;
    const ly0: f64 = 24.0;
    const lw: f64 = 290.0;
    const lh: f64 = 124.0;
    const ns = data.noaa_series;

    var buf: std.ArrayList(u8) = .empty;
    try buf.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\<svg xmlns="http://www.w3.org/2000/svg" width="{d:.0}pt" height="{d:.0}pt" viewBox="0 0 {d:.0} {d:.0}">
        \\<rect x="0" y="0" width="{d:.0}" height="{d:.0}" fill="{s}" />
        \\<text x="{d:.0}" y="12" font-family="Inter, sans-serif" font-size="6.8" font-weight="700" letter-spacing="0.8" fill="{s}">A · MAUNA LOA CO₂ CONCENTRATION (1958–2026)</text>
        \\
    , .{ w, h, w, h, w, h, BG, lx0, NAVY }));

    const yticks = [_]i32{ 320, 350, 380, 410, 440 };
    for (yticks) |yt| {
        const pt = mapKeeling(1958.0, @floatFromInt(yt));
        try buf.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\<line x1="{d:.1}" y1="{d:.1}" x2="{d:.1}" y2="{d:.1}" stroke="{s}" stroke-width="0.6" />
            \\<text x="{d:.1}" y="{d:.1}" text-anchor="end" font-family="Inter, sans-serif" font-size="6.4" fill="{s}">{d}</text>
            \\
        , .{ lx0, pt[1], lx0 + lw, pt[1], GRID, lx0 - 5.0, pt[1] + 2.3, SLATE, yt }));
    }
    try buf.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\<text x="{d:.1}" y="{d:.1}" text-anchor="middle" transform="rotate(-90 {d:.1} {d:.1})" font-family="Inter, sans-serif" font-size="6.2" font-weight="600" fill="{s}">ppm</text>
        \\
    , .{ lx0 - 22.0, ly0 + lh / 2.0, lx0 - 22.0, ly0 + lh / 2.0, SLATE }));

    const xticks = [_]i32{ 1960, 1975, 1990, 2005, 2020 };
    for (xticks) |xt| {
        const pt = mapKeeling(@floatFromInt(xt), 310.0);
        try buf.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\<line x1="{d:.1}" y1="{d:.1}" x2="{d:.1}" y2="{d:.1}" stroke="{s}" stroke-width="0.6" />
            \\<text x="{d:.1}" y="{d:.1}" text-anchor="middle" font-family="Inter, sans-serif" font-size="6.4" fill="{s}">{d}</text>
            \\
        , .{ pt[0], ly0 + lh, pt[0], ly0 + lh + 3.0, SLATE, pt[0], ly0 + lh + 12.0, SLATE, xt }));
    }

    const n = ns.decimal_dates.len;
    if (n > 0) {
        var pts_d: std.ArrayList([2]f64) = .empty;
        var idx: usize = 0;
        while (idx < n) : (idx += 3) {
            try pts_d.append(alloc, mapKeeling(ns.decimal_dates[idx], ns.deseasonalized_ppm[idx]));
        }
        if ((n - 1) % 3 != 0) {
            try pts_d.append(alloc, mapKeeling(ns.decimal_dates[n - 1], ns.deseasonalized_ppm[n - 1]));
        }

        // Area fill under deseasonalized trend
        try buf.appendSlice(alloc, try std.fmt.allocPrint(alloc, "<path d=\"M {d:.1},{d:.1}", .{ pts_d.items[0][0], ly0 + lh }));
        for (pts_d.items) |p| {
            try buf.appendSlice(alloc, try std.fmt.allocPrint(alloc, " L {d:.1},{d:.1}", .{ p[0], p[1] }));
        }
        const last_d = pts_d.items[pts_d.items.len - 1];
        try buf.appendSlice(alloc, try std.fmt.allocPrint(alloc, " L {d:.1},{d:.1} Z\" fill=\"{s}\" fill-opacity=\"0.10\" />\n", .{ last_d[0], ly0 + lh, COBALT }));

        // Raw monthly seasonal sawtooth (every 2nd point + last)
        try buf.appendSlice(alloc, "<path d=\"M");
        var ai: usize = 0;
        var first_a = true;
        while (ai < n) : (ai += 2) {
            const pa = mapKeeling(ns.decimal_dates[ai], ns.average_ppm[ai]);
            const sep: []const u8 = if (first_a) " " else " L ";
            first_a = false;
            try buf.appendSlice(alloc, try std.fmt.allocPrint(alloc, "{s}{d:.1},{d:.1}", .{ sep, pa[0], pa[1] }));
        }
        const pa_last = mapKeeling(ns.decimal_dates[n - 1], ns.average_ppm[n - 1]);
        try buf.appendSlice(alloc, try std.fmt.allocPrint(alloc, " L {d:.1},{d:.1}\" fill=\"none\" stroke=\"{s}\" stroke-opacity=\"0.48\" stroke-width=\"0.7\" />\n", .{ pa_last[0], pa_last[1], COBALT }));

        // Deseasonalized bold trend
        try buf.appendSlice(alloc, "<path d=\"M");
        for (pts_d.items, 0..) |p, pi| {
            const sep: []const u8 = if (pi == 0) " " else " L ";
            try buf.appendSlice(alloc, try std.fmt.allocPrint(alloc, "{s}{d:.1},{d:.1}", .{ sep, p[0], p[1] }));
        }
        try buf.appendSlice(alloc, try std.fmt.allocPrint(alloc, "\" fill=\"none\" stroke=\"{s}\" stroke-width=\"1.5\" />\n", .{NAVY}));

        // Start & end callout dots
        const sp = mapKeeling(ns.decimal_dates[0], ns.deseasonalized_ppm[0]);
        const ep = mapKeeling(ns.decimal_dates[n - 1], ns.deseasonalized_ppm[n - 1]);
        try buf.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\<circle cx="{d:.1}" cy="{d:.1}" r="2.6" fill="{s}" />
            \\<text x="{d:.1}" y="{d:.1}" font-family="Inter, sans-serif" font-size="6.5" font-weight="700" fill="{s}">{d:.2}</text>
            \\<circle cx="{d:.1}" cy="{d:.1}" r="3.0" fill="{s}" />
            \\<text x="{d:.1}" y="{d:.1}" text-anchor="end" font-family="Inter, sans-serif" font-size="7.2" font-weight="700" fill="{s}">{d:.2} ppm</text>
            \\
        , .{
            sp[0],                    sp[1],                        SLATE,
            sp[0] + 2.0,              sp[1] - 7.0,                  SLATE,
            ns.deseasonalized_ppm[0], ep[0],                        ep[1],
            AMBER,                    ep[0] - 6.0,                  ep[1] - 6.0,
            AMBER,                    ns.deseasonalized_ppm[n - 1],
        }));
    }

    // Legend inside upper-left quiet space
    try buf.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\<line x1="{d:.0}" y1="{d:.0}" x2="{d:.0}" y2="{d:.0}" stroke="{s}" stroke-width="1.5" />
        \\<text x="{d:.0}" y="{d:.1}" font-family="Inter, sans-serif" font-size="6.2" fill="{s}">Deseasonalized trend</text>
        \\<line x1="{d:.0}" y1="{d:.0}" x2="{d:.0}" y2="{d:.0}" stroke="{s}" stroke-opacity="0.65" stroke-width="0.9" />
        \\<text x="{d:.0}" y="{d:.1}" font-family="Inter, sans-serif" font-size="6.2" fill="{s}">Monthly mean (seasonal cycle)</text>
        \\
    , .{
        lx0 + 8.0,  ly0 + 10.0, lx0 + 22.0, ly0 + 10.0, NAVY,
        lx0 + 26.0, ly0 + 12.3, INK,        lx0 + 8.0,  ly0 + 21.0,
        lx0 + 22.0, ly0 + 21.0, COBALT,     lx0 + 26.0, ly0 + 23.3,
        SLATE,
    }));

    // Right panel: Decadal growth rate bars
    const rx0: f64 = 356.0;
    const ry0: f64 = 24.0;
    const rw: f64 = 142.0;
    const rh: f64 = 124.0;
    try buf.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\<text x="{d:.0}" y="12" font-family="Inter, sans-serif" font-size="6.8" font-weight="700" letter-spacing="0.8" fill="{s}">B · DECADAL GROWTH (ppm/yr)</text>
        \\<line x1="{d:.1}" y1="{d:.1}" x2="{d:.1}" y2="{d:.1}" stroke="{s}" stroke-width="0.7" />
        \\
    , .{ rx0, NAVY, rx0, ry0 + rh, rx0 + rw, ry0 + rh, SLATE }));

    const dec = ns.decadal_growth;
    if (dec.len > 0) {
        const bar_step = rw / @as(f64, @floatFromInt(dec.len));
        for (dec, 0..) |item, i| {
            const bh = (item.ppm_per_yr / 3.0) * (rh - 14.0);
            const bx = rx0 + @as(f64, @floatFromInt(i)) * bar_step + 3.0;
            const bw = bar_step - 6.0;
            const by = ry0 + rh - bh;
            const col: []const u8 = if (i + 1 == dec.len) AMBER else if (i >= 4) COBALT else "#7B8A98";
            const txt_col: []const u8 = if (i >= 4) col else SLATE;
            const short_lbl = try shortDecadeLabel(alloc, item.label);
            const esc_lbl = try escapeXml(alloc, short_lbl);
            try buf.appendSlice(alloc, try std.fmt.allocPrint(alloc,
                \\<rect x="{d:.1}" y="{d:.1}" width="{d:.1}" height="{d:.1}" fill="{s}" rx="1.2" />
                \\<text x="{d:.1}" y="{d:.1}" text-anchor="middle" font-family="Inter, sans-serif" font-size="6.0" font-weight="700" fill="{s}">{d:.2}</text>
                \\<text x="{d:.1}" y="{d:.1}" text-anchor="middle" font-family="Inter, sans-serif" font-size="5.8" fill="{s}">{s}</text>
                \\
            , .{
                bx,              by,       bw,      bh,              col,
                bx + bw / 2.0,   by - 3.5, txt_col, item.ppm_per_yr, bx + bw / 2.0,
                ry0 + rh + 11.0, SLATE,    esc_lbl,
            }));
        }
    }

    try buf.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\<text x="{d:.0}" y="{d:.0}" text-anchor="end" font-family="Source Serif 4, Georgia, serif" font-style="italic" font-size="6.3" fill="{s}">Source: NOAA Global Monitoring Laboratory Mauna Loa Observatory (N = {d} monthly observations).</text>
        \\</svg>
        \\
    , .{ w - 4.0, h - 3.0, SLATE, data.metrics.noaa_observation_count }));
    return buf.toOwnedSlice(alloc);
}

fn mapDiv(i: usize, gt: f64) [2]f64 {
    const lx0: f64 = 34.0;
    const ly0: f64 = 24.0;
    const lw: f64 = 214.0;
    const lh: f64 = 124.0;
    return .{
        lx0 + (@as(f64, @floatFromInt(i)) / 24.0) * lw,
        ly0 + ((18.0 - gt) / 18.0) * lh,
    };
}

fn buildDivergenceSvg(alloc: std.mem.Allocator, data: SummaryData) ![]u8 {
    const w: f64 = 504.0;
    const h: f64 = 178.0;
    const lx0: f64 = 34.0;
    const ly0: f64 = 24.0;
    const lw: f64 = 214.0;
    const lh: f64 = 124.0;

    var oecd: [25]f64 = @splat(0.0);
    var em3: [25]f64 = @splat(0.0);
    for (data.economies) |e| {
        const n = @min(e.co2_series_2000_2024.len, 25);
        for (0..n) |i| {
            if (std.mem.eql(u8, e.bloc, "OECD-5")) {
                oecd[i] += e.co2_series_2000_2024[i] / 1000.0;
            } else if (std.mem.eql(u8, e.bloc, "Emerging-3")) {
                em3[i] += e.co2_series_2000_2024[i] / 1000.0;
            }
        }
    }

    var buf: std.ArrayList(u8) = .empty;
    try buf.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\<svg xmlns="http://www.w3.org/2000/svg" width="{d:.0}pt" height="{d:.0}pt" viewBox="0 0 {d:.0} {d:.0}">
        \\<rect x="0" y="0" width="{d:.0}" height="{d:.0}" fill="{s}" />
        \\<text x="{d:.0}" y="12" font-family="Inter, sans-serif" font-size="6.8" font-weight="700" letter-spacing="0.8" fill="{s}">A · BLOC EMISSIONS BIFURCATION (Gt CO₂)</text>
        \\
    , .{ w, h, w, h, w, h, BG, lx0, NAVY }));

    const yticks = [_]i32{ 0, 6, 12, 18 };
    for (yticks) |yt| {
        const pt = mapDiv(0, @floatFromInt(yt));
        try buf.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\<line x1="{d:.1}" y1="{d:.1}" x2="{d:.1}" y2="{d:.1}" stroke="{s}" stroke-width="0.6" />
            \\<text x="{d:.1}" y="{d:.1}" text-anchor="end" font-family="Inter, sans-serif" font-size="6.4" fill="{s}">{d}</text>
            \\
        , .{ lx0, pt[1], lx0 + lw, pt[1], GRID, lx0 - 5.0, pt[1] + 2.3, SLATE, yt }));
    }

    const xpairs = [_][2]usize{ .{ 0, 2000 }, .{ 8, 2008 }, .{ 16, 2016 }, .{ 24, 2024 } };
    for (xpairs) |xp| {
        const pt = mapDiv(xp[0], 0.0);
        try buf.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\<text x="{d:.1}" y="{d:.1}" text-anchor="middle" font-family="Inter, sans-serif" font-size="6.3" fill="{s}">{d}</text>
            \\
        , .{ pt[0], ly0 + lh + 11.0, SLATE, xp[1] }));
    }

    try buf.appendSlice(alloc, "<path d=\"M");
    for (0..25) |i| {
        const p = mapDiv(i, em3[i]);
        const sep: []const u8 = if (i == 0) " " else " L ";
        try buf.appendSlice(alloc, try std.fmt.allocPrint(alloc, "{s}{d:.1},{d:.1}", .{ sep, p[0], p[1] }));
    }
    try buf.appendSlice(alloc, try std.fmt.allocPrint(alloc, "\" fill=\"none\" stroke=\"{s}\" stroke-width=\"1.8\" />\n", .{AMBER}));

    try buf.appendSlice(alloc, "<path d=\"M");
    for (0..25) |i| {
        const p = mapDiv(i, oecd[i]);
        const sep: []const u8 = if (i == 0) " " else " L ";
        try buf.appendSlice(alloc, try std.fmt.allocPrint(alloc, "{s}{d:.1},{d:.1}", .{ sep, p[0], p[1] }));
    }
    try buf.appendSlice(alloc, try std.fmt.allocPrint(alloc, "\" fill=\"none\" stroke=\"{s}\" stroke-width=\"1.8\" />\n", .{COBALT}));

    const ep = mapDiv(24, em3[24]);
    const op = mapDiv(24, oecd[24]);
    const em_pct = if (em3[0] > 0.0) ((em3[24] - em3[0]) / em3[0]) * 100.0 else 0.0;
    const oe_pct = if (oecd[0] > 0.0) ((oecd[24] - oecd[0]) / oecd[0]) * 100.0 else 0.0;
    const em_sign: []const u8 = if (em_pct >= 0.0) "+" else "";
    try buf.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\<circle cx="{d:.1}" cy="{d:.1}" r="2.8" fill="{s}" />
        \\<text x="{d:.1}" y="{d:.1}" text-anchor="end" font-family="Inter, sans-serif" font-size="6.5" font-weight="700" fill="{s}">Emerging-3: {d:.2} Gt ({s}{d:.1}%)</text>
        \\<circle cx="{d:.1}" cy="{d:.1}" r="2.8" fill="{s}" />
        \\<text x="{d:.1}" y="{d:.1}" text-anchor="end" font-family="Inter, sans-serif" font-size="6.5" font-weight="700" fill="{s}">OECD-5: {d:.2} Gt ({d:.1}%)</text>
        \\
    , .{
        ep[0], ep[1], AMBER,  ep[0] - 4.0, ep[1] - 6.0,  AMBER,  em3[24],  em_sign, em_pct,
        op[0], op[1], COBALT, op[0] - 4.0, op[1] + 12.0, COBALT, oecd[24], oe_pct,
    }));

    // Right panel: Carbon intensity shift 2000->2024
    const rx0: f64 = 282.0;
    const ry0: f64 = 24.0;
    const rh: f64 = 124.0;
    try buf.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\<text x="{d:.0}" y="12" font-family="Inter, sans-serif" font-size="6.8" font-weight="700" letter-spacing="0.8" fill="{s}">B · CARBON INTENSITY SHIFT (2000–2024)</text>
        \\
    , .{ rx0, NAVY }));

    const ordered = try alloc.dupe(Economy, data.economies);
    std.mem.sort(Economy, ordered, {}, struct {
        fn lessThan(_: void, a: Economy, b: Economy) bool {
            return a.carbon_intensity_change_pct < b.carbon_intensity_change_pct;
        }
    }.lessThan);

    const bar_x = rx0 + 54.0;
    const bar_max: f64 = 122.0;
    const row_h = rh / @as(f64, @floatFromInt(@max(ordered.len, 1)));
    for (ordered, 0..) |e, i| {
        const y = ry0 + @as(f64, @floatFromInt(i)) * row_h + 2.0;
        const bw = (@abs(e.carbon_intensity_change_pct) / 70.0) * bar_max;
        const col: []const u8 = if (std.mem.eql(u8, e.bloc, "OECD-5")) EMERALD else COBALT;
        const esc_name = try escapeXml(alloc, e.name);
        try buf.appendSlice(alloc, try std.fmt.allocPrint(alloc,
            \\<text x="{d:.1}" y="{d:.1}" text-anchor="end" font-family="Inter, sans-serif" font-size="6.5" font-weight="600" fill="{s}">{s}</text>
            \\<rect x="{d:.1}" y="{d:.1}" width="{d:.1}" height="9.0" fill="#ECE7DC" rx="1" />
            \\<rect x="{d:.1}" y="{d:.1}" width="{d:.1}" height="9.0" fill="{s}" rx="1" />
            \\<text x="{d:.1}" y="{d:.1}" font-family="Inter, sans-serif" font-size="6.5" font-weight="700" fill="{s}">{d:.1}%</text>
            \\
        , .{
            bar_x - 6.0, y + 8.5, INK,                           esc_name,
            bar_x,       y + 1.5, bar_max,                       bar_x,
            y + 1.5,     bw,      col,                           bar_x + bar_max + 6.0,
            y + 8.5,     col,     e.carbon_intensity_change_pct,
        }));
    }

    try buf.appendSlice(alloc, try std.fmt.allocPrint(alloc,
        \\<text x="{d:.0}" y="{d:.0}" text-anchor="end" font-family="Source Serif 4, Georgia, serif" font-style="italic" font-size="6.3" fill="{s}">Source: World Bank WDI (2000–2024, 8 major economies; 2025 CO₂ remains [N/A] under Rule 5).</text>
        \\</svg>
        \\
    , .{ w - 4.0, h - 3.0, SLATE }));
    return buf.toOwnedSlice(alloc);
}

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(alloc);
    const repo_root: []const u8 = if (args.len >= 2) args[1] else ".";

    const data_path = try std.fs.path.join(alloc, &.{ repo_root, "demos", "global-carbon-telemetry", "data", "summary_metrics.json" });
    const assets_dir = try std.fs.path.join(alloc, &.{ repo_root, "demos", "typst-carbon-monograph", "report", "assets" });
    try std.Io.Dir.cwd().createDirPath(io, assets_dir);

    const raw = try std.Io.Dir.cwd().readFileAlloc(io, data_path, alloc, .unlimited);
    const parsed = try std.json.parseFromSliceLeaky(SummaryData, alloc, raw, .{ .ignore_unknown_fields = true });

    const keeling = try buildKeelingSvg(alloc, parsed);
    const div = try buildDivergenceSvg(alloc, parsed);

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = try std.fs.path.join(alloc, &.{ assets_dir, "fig_keeling_vector.svg" }), .data = keeling });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = try std.fs.path.join(alloc, &.{ assets_dir, "fig_divergence_vector.svg" }), .data = div });

    try std.Io.File.stdout().writeStreamingAll(io, "[typst-carbon-zig] Wrote pure-vector SVGs -> fig_keeling_vector.svg & fig_divergence_vector.svg\n");
}
