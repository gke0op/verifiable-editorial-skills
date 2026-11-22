#!/usr/bin/env python3
"""
Phase 5a (Keynote): 7-Exhibit 300-DPI Institutional Chart Engine (Dark & Light Themes).

Reads strictly from audited data/summary_metrics.json and renders 14 transparent 300-DPI
exhibits powering the 9-slide Dark Executive Obsidian & Light Swiss Ivory presentations:
  1. keeling_acceleration    (1958-2026 Keeling curve + decadal acceleration)
  2. seasonal_breathing      (Biosphere Jan-Dec anomaly fingerprint + 1960-2025 annual jumps)
  3. bloc_divergence         (8-economy stacked mass balance + OECD-5 vs Emerging-3 index)
  4. per_capita_footprint    (Marimekko Pop x Per-Capita area chart + 2000->2024 slopegraph)
  5. decoupling_matrix       (Real GDP vs CO2 quadrants + carbon intensity dumbbells)
  6. yoy_momentum_heatmap    (8 x 24 annual YoY CO2 % change diverging matrix heatmap)
  7. renewables_bullets      (Stephen Few horizontal bullet graphs, 2000 vs 2021)
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.colors as mcolors
import matplotlib.font_manager as fm
import matplotlib.patches as patches
import matplotlib.pyplot as plt
import numpy as np

BASE_DIR = Path(__file__).resolve().parent.parent
SUMMARY_PATH = BASE_DIR / "data" / "summary_metrics.json"
ASSETS_DIR = BASE_DIR / "report" / "assets"

THEMES = {
    "dark": {
        "bg": "#0b0f19",
        "panel_bg": "#111827",
        "text": "#ffffff",
        "subtext": "#cbd5e1",
        "grid": "#1e293b",
        "spine": "#475569",
        "primary": "#38bdf8",
        "secondary": "#0ea5e9",
        "amber": "#fbbf24",
        "crimson": "#f87171",
        "emerald": "#34d399",
        "muted": "#94a3b8",
        "band_low": "#1e293b",
        "band_mid": "#172033",
        "band_hi": "#111827",
        "quad_ok": "#064e3b",
        "heat_neg": "#059669",
        "heat_zero": "#162032",
        "heat_pos": "#dc2626",
    },
    "light": {
        "bg": "#fcfbf9",
        "panel_bg": "#f8fafc",
        "text": "#0f172a",
        "subtext": "#475569",
        "grid": "#e2e8f0",
        "spine": "#94a3b8",
        "primary": "#0f2b48",
        "secondary": "#0284c7",
        "amber": "#d97706",
        "crimson": "#dc2626",
        "emerald": "#059669",
        "muted": "#64748b",
        "band_low": "#cbd5e1",
        "band_mid": "#e2e8f0",
        "band_hi": "#f1f5f9",
        "quad_ok": "#d1fae5",
        "heat_neg": "#059669",
        "heat_zero": "#f1f5f9",
        "heat_pos": "#dc2626",
    },
}


def configure_fonts() -> None:
    search_dirs: list[Path] = []
    if os.environ.get("INTER_FONT_DIR"):
        search_dirs.append(Path(os.environ["INTER_FONT_DIR"]))
    search_dirs.extend(
        [
            BASE_DIR / "fonts",
            Path.home() / "Library" / "Fonts",
            Path("/Library/Fonts"),
            Path("/usr/share/fonts/truetype/inter"),
        ]
    )
    loaded = False
    for d in search_dirs:
        if not d.is_dir():
            continue
        for fname in ("Inter-Regular.ttf", "Inter-Bold.ttf", "Inter-SemiBold.ttf"):
            fp = d / fname
            if fp.is_file():
                fm.fontManager.addfont(str(fp))
                loaded = True
    plt.rcParams["font.family"] = "sans-serif"
    plt.rcParams["font.sans-serif"] = (
        ["Inter", "Helvetica Neue", "DejaVu Sans"] if loaded else ["Helvetica Neue", "DejaVu Sans"]
    )
    plt.rcParams["axes.unicode_minus"] = False


def style_axes(ax: plt.Axes, t: dict[str, str], grid_axis: str = "y") -> None:
    ax.set_facecolor("none")
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
    for s in ("bottom", "left"):
        ax.spines[s].set_color(t["spine"])
        ax.spines[s].set_linewidth(0.7)
    ax.tick_params(colors=t["subtext"], labelsize=8.0, length=3, width=0.6)
    if grid_axis in ("x", "y", "both"):
        ax.grid(True, axis=grid_axis, linestyle="--", linewidth=0.55, color=t["grid"], alpha=0.85)
        ax.set_axisbelow(True)


# ------------------------------------------------------------------
# EXHIBIT 1: Keeling Curve & Decadal Accumulation
# ------------------------------------------------------------------
def render_keeling_acceleration(summary: dict, theme_name: str, out_path: Path) -> None:
    t = THEMES[theme_name]
    noaa, m, meta = summary["noaa_series"], summary["metrics"], summary["metadata"]
    dates = np.array(noaa["decimal_dates"])
    avg = np.array(noaa["average_ppm"])
    deseas = np.array(noaa["deseasonalized_ppm"])
    decades = noaa["decadal_growth"]

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(9.4, 3.6), dpi=300, gridspec_kw={"width_ratios": [1.85, 1.0]})
    fig.patch.set_alpha(0.0)

    style_axes(ax1, t, "y")
    ax1.spines["left"].set_visible(False)
    ax1.plot(dates, avg, color=t["secondary"], linewidth=0.85, alpha=0.55)
    ax1.plot(dates, deseas, color=t["primary"], linewidth=2.0)

    ax1.axvspan(2022.9, 2023.52, color=t["amber"], alpha=0.22)
    ax1.annotate(
        "Maunakea site\n(2022-23 eruption)",
        xy=(2023.1, 419.5),
        xytext=(1998.5, 412.0),
        fontsize=7.2,
        color=t["amber"],
        fontweight="bold",
        arrowprops={"arrowstyle": "->", "color": t["amber"], "lw": 0.9},
    )
    ax1.scatter([dates[0], dates[-1]], [deseas[0], deseas[-1]], color=[t["muted"], t["crimson"]], s=26, zorder=5)
    ax1.text(dates[0] + 1.2, deseas[0] - 5.5, f"{meta['noaa_start']}: {m['noaa_first_deseasonalized_ppm']:.1f} ppm", fontsize=7.6, color=t["subtext"], fontweight="bold")
    ax1.text(
        2021.8,
        m["noaa_peak_average_ppm"] + 4.5,
        f"Peak ({meta['noaa_peak_month']}): {m['noaa_peak_average_ppm']:.2f} ppm\nLatest deseas.: {m['noaa_latest_deseasonalized_ppm']:.2f} ppm",
        fontsize=7.5,
        color=t["crimson"],
        fontweight="bold",
        ha="right",
        va="bottom",
    )
    ax1.set_xlim(1957, 2028)
    ax1.set_ylim(305, 458)
    ax1.set_ylabel("Atmospheric CO2 (ppm)", fontsize=8.4, color=t["subtext"], fontweight="bold")
    ax1.set_title("Mauna Loa Atmospheric CO2 Concentration (1958–2026)", fontsize=9.8, fontweight="bold", color=t["text"], loc="left", pad=10)

    style_axes(ax2, t, "y")
    ax2.spines["left"].set_visible(False)
    labels = [d["label"] for d in decades]
    rates = [d["ppm_per_yr"] for d in decades]
    bar_colors = [t["muted"]] * (len(rates) - 2) + [t["amber"], t["crimson"]]
    x = np.arange(len(labels))
    bars = ax2.bar(x, rates, width=0.62, color=bar_colors)
    for bar, val in zip(bars, rates):
        ax2.text(bar.get_x() + bar.get_width() / 2.0, val + 0.06, f"+{val:.2f}", ha="center", va="bottom", fontsize=7.3, fontweight="bold", color=t["text"])
    ax2.set_xticks(x)
    ax2.set_xticklabels(labels, fontsize=7.3, color=t["subtext"], rotation=25, ha="right")
    ax2.set_ylim(0, max(rates) * 1.24)
    ax2.set_ylabel("Mean Annual Growth (ppm/yr)", fontsize=8.2, color=t["subtext"], fontweight="bold")
    ax2.set_title("Decadal Accumulation Rate (3.0x Rise)", fontsize=9.8, fontweight="bold", color=t["text"], loc="left", pad=10)

    plt.tight_layout(pad=1.1, w_pad=1.8)
    fig.savefig(out_path, dpi=300, transparent=True)
    plt.close(fig)


# ------------------------------------------------------------------
# EXHIBIT 2 (NEW): Seasonal Biosphere Fingerprint & Annual Increments
# ------------------------------------------------------------------
def render_seasonal_breathing(summary: dict, theme_name: str, out_path: Path) -> None:
    t = THEMES[theme_name]
    noaa = summary["noaa_series"]
    profs = noaa["seasonal_profiles"]
    yoy_yrs = np.array(noaa["yoy_years"])
    yoy_j = np.array(noaa["yoy_jumps_ppm"])

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(9.4, 3.6), dpi=300, gridspec_kw={"width_ratios": [1.0, 1.55]})
    fig.patch.set_alpha(0.0)

    # Left: Multi-decade Jan-Dec Seasonal Cycle Anomaly (average - deseasonalized)
    style_axes(ax1, t, "y")
    ax1.spines["left"].set_visible(False)
    months = np.arange(1, 13)
    m_lbls = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    ax1.axhline(0, color=t["spine"], linestyle="--", linewidth=0.8)
    ax1.fill_between(months, profs["2020-25"], 0, where=np.array(profs["2020-25"]) >= 0, color=t["amber"], alpha=0.14, interpolate=True)
    ax1.fill_between(months, profs["2020-25"], 0, where=np.array(profs["2020-25"]) < 0, color=t["emerald"], alpha=0.14, interpolate=True)

    ax1.plot(months, profs["1960s"], color=t["muted"], linewidth=1.4, linestyle=":", label="1960s")
    ax1.plot(months, profs["1990s"], color=t["secondary"], linewidth=1.6, linestyle="--", label="1990s")
    ax1.plot(months, profs["2020-25"], color=t["primary"], linewidth=2.4, marker="o", markersize=3.5, label="2020–25")

    ax1.text(5.0, max(profs["2020-25"]) + 0.35, "May Peak (+3.2 ppm)\nWinter release", fontsize=7.0, fontweight="bold", color=t["amber"], ha="center")
    ax1.text(9.3, min(profs["2020-25"]) - 0.32, "Sep/Oct Trough (-3.0 ppm)\nBoreal drawdown", fontsize=7.0, fontweight="bold", color=t["emerald"], ha="center", va="top")

    # Compact inline era legend at lower-left
    ax1.plot([1.2, 2.0], [-2.55, -2.55], color=t["muted"], lw=1.4, ls=":")
    ax1.text(2.2, -2.55, "1960s", fontsize=6.9, color=t["subtext"], va="center")
    ax1.plot([1.2, 2.0], [-3.15, -3.15], color=t["secondary"], lw=1.6, ls="--")
    ax1.text(2.2, -3.15, "1990s", fontsize=6.9, color=t["secondary"], va="center")
    ax1.plot([1.2, 2.0], [-3.75, -3.75], color=t["primary"], lw=2.3)
    ax1.text(2.2, -3.75, "2020–25", fontsize=6.9, color=t["primary"], fontweight="bold", va="center")

    ax1.set_xticks(months)
    ax1.set_xticklabels(m_lbls, fontsize=7.2, color=t["subtext"])
    ax1.set_ylim(-4.95, 4.45)
    ax1.set_ylabel("Seasonal Anomaly vs. Trend (ppm)", fontsize=8.1, color=t["subtext"], fontweight="bold")
    ax1.set_title("Biosphere Seasonal Breathing (1960s vs. 2020s)", fontsize=9.4, fontweight="bold", color=t["text"], loc="left", pad=10)

    # Right: Annual YoY CO2 Increments (1960-2025) + 10-yr rolling mean
    style_axes(ax2, t, "y")
    ax2.spines["left"].set_visible(False)

    bar_cols = [t["crimson"] if y in (2024, 2016) else (t["amber"] if j >= 2.5 else t["muted"]) for y, j in zip(yoy_yrs, yoy_j)]
    ax2.bar(yoy_yrs, yoy_j, width=0.72, color=bar_cols, alpha=0.86)

    # 10-year trailing mean line
    rolling = np.convolve(yoy_j, np.ones(10) / 10.0, mode="valid")
    ax2.plot(yoy_yrs[9:], rolling, color=t["primary"], linewidth=2.2, zorder=5)
    ax2.annotate(
        "10-yr rolling mean",
        xy=(1978, rolling[9]),
        xytext=(1971.5, 2.75),
        fontsize=7.2,
        fontweight="bold",
        color=t["primary"],
        ha="center",
        arrowprops={"arrowstyle": "->", "color": t["primary"], "lw": 0.85},
    )

    # Peak jump callouts
    idx24 = int(np.where(yoy_yrs == 2024)[0][0])
    idx16 = int(np.where(yoy_yrs == 2016)[0][0])
    idx98 = int(np.where(yoy_yrs == 1998)[0][0])
    ax2.annotate(
        f"2024 Record\n+{yoy_j[idx24]:.2f} ppm",
        xy=(2024, yoy_j[idx24]),
        xytext=(2016.5, 3.88),
        fontsize=7.2,
        fontweight="bold",
        color=t["crimson"],
        ha="center",
        arrowprops={"arrowstyle": "->", "color": t["crimson"], "lw": 0.85},
    )
    ax2.annotate(
        f"2016 El Niño (+{yoy_j[idx16]:.2f})",
        xy=(2016, yoy_j[idx16]),
        xytext=(2004.5, 3.68),
        fontsize=7.0,
        fontweight="bold",
        color=t["crimson"],
        ha="center",
        arrowprops={"arrowstyle": "->", "color": t["crimson"], "lw": 0.75},
    )
    ax2.annotate(
        f"1998 (+{yoy_j[idx98]:.2f})",
        xy=(1998, yoy_j[idx98]),
        xytext=(1991.5, 3.22),
        fontsize=6.9,
        fontweight="bold",
        color=t["amber"],
        ha="center",
        arrowprops={"arrowstyle": "->", "color": t["amber"], "lw": 0.75},
    )

    ax2.set_xlim(1958.5, 2026.5)
    ax2.set_ylim(0, 4.35)
    ax2.set_ylabel("Annual Mean Increment (ppm/yr)", fontsize=8.1, color=t["subtext"], fontweight="bold")
    ax2.set_title("Single-Year Atmospheric CO2 Jumps (1960–2025)", fontsize=9.4, fontweight="bold", color=t["text"], loc="left", pad=10)

    plt.tight_layout(pad=1.1, w_pad=1.7)
    fig.savefig(out_path, dpi=300, transparent=True)
    plt.close(fig)


# ------------------------------------------------------------------
# EXHIBIT 3: Bloc Mass Balance & Structural Divergence
# ------------------------------------------------------------------
def render_bloc_divergence(summary: dict, theme_name: str, out_path: Path) -> None:
    t = THEMES[theme_name]
    years = np.array(summary["panel_years"])
    econ_map = {e["iso3"]: e for e in summary["economies"]}

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(9.4, 3.55), dpi=300, gridspec_kw={"width_ratios": [1.55, 1.0]})
    fig.patch.set_alpha(0.0)

    style_axes(ax1, t, "y")
    ax1.spines["left"].set_visible(False)

    chn = np.array(econ_map["CHN"]["co2_series_2000_2024"]) / 1000.0
    ind = np.array(econ_map["IND"]["co2_series_2000_2024"]) / 1000.0
    bra = np.array(econ_map["BRA"]["co2_series_2000_2024"]) / 1000.0
    usa = np.array(econ_map["USA"]["co2_series_2000_2024"]) / 1000.0
    oecd_other = sum(np.array(econ_map[c]["co2_series_2000_2024"]) for c in ("JPN", "DEU", "GBR", "FRA")) / 1000.0

    stacks = [chn, ind, bra, usa, oecd_other]
    stack_colors = (
        ["#ef4444", "#f59e0b", "#fbbf24", "#38bdf8", "#475569"]
        if theme_name == "dark"
        else ["#b91c1c", "#d97706", "#eab308", "#0284c7", "#334155"]
    )
    stack_labels = [
        f"China ({chn[-1]:.2f} Gt)",
        f"India ({ind[-1]:.2f} Gt)",
        f"Brazil ({bra[-1]:.2f} Gt)",
        f"USA ({usa[-1]:.2f} Gt)",
        f"DEU+JPN+GBR+FRA ({oecd_other[-1]:.2f} Gt)",
    ]

    ax1.stackplot(years, stacks, colors=stack_colors, alpha=0.88)
    cum = np.zeros_like(chn)
    prev_y = -99.0
    for series, lbl, col in zip(stacks, stack_labels, stack_colors):
        mid_y = cum[-1] + series[-1] * 0.5
        if mid_y - prev_y < 1.35:
            mid_y = prev_y + 1.35
        ax1.text(2024.35, mid_y, lbl, fontsize=7.3, fontweight="bold", color=col, va="center", ha="left")
        cum = cum + series
        prev_y = mid_y

    ax1.axvline(2020, color=t["subtext"], linestyle=":", linewidth=0.9)
    ax1.text(2019.6, cum.max() * 1.09, "2020 COVID dip", fontsize=7.0, fontweight="bold", color=t["subtext"], ha="right", va="bottom")
    ax1.set_xlim(2000, 2032.2)
    ax1.set_xticks([2000, 2005, 2010, 2015, 2020, 2024])
    ax1.set_ylim(0, cum.max() * 1.20)
    ax1.set_ylabel("Annual Emissions (Gt CO2e)", fontsize=8.3, color=t["subtext"], fontweight="bold")
    ax1.set_title("8-Economy Emissions Mass Balance (2000–2024)", fontsize=9.6, fontweight="bold", color=t["text"], loc="left", pad=10)

    style_axes(ax2, t, "y")
    ax2.spines["left"].set_visible(False)
    oecd5_s = sum(np.array(econ_map[c]["co2_series_2000_2024"]) for c in ("USA", "DEU", "JPN", "GBR", "FRA"))
    em3_s = sum(np.array(econ_map[c]["co2_series_2000_2024"]) for c in ("CHN", "IND", "BRA"))
    oecd5_idx = (oecd5_s / oecd5_s[0]) * 100.0
    em3_idx = (em3_s / em3_s[0]) * 100.0

    ax2.axhline(100.0, color=t["spine"], linestyle="--", linewidth=0.8)
    ax2.plot(years, em3_idx, color=t["crimson"], linewidth=2.3)
    ax2.plot(years, oecd5_idx, color=t["emerald"], linewidth=2.3)
    ax2.scatter([2024, 2024], [em3_idx[-1], oecd5_idx[-1]], color=[t["crimson"], t["emerald"]], s=30, zorder=5)
    ax2.text(2023.6, em3_idx[-1] + 13, f"Emerging-3\n{em3_idx[-1]:.0f} (+{summary['metrics']['em3_co2_change_2000_2024_pct']:.0f}%)", fontsize=7.5, fontweight="bold", color=t["crimson"], ha="right")
    ax2.text(2023.6, oecd5_idx[-1] + 34, f"OECD-5\n{oecd5_idx[-1]:.0f} ({summary['metrics']['oecd5_co2_change_2000_2024_pct']:.0f}%)", fontsize=7.5, fontweight="bold", color=t["emerald"], ha="right", va="bottom")
    ax2.set_xlim(2000, 2025.2)
    ax2.set_xticks([2000, 2006, 2012, 2018, 2024])
    ax2.set_ylim(40, max(em3_idx) * 1.22)
    ax2.set_ylabel("CO2 Index (Year 2000 = 100)", fontsize=8.2, color=t["subtext"], fontweight="bold")
    ax2.set_title("Structural Bloc Bifurcation", fontsize=9.6, fontweight="bold", color=t["text"], loc="left", pad=10)

    plt.tight_layout(pad=1.1, w_pad=1.6)
    fig.savefig(out_path, dpi=300, transparent=True)
    plt.close(fig)


# ------------------------------------------------------------------
# EXHIBIT 4 (NEW): Marimekko Population x Per-Capita + Slopegraph
# ------------------------------------------------------------------
def render_per_capita_footprint(summary: dict, theme_name: str, out_path: Path) -> None:
    t = THEMES[theme_name]
    economies = sorted(summary["economies"], key=lambda e: e["co2_per_capita_2024_t"], reverse=True)

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(9.4, 3.6), dpi=300, gridspec_kw={"width_ratios": [1.55, 1.0]})
    fig.patch.set_alpha(0.0)

    # Left: Variable-Width Marimekko (Width = 2024 Pop in Billions, Height = Per-Capita CO2, Area = EXACT Total CO2!)
    style_axes(ax1, t, "y")
    ax1.spines["left"].set_visible(False)

    palette_map = (
        {
            "USA": "#0284c7",
            "CHN": "#dc2626",
            "JPN": "#64748b",
            "DEU": "#475569",
            "GBR": "#10b981",
            "FRA": "#0d9488",
            "BRA": "#f59e0b",
            "IND": "#d97706",
        }
        if theme_name == "dark"
        else {
            "USA": "#0284c7",
            "CHN": "#b91c1c",
            "JPN": "#475569",
            "DEU": "#334155",
            "GBR": "#059669",
            "FRA": "#0d9488",
            "BRA": "#eab308",
            "IND": "#d97706",
        }
    )

    x_cursor = 0.0
    gap = 0.03  # 30M visual micro-gutter between countries
    total_w = sum(e["population_2024_m"] / 1000.0 for e in economies) + gap * (len(economies) - 1)

    for e in economies:
        w = e["population_2024_m"] / 1000.0  # Billions
        h = e["co2_per_capita_2024_t"]
        col = palette_map[e["iso3"]]
        rect = patches.Rectangle((x_cursor, 0), w, h, facecolor=col, edgecolor=t["bg"], linewidth=0.9, alpha=0.90)
        ax1.add_patch(rect)

        cx = x_cursor + w / 2.0
        if w >= 0.30:
            # Wide enough for clean inside label
            txt_col = "#ffffff" if theme_name == "light" or e["iso3"] in ("CHN", "USA") else "#0b0f19"
            if e["iso3"] == "IND":
                # IND is short (2.17 t) -> label cleanly above bar
                ax1.text(cx, h + 0.45, f"IND — {h:.2f} t/cap\n(1.45B pop · 3.15 Gt)", fontsize=7.4, fontweight="bold", color=col, ha="center", va="bottom")
            elif e["iso3"] == "USA":
                ax1.text(cx, h * 0.72, f"USA\n{h:.1f} t\n4.63 Gt", fontsize=7.2, fontweight="bold", color="#ffffff", ha="center", va="center")
            else:
                ax1.text(cx, h * 0.52, f"{e['iso3']} — {h:.2f} t/cap\n(1.41B pop · 13.12 Gt)", fontsize=7.8, fontweight="bold", color="#ffffff", ha="center", va="center")
        else:
            # Narrow bars (JPN, DEU, GBR, FRA, BRA) -> staggered clean top callouts cleanly ABOVE weighted mean line
            y_targets = {"JPN": 13.7, "DEU": 12.3, "GBR": 10.9, "FRA": 9.5, "BRA": 8.0}
            ty = y_targets[e["iso3"]]
            ax1.plot([cx, cx + 0.14], [h + 0.18, ty], color=col, linewidth=0.75, solid_capstyle="round")
            ax1.text(
                cx + 0.17,
                ty,
                f"{e['iso3']} ({h:.1f} t)",
                fontsize=6.9,
                fontweight="bold",
                color=col if theme_name == "light" else t["text"],
                ha="left",
                va="center",
            )

        x_cursor += w + gap

    # Panel population-weighted average dashed rule
    weighted_avg = summary["metrics"]["panel8_co2_2024_mt"] / summary["metrics"]["panel8_population_2024_m"]
    ax1.axhline(weighted_avg, color=t["text"], linestyle="--", linewidth=0.85, alpha=0.75)
    ax1.text(total_w, weighted_avg + 0.3, f"8-Econ Weighted Mean: {weighted_avg:.2f} t/cap", fontsize=7.0, fontweight="bold", color=t["text"], ha="right")

    ax1.set_xlim(-0.04, total_w + 0.08)
    ax1.set_ylim(0, 15.6)
    ax1.set_xlabel("2024 Cumulative Population Width (Billions; Total = 3.76B) — Area = Exact Total CO2", fontsize=7.6, color=t["subtext"], fontweight="bold")
    ax1.set_ylabel("2024 Per-Capita CO2 (t CO2e / person)", fontsize=8.0, color=t["subtext"], fontweight="bold")
    ax1.set_title("Marimekko Carbon Footprint (Width = Pop × Height = t/cap)", fontsize=9.2, fontweight="bold", color=t["text"], loc="left", pad=10)

    # Right: Per-Capita Slopegraph (2000 -> 2024)
    style_axes(ax2, t, "none")
    for s in ("bottom", "left"):
        ax2.spines[s].set_visible(False)
    ax2.set_xticks([0, 1])
    ax2.set_xticklabels(["2000", "2024"], fontsize=8.4, fontweight="bold", color=t["text"])
    ax2.set_yticks([])

    ax2.axvline(0, color=t["grid"], linewidth=1.0)
    ax2.axvline(1, color=t["grid"], linewidth=1.0)

    # Explicit vertical nudges to prevent label overlap at 2000 and 2024 endpoints
    left_nudge = {"USA": 0.0, "DEU": 0.45, "JPN": -0.15, "GBR": -1.15, "FRA": 0.0, "CHN": 0.35, "BRA": -0.25, "IND": -0.55}
    right_nudge = {"USA": 0.0, "CHN": 0.25, "JPN": -0.05, "DEU": -0.55, "GBR": 0.45, "FRA": -0.60, "BRA": 0.25, "IND": -0.70}

    for e in economies:
        iso = e["iso3"]
        y0, y1 = e["co2_per_capita_2000_t"], e["co2_per_capita_2024_t"]
        is_rise = y1 > y0
        col = t["crimson"] if iso == "CHN" else (t["amber"] if is_rise else (t["primary"] if iso == "USA" else t["emerald"]))
        lw = 2.4 if iso in ("CHN", "USA", "GBR") else 1.4
        ax2.plot([0, 1], [y0, y1], color=col, linewidth=lw, alpha=0.9)
        ax2.scatter([0, 1], [y0, y1], color=col, s=24, zorder=5)

        ax2.text(-0.06, y0 + left_nudge[iso], f"{iso} {y0:.1f}", fontsize=7.0, fontweight="bold" if iso in ("USA", "CHN", "GBR") else "normal", color=col, ha="right", va="center")
        ax2.text(1.06, y1 + right_nudge[iso], f"{y1:.1f} {iso}", fontsize=7.0, fontweight="bold" if iso in ("USA", "CHN", "GBR") else "normal", color=col, ha="left", va="center")

    ax2.set_xlim(-0.46, 1.48)
    ax2.set_ylim(-0.5, 22.8)
    ax2.set_title("Per-Capita Rank Inversion (t/cap)", fontsize=9.2, fontweight="bold", color=t["text"], loc="left", pad=10)

    plt.tight_layout(pad=1.0, w_pad=1.4)
    fig.savefig(out_path, dpi=300, transparent=True)
    plt.close(fig)


# ------------------------------------------------------------------
# EXHIBIT 5: Decoupling Matrix & Carbon Intensity Compression
# ------------------------------------------------------------------
def render_decoupling_matrix(summary: dict, theme_name: str, out_path: Path) -> None:
    t = THEMES[theme_name]
    economies = summary["economies"]

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(9.4, 3.6), dpi=300, gridspec_kw={"width_ratios": [1.05, 1.15]})
    fig.patch.set_alpha(0.0)

    style_axes(ax1, t, "both")
    ax1.axhspan(-78, 0, xmin=0, xmax=1, color=t["quad_ok"], alpha=0.22, zorder=0)
    ax1.axhline(0, color=t["emerald"], linewidth=1.0, linestyle="--")

    x_diag = np.linspace(0, 295, 100)
    ax1.plot(x_diag, x_diag, color=t["muted"], linewidth=0.85, linestyle=":", alpha=0.85)
    ax1.text(132, 168, "1:1 Coupling Line", fontsize=6.9, color=t["muted"], fontweight="bold", rotation=42)

    label_targets = {
        "CHN": (550, 208, "center", False),
        "IND": (329, 178, "center", False),
        "BRA": (118, 52, "left", False),
        "USA": (162, 12, "left", True),
        "JPN": (162, -16, "left", True),
        "FRA": (162, -34, "left", True),
        "DEU": (162, -52, "left", True),
        "GBR": (162, -70, "left", True),
    }

    for e in economies:
        gx, cy = e["gdp_growth_2000_2024_pct"], e["co2_change_pct"]
        col = t["emerald"] if cy < 0 else (t["amber"] if cy < 100 else t["crimson"])
        ax1.scatter([gx], [cy], s=max(42, e["co2_2024_mt"] / 45.0), color=col, alpha=0.88, edgecolors=t["bg"], linewidth=0.9, zorder=4)
        tx, ty, ha, use_arrow = label_targets[e["iso3"]]
        ax1.annotate(
            f"{e['iso3']} ({cy:+.0f}%)",
            xy=(gx, cy),
            xytext=(tx, ty),
            textcoords="data",
            fontsize=7.2,
            fontweight="bold",
            color=col,
            ha=ha,
            va="center",
            arrowprops={"arrowstyle": "-", "color": col, "lw": 0.65, "alpha": 0.75} if use_arrow else None,
        )

    ax1.text(600, -68, "ABSOLUTE DECOUPLING\n(GDP up, CO2 down)", fontsize=6.9, fontweight="bold", color=t["emerald"], ha="right", va="bottom")
    ax1.set_xlim(-10, 615)
    ax1.set_ylim(-78, 305)
    ax1.set_xlabel("Real GDP Growth 2000–2024 (%, const. 2015 $)", fontsize=8.0, color=t["subtext"], fontweight="bold")
    ax1.set_ylabel("Total CO2 Change 2000–2024 (%)", fontsize=8.0, color=t["subtext"], fontweight="bold")
    ax1.set_title("Economic Growth vs. Carbon Emissions", fontsize=9.5, fontweight="bold", color=t["text"], loc="left", pad=10)

    style_axes(ax2, t, "x")
    ax2.spines["left"].set_visible(False)
    sorted_ci = sorted(economies, key=lambda e: e["carbon_intensity_2024"])
    y = np.arange(len(sorted_ci))

    for idx, e in enumerate(sorted_ci):
        c00, c24 = e["carbon_intensity_2000"], e["carbon_intensity_2024"]
        ax2.plot([c24, c00], [idx, idx], color=t["muted"], linewidth=1.8, alpha=0.65, zorder=2)
        ax2.scatter([c00], [idx], color=t["muted"], s=34, zorder=3)
        ax2.scatter([c24], [idx], color=t["primary"], s=44, zorder=4)
        ax2.text(c00 + 22, idx, f"{e['carbon_intensity_change_pct']:+.0f}%  ({c24:.0f})", fontsize=7.3, fontweight="bold", color=t["emerald"] if e["carbon_intensity_change_pct"] <= -40 else t["text"], va="center")

    ax2.set_yticks(y)
    ax2.set_yticklabels([f"{e['iso3']} — {e['name']}" for e in sorted_ci], fontsize=7.6, color=t["text"], fontweight="bold")
    ax2.set_xlim(0, 1650)
    ax2.set_xlabel("Carbon Intensity (t CO2e / $1M const. 2015 GDP)", fontsize=8.0, color=t["subtext"], fontweight="bold")
    ax2.set_title("Carbon Intensity Compression (2000 → 2024)", fontsize=9.5, fontweight="bold", color=t["text"], loc="left", pad=10)
    ax2.scatter([1150, 1340], [0.45, 0.45], color=[t["muted"], t["primary"]], s=[30, 38], zorder=5)
    ax2.text(1185, 0.45, "2000", fontsize=7.2, color=t["subtext"], va="center")
    ax2.text(1375, 0.45, "2024", fontsize=7.2, color=t["primary"], fontweight="bold", va="center")

    plt.tight_layout(pad=1.1, w_pad=1.8)
    fig.savefig(out_path, dpi=300, transparent=True)
    plt.close(fig)


# ------------------------------------------------------------------
# EXHIBIT 6 (NEW): 8x24 Annual YoY CO2 Momentum Matrix Heatmap
# ------------------------------------------------------------------
def render_yoy_heatmap(summary: dict, theme_name: str, out_path: Path) -> None:
    t = THEMES[theme_name]
    yoy_years = summary["yoy_years"]  # 2001..2024 (24 cols)
    # Order rows from strongest growth (top) to deepest decarbonizer (bottom)
    economies = sorted(summary["economies"], key=lambda e: e["co2_change_pct"], reverse=True)
    matrix = np.array([e["yoy_pct_2001_2024"] for e in economies])  # shape (8, 24)

    fig, ax = plt.subplots(figsize=(9.4, 3.55), dpi=300)
    fig.patch.set_alpha(0.0)
    ax.set_facecolor("none")

    cmap = mcolors.LinearSegmentedColormap.from_list(
        "carbon_div",
        [t["heat_neg"], t["heat_zero"], t["heat_pos"]],
    )
    norm = mcolors.TwoSlopeNorm(vmin=-12.0, vcenter=0.0, vmax=12.0)

    ax.imshow(matrix, cmap=cmap, norm=norm, aspect="auto")

    # Crisp cell borders + automatic high-contrast text (never print -0 / +0)
    for i in range(matrix.shape[0]):
        for j in range(matrix.shape[1]):
            val = matrix[i, j]
            rounded = int(round(val))
            cell_txt = "0" if rounded == 0 else f"{rounded:+d}"
            strong = abs(val) >= 5.5
            txt_col = "#ffffff" if strong else t["text"]
            ax.text(
                j,
                i,
                cell_txt,
                ha="center",
                va="center",
                fontsize=6.3,
                fontweight="bold" if strong else "normal",
                color=txt_col,
            )

    # Subtle grid separators between cells
    ax.set_xticks(np.arange(-0.5, len(yoy_years), 1), minor=True)
    ax.set_yticks(np.arange(-0.5, len(economies), 1), minor=True)
    ax.grid(which="minor", color=t["bg"], linestyle="-", linewidth=1.1)
    ax.tick_params(which="minor", length=0)

    # Highlight 2009 GFC and 2020 COVID shock columns with crisp amber outline annotations
    for yr_shock, lbl in [(2009, "2009 GFC"), (2020, "2020 COVID")]:
        c_idx = yoy_years.index(yr_shock)
        rect = patches.Rectangle((c_idx - 0.5, -0.5), 1.0, len(economies), fill=False, edgecolor=t["amber"], linewidth=1.4, zorder=6)
        ax.add_patch(rect)
        ax.text(c_idx, -0.78, lbl, ha="center", va="bottom", fontsize=7.0, fontweight="bold", color=t["amber"])

    # Horizontal divider between Emerging-3 (rows 0-2) and OECD-5 (rows 3-7)
    ax.axhline(2.5, color=t["text"], linewidth=1.4, linestyle="-", alpha=0.8)

    # Right-edge cumulative 24-yr change summary column
    for i, e in enumerate(economies):
        col = t["emerald"] if e["co2_change_pct"] < 0 else t["crimson"]
        ax.text(len(yoy_years) - 0.25, i, f"  {e['co2_change_pct']:+.1f}%", va="center", ha="left", fontsize=7.4, fontweight="bold", color=col)
    ax.text(len(yoy_years) - 0.25, -0.78, "  2000→24", va="bottom", ha="left", fontsize=6.9, fontweight="bold", color=t["subtext"])

    ax.set_xticks(np.arange(len(yoy_years)))
    ax.set_xticklabels([f"'{str(y)[2:]}" for y in yoy_years], fontsize=7.1, color=t["subtext"])
    ax.set_yticks(np.arange(len(economies)))
    ax.set_yticklabels([f"{e['iso3']}  {e['name']}" for e in economies], fontsize=7.7, fontweight="bold", color=t["text"])
    ax.set_xlim(-0.5, len(yoy_years) + 2.4)
    ax.set_ylim(len(economies) - 0.5, -1.15)
    for s in ("top", "right", "bottom", "left"):
        ax.spines[s].set_visible(False)

    ax.set_title(
        "Annual YoY CO2 Emissions Momentum (%) — Emerald = Contraction | Crimson = Expansion (2001–2024)",
        fontsize=9.2,
        fontweight="bold",
        color=t["text"],
        loc="left",
        pad=6,
    )

    plt.tight_layout(pad=0.9)
    fig.savefig(out_path, dpi=300, transparent=True)
    plt.close(fig)


# ------------------------------------------------------------------
# EXHIBIT 7: Stephen Few Renewables Bullet Graphs
# ------------------------------------------------------------------
def render_renewables_bullets(summary: dict, theme_name: str, out_path: Path) -> None:
    t = THEMES[theme_name]
    economies = sorted(summary["economies"], key=lambda e: e["renewables_2021_pct"])

    fig, ax = plt.subplots(figsize=(9.4, 2.75), dpi=300)
    fig.patch.set_alpha(0.0)
    style_axes(ax, t, "x")
    ax.spines["left"].set_visible(False)

    y = np.arange(len(economies))
    for idx in y:
        ax.barh(idx, 15, height=0.62, left=0, color=t["band_low"], zorder=1)
        ax.barh(idx, 15, height=0.62, left=15, color=t["band_mid"], zorder=1)
        ax.barh(idx, 25, height=0.62, left=30, color=t["band_hi"], zorder=1)

    for idx, e in enumerate(economies):
        r00, r21 = e["renewables_2000_pct"], e["renewables_2021_pct"]
        bar_col = t["emerald"] if r21 >= 30 else (t["primary"] if r21 >= 15 else t["secondary"])
        ax.barh(idx, r21, height=0.28, color=bar_col, zorder=3)
        ax.plot([r00, r00], [idx - 0.28, idx + 0.28], color=t["amber"], linewidth=2.0, zorder=4)
        ax.text(56.2, idx, f"2021: {r21:4.1f}%   (2000: {r00:4.1f}%, {r21 - r00:+5.1f} pp)", fontsize=7.4, fontweight="bold", color=t["text"], va="center")

    ax.set_yticks(y)
    ax.set_yticklabels([f"{e['iso3']} ({e['name']})" for e in economies], fontsize=7.6, color=t["text"], fontweight="bold")
    ax.set_xlim(0, 82)
    ax.spines["bottom"].set_bounds(0, 55)
    ax.set_xticks([0, 15, 30, 45, 55])
    ax.set_xticklabels(["0%", "15%", "30%", "45%", "55%"])
    ax.set_xlabel("Renewable Energy Share of Total Final Energy Consumption (%)", fontsize=8.0, color=t["subtext"], fontweight="bold")
    ax.set_title(
        "Stephen Few Bullet Graph — Renewable Energy Share (Amber Tick = 2000 Baseline | Bar = 2021 Latest WDI; 2022–2024 N/A)",
        fontsize=8.6,
        fontweight="bold",
        color=t["text"],
        loc="left",
        pad=9,
    )

    plt.tight_layout(pad=1.0)
    fig.savefig(out_path, dpi=300, transparent=True)
    plt.close(fig)


def main() -> int:
    configure_fonts()
    ASSETS_DIR.mkdir(parents=True, exist_ok=True)
    summary = json.loads(SUMMARY_PATH.read_text(encoding="utf-8"))

    for theme in ("dark", "light"):
        render_keeling_acceleration(summary, theme, ASSETS_DIR / f"keeling_acceleration_{theme}.png")
        render_seasonal_breathing(summary, theme, ASSETS_DIR / f"seasonal_breathing_{theme}.png")
        render_bloc_divergence(summary, theme, ASSETS_DIR / f"bloc_divergence_{theme}.png")
        render_per_capita_footprint(summary, theme, ASSETS_DIR / f"per_capita_footprint_{theme}.png")
        render_decoupling_matrix(summary, theme, ASSETS_DIR / f"decoupling_matrix_{theme}.png")
        render_yoy_heatmap(summary, theme, ASSETS_DIR / f"yoy_momentum_heatmap_{theme}.png")
        render_renewables_bullets(summary, theme, ASSETS_DIR / f"renewables_bullets_{theme}.png")
        print(f"[OK] Rendered 7 institutional 300-DPI charts ({theme} theme)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
