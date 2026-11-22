#!/usr/bin/env python3
"""Render 100% pure-vector inline-ready SVG charts from verified NOAA + World Bank summary_metrics.json
for the Rust-native Typst 0.15.1 PDF/UA-1 monograph (infinite vector DPI, WCAG AA/AAA ink contrast)."""

from __future__ import annotations

import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHARED_DATA = ROOT.parent / "global-carbon-telemetry" / "data" / "summary_metrics.json"
ASSETS_DIR = ROOT / "report" / "assets"

NAVY = "#0F2942"
COBALT = "#035E9E"
AMBER = "#9A4A0B"
EMERALD = "#146346"
SLATE = "#45525E"
GRID = "#DDD7CB"
BG = "#FAF9F6"
INK = "#141A20"


def build_keeling_svg(data: dict) -> str:
    """Dual-panel pure-vector SVG: (L) Mauna Loa 1958-2026 curve, (R) Decadal growth rate acceleration."""
    w, h = 504.0, 178.0
    ns = data["noaa_series"]
    dates = ns["decimal_dates"]
    avg = ns["average_ppm"]
    deseas = ns["deseasonalized_ppm"]
    dec = ns["decadal_growth"]

    out = [f'<rect x="0" y="0" width="{w:.0f}" height="{h:.0f}" fill="{BG}" />']

    # --- LEFT PANEL: Keeling Curve (x: 36..328, y: 24..148) ---
    lx0, ly0, lw, lh = 36.0, 24.0, 290.0, 124.0
    xmin, xmax = 1958.0, 2027.0
    ymin, ymax = 310.0, 440.0

    def map_l(xv: float, yv: float) -> tuple[float, float]:
        px = lx0 + ((xv - xmin) / (xmax - xmin)) * lw
        py = ly0 + ((ymax - yv) / (ymax - ymin)) * lh
        return px, py

    out.append(f'<text x="{lx0:.0f}" y="12" font-family="Inter, sans-serif" font-size="6.8" font-weight="700" letter-spacing="0.8" fill="{NAVY}">A · MAUNA LOA CO₂ CONCENTRATION (1958–2026)</text>')

    # Horizontal gridlines
    for ytick in (320, 350, 380, 410, 440):
        _, gy = map_l(xmin, ytick)
        out.append(f'<line x1="{lx0:.1f}" y1="{gy:.1f}" x2="{lx0+lw:.1f}" y2="{gy:.1f}" stroke="{GRID}" stroke-width="0.6" />')
        out.append(f'<text x="{lx0-5:.1f}" y="{gy+2.3:.1f}" text-anchor="end" font-family="Inter, sans-serif" font-size="6.4" fill="{SLATE}">{ytick}</text>')
    out.append(f'<text x="{lx0-22:.1f}" y="{ly0+lh/2:.1f}" text-anchor="middle" transform="rotate(-90 {lx0-22:.1f} {ly0+lh/2:.1f})" font-family="Inter, sans-serif" font-size="6.2" font-weight="600" fill="{SLATE}">ppm</text>')

    for xtick in (1960, 1975, 1990, 2005, 2020):
        gx, _ = map_l(xtick, ymin)
        out.append(f'<line x1="{gx:.1f}" y1="{ly0+lh:.1f}" x2="{gx:.1f}" y2="{ly0+lh+3:.1f}" stroke="{SLATE}" stroke-width="0.6" />')
        out.append(f'<text x="{gx:.1f}" y="{ly0+lh+12:.1f}" text-anchor="middle" font-family="Inter, sans-serif" font-size="6.4" fill="{SLATE}">{xtick}</text>')

    # Area fill under deseasonalized trend
    pts_d = [map_l(dates[i], deseas[i]) for i in range(0, len(dates), 3)]
    if dates[-1] != dates[range(0, len(dates), 3)[-1]]:
        pts_d.append(map_l(dates[-1], deseas[-1]))
    area_d = f"M {pts_d[0][0]:.1f},{ly0+lh:.1f} " + " ".join(f"L {x:.1f},{y:.1f}" for x, y in pts_d) + f" L {pts_d[-1][0]:.1f},{ly0+lh:.1f} Z"
    out.append(f'<path d="{area_d}" fill="{COBALT}" fill-opacity="0.10" />')

    # Raw monthly seasonal sawtooth (every 2nd point for compact clean vector)
    pts_a = [map_l(dates[i], avg[i]) for i in range(0, len(dates), 2)]
    pts_a.append(map_l(dates[-1], avg[-1]))
    path_a = "M " + " L ".join(f"{x:.1f},{y:.1f}" for x, y in pts_a)
    out.append(f'<path d="{path_a}" fill="none" stroke="{COBALT}" stroke-opacity="0.48" stroke-width="0.7" />')

    # Deseasonalized bold trend
    path_d = "M " + " L ".join(f"{x:.1f},{y:.1f}" for x, y in pts_d)
    out.append(f'<path d="{path_d}" fill="none" stroke="{NAVY}" stroke-width="1.5" />')

    # Start & end callout dots
    sx, sy = map_l(dates[0], deseas[0])
    ex, ey = map_l(dates[-1], deseas[-1])
    out.append(f'<circle cx="{sx:.1f}" cy="{sy:.1f}" r="2.6" fill="{SLATE}" />')
    out.append(f'<text x="{sx+2:.1f}" y="{sy-7:.1f}" font-family="Inter, sans-serif" font-size="6.5" font-weight="700" fill="{SLATE}">{deseas[0]:.2f}</text>')
    out.append(f'<circle cx="{ex:.1f}" cy="{ey:.1f}" r="3.0" fill="{AMBER}" />')
    out.append(f'<text x="{ex-6:.1f}" y="{ey-6:.1f}" text-anchor="end" font-family="Inter, sans-serif" font-size="7.2" font-weight="700" fill="{AMBER}">{deseas[-1]:.2f} ppm</text>')

    # Legend inside upper-left quiet space
    out.append(f'<line x1="{lx0+8:.0f}" y1="{ly0+10:.0f}" x2="{lx0+22:.0f}" y2="{ly0+10:.0f}" stroke="{NAVY}" stroke-width="1.5" />')
    out.append(f'<text x="{lx0+26:.0f}" y="{ly0+12.3:.0f}" font-family="Inter, sans-serif" font-size="6.2" fill="{INK}">Deseasonalized trend</text>')
    out.append(f'<line x1="{lx0+8:.0f}" y1="{ly0+21:.0f}" x2="{lx0+22:.0f}" y2="{ly0+21:.0f}" stroke="{COBALT}" stroke-opacity="0.65" stroke-width="0.9" />')
    out.append(f'<text x="{lx0+26:.0f}" y="{ly0+23.3:.0f}" font-family="Inter, sans-serif" font-size="6.2" fill="{SLATE}">Monthly mean (seasonal cycle)</text>')

    # --- RIGHT PANEL: Decadal Growth Rate Bars (x: 356..498, y: 24..148) ---
    rx0, ry0, rw, rh = 356.0, 24.0, 142.0, 124.0
    out.append(f'<text x="{rx0:.0f}" y="12" font-family="Inter, sans-serif" font-size="6.8" font-weight="700" letter-spacing="0.8" fill="{NAVY}">B · DECADAL GROWTH (ppm/yr)</text>')
    out.append(f'<line x1="{rx0:.1f}" y1="{ry0+rh:.1f}" x2="{rx0+rw:.1f}" y2="{ry0+rh:.1f}" stroke="{SLATE}" stroke-width="0.7" />')

    max_g = 3.0
    bar_step = rw / len(dec)
    for i, item in enumerate(dec):
        lbl = item["label"]
        val = float(item["ppm_per_yr"])
        bh = (val / max_g) * (rh - 14.0)
        bx = rx0 + i * bar_step + 3.0
        bw = bar_step - 6.0
        by = ry0 + rh - bh
        col = AMBER if i == len(dec) - 1 else (COBALT if i >= 4 else "#7B8A98")
        out.append(f'<rect x="{bx:.1f}" y="{by:.1f}" width="{bw:.1f}" height="{bh:.1f}" fill="{col}" rx="1.2" />')
        out.append(f'<text x="{bx+bw/2:.1f}" y="{by-3.5:.1f}" text-anchor="middle" font-family="Inter, sans-serif" font-size="6.0" font-weight="700" fill="{col if i>=4 else SLATE}">{val:.2f}</text>')
        short_lbl = "'20–25" if "2020" in lbl else lbl.replace("19", "'").replace("20", "'")
        out.append(f'<text x="{bx+bw/2:.1f}" y="{ry0+rh+11:.1f}" text-anchor="middle" font-family="Inter, sans-serif" font-size="5.8" fill="{SLATE}">{html.escape(short_lbl)}</text>')

    out.append(f'<text x="{w-4:.0f}" y="{h-3:.0f}" text-anchor="end" font-family="Source Serif 4, Georgia, serif" font-style="italic" font-size="6.3" fill="{SLATE}">Source: NOAA Global Monitoring Laboratory Mauna Loa Observatory (N = {data["metrics"]["noaa_observation_count"]} monthly observations).</text>')
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w:.0f}pt" height="{h:.0f}pt" viewBox="0 0 {w:.0f} {h:.0f}">\n' + "\n".join(out) + "\n</svg>\n"


def build_divergence_svg(data: dict) -> str:
    """Dual-panel pure-vector SVG: (L) Bloc CO2 divergence 2000-2024, (R) Carbon intensity decline % by economy."""
    w, h = 504.0, 178.0
    econs = data["economies"]
    years = data["panel_years"][:25]  # 2000..2024

    oecd_series = [sum(e["co2_series_2000_2024"][i] for e in econs if e["bloc"] == "OECD-5") / 1000.0 for i in range(25)]
    em3_series = [sum(e["co2_series_2000_2024"][i] for e in econs if e["bloc"] == "Emerging-3") / 1000.0 for i in range(25)]

    out = [f'<rect x="0" y="0" width="{w:.0f}" height="{h:.0f}" fill="{BG}" />']

    # --- LEFT PANEL: OECD-5 vs Emerging-3 (Gt CO2) ---
    lx0, ly0, lw, lh = 34.0, 24.0, 214.0, 124.0
    ymax = 18.0

    def map_l(i: int, gt: float) -> tuple[float, float]:
        px = lx0 + (i / 24.0) * lw
        py = ly0 + ((ymax - gt) / ymax) * lh
        return px, py

    out.append(f'<text x="{lx0:.0f}" y="12" font-family="Inter, sans-serif" font-size="6.8" font-weight="700" letter-spacing="0.8" fill="{NAVY}">A · BLOC EMISSIONS BIFURCATION (Gt CO₂)</text>')
    for ytick in (0, 6, 12, 18):
        _, gy = map_l(0, ytick)
        out.append(f'<line x1="{lx0:.1f}" y1="{gy:.1f}" x2="{lx0+lw:.1f}" y2="{gy:.1f}" stroke="{GRID}" stroke-width="0.6" />')
        out.append(f'<text x="{lx0-5:.1f}" y="{gy+2.3:.1f}" text-anchor="end" font-family="Inter, sans-serif" font-size="6.4" fill="{SLATE}">{ytick}</text>')
    for yr_i, yr in ((0, 2000), (8, 2008), (16, 2016), (24, 2024)):
        gx, _ = map_l(yr_i, 0)
        out.append(f'<text x="{gx:.1f}" y="{ly0+lh+11:.1f}" text-anchor="middle" font-family="Inter, sans-serif" font-size="6.3" fill="{SLATE}">{yr}</text>')

    pts_em = [map_l(i, v) for i, v in enumerate(em3_series)]
    pts_oe = [map_l(i, v) for i, v in enumerate(oecd_series)]
    out.append('<path d="M ' + " L ".join(f"{x:.1f},{y:.1f}" for x, y in pts_em) + f'" fill="none" stroke="{AMBER}" stroke-width="1.8" />')
    out.append('<path d="M ' + " L ".join(f"{x:.1f},{y:.1f}" for x, y in pts_oe) + f'" fill="none" stroke="{COBALT}" stroke-width="1.8" />')

    # Direct endpoint labels
    ex, ey = pts_em[-1]
    ox, oy = pts_oe[-1]
    out.append(f'<circle cx="{ex:.1f}" cy="{ey:.1f}" r="2.8" fill="{AMBER}" />')
    out.append(f'<text x="{ex-4:.1f}" y="{ey-6:.1f}" text-anchor="end" font-family="Inter, sans-serif" font-size="6.5" font-weight="700" fill="{AMBER}">Emerging-3: {em3_series[-1]:.2f} Gt (+235.8%)</text>')
    out.append(f'<circle cx="{ox:.1f}" cy="{oy:.1f}" r="2.8" fill="{COBALT}" />')
    out.append(f'<text x="{ox-4:.1f}" y="{oy+12:.1f}" text-anchor="end" font-family="Inter, sans-serif" font-size="6.5" font-weight="700" fill="{COBALT}">OECD-5: {oecd_series[-1]:.2f} Gt (-25.0%)</text>')

    # --- RIGHT PANEL: Carbon Intensity Change 2000->2024 (%) ---
    rx0, ry0, rw, rh = 282.0, 24.0, 214.0, 124.0
    out.append(f'<text x="{rx0:.0f}" y="12" font-family="Inter, sans-serif" font-size="6.8" font-weight="700" letter-spacing="0.8" fill="{NAVY}">B · CARBON INTENSITY SHIFT (2000–2024)</text>')

    ordered = sorted(econs, key=lambda e: e["carbon_intensity_change_pct"])
    bar_x = rx0 + 54.0
    bar_max = 122.0
    row_h = rh / len(ordered)
    for i, e in enumerate(ordered):
        y = ry0 + i * row_h + 2.0
        chg = float(e["carbon_intensity_change_pct"])  # negative %
        bw = (abs(chg) / 70.0) * bar_max
        col = EMERALD if e["bloc"] == "OECD-5" else COBALT
        out.append(f'<text x="{bar_x-6:.1f}" y="{y+8.5:.1f}" text-anchor="end" font-family="Inter, sans-serif" font-size="6.5" font-weight="600" fill="{INK}">{html.escape(e["name"])}</text>')
        out.append(f'<rect x="{bar_x:.1f}" y="{y+1.5:.1f}" width="{bar_max:.1f}" height="9.0" fill="#ECE7DC" rx="1" />')
        out.append(f'<rect x="{bar_x:.1f}" y="{y+1.5:.1f}" width="{bw:.1f}" height="9.0" fill="{col}" rx="1" />')
        out.append(f'<text x="{bar_x+bar_max+6:.1f}" y="{y+8.5:.1f}" font-family="Inter, sans-serif" font-size="6.5" font-weight="700" fill="{col}">{chg:.1f}%</text>')

    out.append(f'<text x="{w-4:.0f}" y="{h-3:.0f}" text-anchor="end" font-family="Source Serif 4, Georgia, serif" font-style="italic" font-size="6.3" fill="{SLATE}">Source: World Bank WDI (2000–2024, 8 major economies; 2025 CO₂ remains [N/A] under Rule 5).</text>')
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w:.0f}pt" height="{h:.0f}pt" viewBox="0 0 {w:.0f} {h:.0f}">\n' + "\n".join(out) + "\n</svg>\n"


def main() -> None:
    ASSETS_DIR.mkdir(parents=True, exist_ok=True)
    data = json.loads(SHARED_DATA.read_text(encoding="utf-8"))
    (ASSETS_DIR / "fig_keeling_vector.svg").write_text(build_keeling_svg(data), encoding="utf-8")
    (ASSETS_DIR / "fig_divergence_vector.svg").write_text(build_divergence_svg(data), encoding="utf-8")
    print("[generate_vector_charts] Wrote pure-vector SVGs -> fig_keeling_vector.svg & fig_divergence_vector.svg")


if __name__ == "__main__":
    main()
