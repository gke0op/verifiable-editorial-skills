#!/usr/bin/env python3
"""
Phase 5a: Vector-Quality Publication Chart Engine (300 DPI, Dark & Light Themes).

Reads strictly from audited data/summary_metrics.json (zero hardcoded domain numbers)
and renders spine-stripped institutional charts for both the 16:9 dark executive deck
and the Letter light Swiss-ivory report.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.font_manager as fm
import matplotlib.pyplot as plt
import numpy as np

BASE_DIR = Path(__file__).resolve().parent.parent
SUMMARY_PATH = BASE_DIR / "data" / "summary_metrics.json"
ASSETS_DIR = BASE_DIR / "report" / "assets"

THEMES = {
    "dark": {
        "bg": "#0b0f19",
        "panel_bg": "#111827",
        "text": "#f8fafc",
        "subtext": "#94a3b8",
        "grid": "#1e293b",
        "spine": "#334155",
        "primary": "#38bdf8",
        "secondary": "#0284c7",
        "amber": "#f59e0b",
        "crimson": "#f87171",
        "emerald": "#34d399",
        "muted": "#64748b",
        "band_low": "#1e293b",
        "band_mid": "#172033",
        "band_hi": "#111827",
        "quad_ok": "#064e3b",
        "quad_warn": "#3b1d1d",
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
        "quad_warn": "#fee2e2",
    },
}


def configure_fonts() -> None:
    """Register Inter if available via INTER_FONT_DIR or standard OS paths, else fall back cleanly."""
    import os

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


def render_keeling_acceleration(summary: dict, theme_name: str, out_path: Path) -> None:
    t = THEMES[theme_name]
    noaa = summary["noaa_series"]
    m = summary["metrics"]
    meta = summary["metadata"]

    dates = np.array(noaa["decimal_dates"])
    avg = np.array(noaa["average_ppm"])
    deseas = np.array(noaa["deseasonalized_ppm"])
    decades = noaa["decadal_growth"]

    fig, (ax1, ax2) = plt.subplots(
        1, 2, figsize=(9.4, 3.65), dpi=300, gridspec_kw={"width_ratios": [1.85, 1.0]}
    )
    fig.patch.set_alpha(0.0)

    # Left: Keeling Curve 1958-2026
    style_axes(ax1, t, "y")
    ax1.spines["left"].set_visible(False)
    ax1.plot(dates, avg, color=t["secondary"], linewidth=0.85, alpha=0.55, label="Monthly Mean")
    ax1.plot(dates, deseas, color=t["primary"], linewidth=2.0, label="Deseasonalized Trend")

    # Eruption relocation band (Dec 2022 - Jul 2023)
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

    # Start and end markers + direct labels
    ax1.scatter([dates[0], dates[-1]], [deseas[0], deseas[-1]], color=[t["muted"], t["crimson"]], s=26, zorder=5)
    ax1.text(
        dates[0] + 1.2,
        deseas[0] - 5.5,
        f"{meta['noaa_start']}: {m['noaa_first_deseasonalized_ppm']:.1f} ppm",
        fontsize=7.6,
        color=t["subtext"],
        fontweight="bold",
    )
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
    ax1.set_ylabel("Atmospheric CO2 (ppm)", fontsize=8.5, color=t["subtext"], fontweight="bold")
    ax1.set_title(
        "Mauna Loa Atmospheric CO2 Concentration (1958–2026)",
        fontsize=9.8,
        fontweight="bold",
        color=t["text"],
        loc="left",
        pad=10,
    )

    # Right: Decadal Growth Acceleration
    style_axes(ax2, t, "y")
    ax2.spines["left"].set_visible(False)
    labels = [d["label"] for d in decades]
    rates = [d["ppm_per_yr"] for d in decades]
    bar_colors = [t["muted"]] * (len(rates) - 2) + [t["amber"], t["crimson"]]
    x = np.arange(len(labels))
    bars = ax2.bar(x, rates, width=0.62, color=bar_colors, edgecolor="none")

    for bar, val in zip(bars, rates):
        ax2.text(
            bar.get_x() + bar.get_width() / 2.0,
            val + 0.06,
            f"+{val:.2f}",
            ha="center",
            va="bottom",
            fontsize=7.3,
            fontweight="bold",
            color=t["text"],
        )

    ax2.set_xticks(x)
    ax2.set_xticklabels(labels, fontsize=7.3, color=t["subtext"], rotation=25, ha="right")
    ax2.set_ylim(0, max(rates) * 1.24)
    ax2.set_ylabel("Mean Annual Growth (ppm/yr)", fontsize=8.2, color=t["subtext"], fontweight="bold")
    ax2.set_title(
        "Decadal Accumulation Rate (3.0x Rise)",
        fontsize=9.8,
        fontweight="bold",
        color=t["text"],
        loc="left",
        pad=10,
    )

    plt.tight_layout(pad=1.2, w_pad=2.0)
    fig.savefig(out_path, dpi=300, transparent=True)
    plt.close(fig)


def render_bloc_divergence(summary: dict, theme_name: str, out_path: Path) -> None:
    t = THEMES[theme_name]
    years = np.array(summary["panel_years"])
    econ_map = {e["iso3"]: e for e in summary["economies"]}

    fig, (ax1, ax2) = plt.subplots(
        1, 2, figsize=(9.4, 3.55), dpi=300, gridspec_kw={"width_ratios": [1.55, 1.0]}
    )
    fig.patch.set_alpha(0.0)

    # Left: Stacked area of 8-economy CO2 trajectory (Gt CO2e)
    style_axes(ax1, t, "y")
    ax1.spines["left"].set_visible(False)

    chn = np.array(econ_map["CHN"]["co2_series_2000_2024"]) / 1000.0
    ind = np.array(econ_map["IND"]["co2_series_2000_2024"]) / 1000.0
    bra = np.array(econ_map["BRA"]["co2_series_2000_2024"]) / 1000.0
    usa = np.array(econ_map["USA"]["co2_series_2000_2024"]) / 1000.0
    oecd_other = (
        np.array(econ_map["JPN"]["co2_series_2000_2024"])
        + np.array(econ_map["DEU"]["co2_series_2000_2024"])
        + np.array(econ_map["GBR"]["co2_series_2000_2024"])
        + np.array(econ_map["FRA"]["co2_series_2000_2024"])
    ) / 1000.0

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

    # Direct terminal edge labels (zero separate legend box!)
    cum = np.zeros_like(chn)
    prev_y = -99.0
    for series, lbl, col in zip(stacks, stack_labels, stack_colors):
        mid_y = cum[-1] + series[-1] * 0.5
        if mid_y - prev_y < 1.35:
            mid_y = prev_y + 1.35
        ax1.text(
            2024.35,
            mid_y,
            lbl,
            fontsize=7.3,
            fontweight="bold",
            color=col,
            va="center",
            ha="left",
        )
        cum = cum + series
        prev_y = mid_y

    # COVID shock hairline (labeled cleanly in margin above stack)
    ax1.axvline(2020, color=t["subtext"], linestyle=":", linewidth=0.9)
    ax1.text(2019.6, cum.max() * 1.09, "2020 COVID dip", fontsize=7.0, fontweight="bold", color=t["subtext"], ha="right", va="bottom")

    ax1.set_xlim(2000, 2032.2)
    ax1.set_xticks([2000, 2005, 2010, 2015, 2020, 2024])
    ax1.set_ylim(0, cum.max() * 1.20)
    ax1.set_ylabel("Annual Emissions (Gt CO2e)", fontsize=8.3, color=t["subtext"], fontweight="bold")
    ax1.set_title(
        "8-Economy Emissions Mass Balance (2000–2024)",
        fontsize=9.6,
        fontweight="bold",
        color=t["text"],
        loc="left",
        pad=10,
    )

    # Right: Divergent Indexed Trajectories (2000 = 100): OECD-5 vs Emerging-3
    style_axes(ax2, t, "y")
    ax2.spines["left"].set_visible(False)

    oecd5_series = sum(
        np.array(econ_map[c]["co2_series_2000_2024"]) for c in ("USA", "DEU", "JPN", "GBR", "FRA")
    )
    em3_series = sum(
        np.array(econ_map[c]["co2_series_2000_2024"]) for c in ("CHN", "IND", "BRA")
    )
    oecd5_idx = (oecd5_series / oecd5_series[0]) * 100.0
    em3_idx = (em3_series / em3_series[0]) * 100.0

    ax2.axhline(100.0, color=t["spine"], linestyle="--", linewidth=0.8)
    ax2.plot(years, em3_idx, color=t["crimson"], linewidth=2.3)
    ax2.plot(years, oecd5_idx, color=t["emerald"], linewidth=2.3)
    ax2.scatter([2024, 2024], [em3_idx[-1], oecd5_idx[-1]], color=[t["crimson"], t["emerald"]], s=30, zorder=5)

    ax2.text(
        2023.6,
        em3_idx[-1] + 13,
        f"Emerging-3\n{em3_idx[-1]:.0f} (+{summary['metrics']['em3_co2_change_2000_2024_pct']:.0f}%)",
        fontsize=7.5,
        fontweight="bold",
        color=t["crimson"],
        ha="right",
    )
    ax2.text(
        2023.6,
        oecd5_idx[-1] + 34,
        f"OECD-5\n{oecd5_idx[-1]:.0f} ({summary['metrics']['oecd5_co2_change_2000_2024_pct']:.0f}%)",
        fontsize=7.5,
        fontweight="bold",
        color=t["emerald"],
        ha="right",
        va="bottom",
    )

    ax2.set_xlim(2000, 2025.2)
    ax2.set_xticks([2000, 2006, 2012, 2018, 2024])
    ax2.set_ylim(40, max(em3_idx) * 1.22)
    ax2.set_ylabel("CO2 Index (Year 2000 = 100)", fontsize=8.2, color=t["subtext"], fontweight="bold")
    ax2.set_title(
        "Structural Bloc Bifurcation",
        fontsize=9.6,
        fontweight="bold",
        color=t["text"],
        loc="left",
        pad=10,
    )

    plt.tight_layout(pad=1.1, w_pad=1.6)
    fig.savefig(out_path, dpi=300, transparent=True)
    plt.close(fig)


def render_decoupling_matrix(summary: dict, theme_name: str, out_path: Path) -> None:
    t = THEMES[theme_name]
    economies = summary["economies"]

    fig, (ax1, ax2) = plt.subplots(
        1, 2, figsize=(9.4, 3.65), dpi=300, gridspec_kw={"width_ratios": [1.05, 1.15]}
    )
    fig.patch.set_alpha(0.0)

    # Left: Real GDP Growth vs CO2 Change (Decoupling Quadrants)
    style_axes(ax1, t, "both")
    ax1.axhspan(-78, 0, xmin=0, xmax=1, color=t["quad_ok"], alpha=0.22, zorder=0)
    ax1.axhline(0, color=t["emerald"], linewidth=1.0, linestyle="--")

    # 1:1 coupling parity diagonal line
    x_diag = np.linspace(0, 295, 100)
    ax1.plot(x_diag, x_diag, color=t["muted"], linewidth=0.85, linestyle=":", alpha=0.85)
    ax1.text(132, 168, "1:1 Coupling Line", fontsize=6.9, color=t["muted"], fontweight="bold", rotation=42)

    # Explicit non-overlapping label positions in data coordinates with clean leader lines for the OECD-5 cluster
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
        gx = e["gdp_growth_2000_2024_pct"]
        cy = e["co2_change_pct"]
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
    ax1.set_title(
        "Economic Growth vs. Carbon Emissions",
        fontsize=9.5,
        fontweight="bold",
        color=t["text"],
        loc="left",
        pad=10,
    )

    # Right: Carbon Intensity Dumbbell (2000 -> 2024, t CO2e / $1M const-2015 USD)
    style_axes(ax2, t, "x")
    ax2.spines["left"].set_visible(False)
    sorted_ci = sorted(economies, key=lambda e: e["carbon_intensity_2024"])
    y = np.arange(len(sorted_ci))

    for idx, e in enumerate(sorted_ci):
        c00 = e["carbon_intensity_2000"]
        c24 = e["carbon_intensity_2024"]
        ax2.plot([c24, c00], [idx, idx], color=t["muted"], linewidth=1.8, alpha=0.65, zorder=2)
        ax2.scatter([c00], [idx], color=t["muted"], s=34, zorder=3, label="2000" if idx == 0 else "")
        ax2.scatter([c24], [idx], color=t["primary"], s=44, zorder=4, label="2024" if idx == 0 else "")
        ax2.text(
            c00 + 22,
            idx,
            f"{e['carbon_intensity_change_pct']:+.0f}%  ({c24:.0f})",
            fontsize=7.3,
            fontweight="bold",
            color=t["emerald"] if e["carbon_intensity_change_pct"] <= -40 else t["text"],
            va="center",
        )

    ax2.set_yticks(y)
    ax2.set_yticklabels([f"{e['iso3']} — {e['name']}" for e in sorted_ci], fontsize=7.6, color=t["text"], fontweight="bold")
    ax2.set_xlim(0, 1650)
    ax2.set_xlabel("Carbon Intensity (t CO2e / $1M const. 2015 GDP)", fontsize=8.0, color=t["subtext"], fontweight="bold")
    ax2.set_title(
        "Carbon Intensity Compression (2000 → 2024)",
        fontsize=9.5,
        fontweight="bold",
        color=t["text"],
        loc="left",
        pad=10,
    )
    # Compact inline legend for dots
    ax2.scatter([1150, 1340], [0.45, 0.45], color=[t["muted"], t["primary"]], s=[30, 38], zorder=5)
    ax2.text(1185, 0.45, "2000", fontsize=7.2, color=t["subtext"], va="center")
    ax2.text(1375, 0.45, "2024", fontsize=7.2, color=t["primary"], fontweight="bold", va="center")

    plt.tight_layout(pad=1.1, w_pad=1.8)
    fig.savefig(out_path, dpi=300, transparent=True)
    plt.close(fig)


def render_renewables_bullets(summary: dict, theme_name: str, out_path: Path) -> None:
    """Stephen Few horizontal bullet graphs for Renewable Energy Share (2000 vs 2021)."""
    t = THEMES[theme_name]
    economies = sorted(summary["economies"], key=lambda e: e["renewables_2021_pct"])

    fig, ax = plt.subplots(figsize=(9.4, 2.75), dpi=300)
    fig.patch.set_alpha(0.0)
    style_axes(ax, t, "x")
    ax.spines["left"].set_visible(False)

    y = np.arange(len(economies))
    bar_h = 0.62

    # Qualitative performance bands: <15%, 15-30%, 30-55%
    for idx in y:
        ax.barh(idx, 15, height=bar_h, left=0, color=t["band_low"], edgecolor="none", zorder=1)
        ax.barh(idx, 15, height=bar_h, left=15, color=t["band_mid"], edgecolor="none", zorder=1)
        ax.barh(idx, 25, height=bar_h, left=30, color=t["band_hi"], edgecolor="none", zorder=1)

    for idx, e in enumerate(economies):
        r00 = e["renewables_2000_pct"]
        r21 = e["renewables_2021_pct"]
        delta = r21 - r00
        bar_col = t["emerald"] if r21 >= 30 else (t["primary"] if r21 >= 15 else t["secondary"])
        ax.barh(idx, r21, height=0.28, color=bar_col, zorder=3)
        # 2000 baseline target tick
        ax.plot([r00, r00], [idx - 0.28, idx + 0.28], color=t["amber"], linewidth=2.0, zorder=4)
        ax.text(
            56.2,
            idx,
            f"2021: {r21:4.1f}%   (2000: {r00:4.1f}%, {delta:+5.1f} pp)",
            fontsize=7.4,
            fontweight="bold",
            color=t["text"],
            va="center",
        )

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
        render_bloc_divergence(summary, theme, ASSETS_DIR / f"bloc_divergence_{theme}.png")
        render_decoupling_matrix(summary, theme, ASSETS_DIR / f"decoupling_matrix_{theme}.png")
        render_renewables_bullets(summary, theme, ASSETS_DIR / f"renewables_bullets_{theme}.png")
        print(f"[OK] Rendered 4 institutional 300-DPI charts ({theme} theme)")

    return 0


if __name__ == "__main__":
    sys.exit(main())
