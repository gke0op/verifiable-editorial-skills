#!/usr/bin/env python3
"""
Phase 3: Extended Keynote Synthesis & Atomic Provenance Registration.

Computes all datasets powering the 9-slide dual-theme visual-heavy presentation:
  - Full NOAA Mauna Loa monthly curve, decadal growth, seasonal anomaly fingerprints
    (1960s / 1990s / 2020-25), and 1959-2025 annual YoY ppm increments
  - 8-Economy mass balance, population-weighted Marimekko dimensions, 2000->2024
    per-capita inversion, decoupling quadrants, carbon intensity compression,
    24-year annual YoY CO2 momentum matrix, and renewables bullet telemetry
  - 100% atomic provenance registration in data/provenance_ledger.json
"""
from __future__ import annotations

import csv
import hashlib
import json
import sys
from pathlib import Path
from typing import Any, Optional

from validate_reality import (
    BASE_DIR,
    RAW_DIR,
    VALID_ISO3,
    EconomyYearTelemetry,
    MaunaLoaObservation,
    validate_all,
)

DATA_DIR = BASE_DIR / "data"
PANEL_CSV = DATA_DIR / "processed_panel.csv"
LEDGER_PATH = DATA_DIR / "provenance_ledger.json"
SUMMARY_PATH = DATA_DIR / "summary_metrics.json"

OECD5 = ("USA", "DEU", "JPN", "GBR", "FRA")
EMERGING3 = ("CHN", "IND", "BRA")

SHORT_NAMES = {
    "USA": "United States",
    "CHN": "China",
    "DEU": "Germany",
    "IND": "India",
    "JPN": "Japan",
    "GBR": "United Kingdom",
    "FRA": "France",
    "BRA": "Brazil",
}


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    print("[*] Phase 3 (Keynote): Validating raw inputs before synthesis...")
    noaa, panel = validate_all()

    file_hashes = {p.name: sha256_file(p) for p in sorted(RAW_DIR.iterdir()) if p.is_file()}
    ledger: list[dict[str, Any]] = []
    metrics: dict[str, Any] = {}

    def register(
        metric_id: str,
        value: Any,
        unit: str,
        source_filename: str,
        locator: str,
        quote: str,
    ) -> None:
        if metric_id in metrics:
            raise ValueError(f"Duplicate metric_id: {metric_id}")
        metrics[metric_id] = value
        ledger.append(
            {
                "metric_id": metric_id,
                "value": value,
                "unit": unit,
                "source_document": f"data/raw/{source_filename}",
                "source_locator": locator,
                "exact_extracted_quote": quote,
                "raw_file_sha256": file_hashes[source_filename],
                "parser_script": "scripts/process_data.py",
            }
        )

    # ------------------------------------------------------------------
    # 1. NOAA Atmospheric Physics, Seasonal Breathing & Annual Increments
    # ------------------------------------------------------------------
    first_obs, latest_obs = noaa[0], noaa[-1]
    peak_obs = max(noaa, key=lambda o: o.average_ppm)
    rise_ppm = round(latest_obs.deseasonalized_ppm - first_obs.deseasonalized_ppm, 4)

    register("noaa_first_deseasonalized_ppm", first_obs.deseasonalized_ppm, "ppm", "noaa_co2_mm_mlo.csv", f"row {first_obs.year}-{first_obs.month:02d}", f"{first_obs.year},{first_obs.month},{first_obs.deseasonalized_ppm}")
    register("noaa_latest_average_ppm", latest_obs.average_ppm, "ppm", "noaa_co2_mm_mlo.csv", f"row {latest_obs.year}-{latest_obs.month:02d}", f"{latest_obs.year},{latest_obs.month},{latest_obs.average_ppm}")
    register("noaa_latest_deseasonalized_ppm", latest_obs.deseasonalized_ppm, "ppm", "noaa_co2_mm_mlo.csv", f"row {latest_obs.year}-{latest_obs.month:02d}", f"{latest_obs.year},{latest_obs.month},{latest_obs.deseasonalized_ppm}")
    register("noaa_peak_average_ppm", peak_obs.average_ppm, "ppm", "noaa_co2_mm_mlo.csv", f"row {peak_obs.year}-{peak_obs.month:02d} peak", f"{peak_obs.year},{peak_obs.month},{peak_obs.average_ppm}")
    register("noaa_cumulative_rise_ppm", rise_ppm, "ppm", "noaa_co2_mm_mlo.csv", f"{first_obs.year}-{first_obs.month:02d} -> {latest_obs.year}-{latest_obs.month:02d}", f"{latest_obs.deseasonalized_ppm} - {first_obs.deseasonalized_ppm} = {rise_ppm}")
    register("noaa_observation_count", len(noaa), "months", "noaa_co2_mm_mlo.csv", "complete valid record count", f"count={len(noaa)}")

    by_year: dict[int, list[MaunaLoaObservation]] = {}
    for o in noaa:
        by_year.setdefault(o.year, []).append(o)
    annual_means: dict[int, float] = {
        yr: sum(x.average_ppm for x in obs) / 12.0
        for yr, obs in sorted(by_year.items())
        if len(obs) == 12
    }

    decades = [
        ("1960s", 1960, 1970),
        ("1970s", 1970, 1980),
        ("1980s", 1980, 1990),
        ("1990s", 1990, 2000),
        ("2000s", 2000, 2010),
        ("2010s", 2010, 2020),
        ("2020-25", 2020, 2025),
    ]
    decade_growth = []
    for label, y0, y1 in decades:
        rate = round((annual_means[y1] - annual_means[y0]) / (y1 - y0), 4)
        register(f"noaa_growth_rate_{label.lower().replace('-', '_')}", rate, "ppm/yr", "noaa_co2_mm_mlo.csv", f"annual mean slope {y0}->{y1}", f"({annual_means[y1]:.4f}-{annual_means[y0]:.4f})/{y1-y0}={rate}")
        decade_growth.append({"label": label, "start_year": y0, "end_year": y1, "ppm_per_yr": rate})

    # Annual YoY jumps (1960..2025)
    yoy_years: list[int] = []
    yoy_jumps: list[float] = []
    for yr in sorted(annual_means):
        if (yr - 1) in annual_means:
            yoy_years.append(yr)
            yoy_jumps.append(round(annual_means[yr] - annual_means[yr - 1], 4))

    max_jump_idx = max(range(len(yoy_jumps)), key=lambda i: yoy_jumps[i])
    max_jump_year = yoy_years[max_jump_idx]
    max_jump_ppm = yoy_jumps[max_jump_idx]
    register("noaa_max_annual_jump_ppm", max_jump_ppm, "ppm/yr", "noaa_co2_mm_mlo.csv", f"max YoY annual mean delta (year={max_jump_year})", f"annual[{max_jump_year}] - annual[{max_jump_year-1}] = {max_jump_ppm}")
    register("noaa_max_annual_jump_year", max_jump_year, "year", "noaa_co2_mm_mlo.csv", "calendar year of peak YoY jump", f"year={max_jump_year}, delta={max_jump_ppm}")

    # Seasonal anomaly fingerprint (average - deseasonalized) by calendar month for 3 eras
    def era_seasonal_profile(y_start: int, y_end: int) -> list[float]:
        monthly: dict[int, list[float]] = {m: [] for m in range(1, 13)}
        for o in noaa:
            if y_start <= o.year <= y_end:
                monthly[o.month].append(o.average_ppm - o.deseasonalized_ppm)
        return [round(sum(monthly[m]) / len(monthly[m]), 4) for m in range(1, 13)]

    prof_1960s = era_seasonal_profile(1960, 1969)
    prof_1990s = era_seasonal_profile(1990, 1999)
    prof_2020s = era_seasonal_profile(2020, 2025)

    amp_1960s = round(sum(max(x.average_ppm for x in by_year[y]) - min(x.average_ppm for x in by_year[y]) for y in range(1960, 1970)) / 10.0, 4)
    amp_2020s = round(sum(max(x.average_ppm for x in by_year[y]) - min(x.average_ppm for x in by_year[y]) for y in range(2020, 2026)) / 6.0, 4)
    register("noaa_seasonal_amp_1960s_ppm", amp_1960s, "ppm", "noaa_co2_mm_mlo.csv", "mean peak-to-trough amplitude 1960-1969", f"mean_amp_1960s={amp_1960s}")
    register("noaa_seasonal_amp_2020_25_ppm", amp_2020s, "ppm", "noaa_co2_mm_mlo.csv", "mean peak-to-trough amplitude 2020-2025", f"mean_amp_2020_25={amp_2020s}")

    # ------------------------------------------------------------------
    # 2. World Bank 8-Economy Panel + Population + YoY Momentum Matrix
    # ------------------------------------------------------------------
    panel_idx: dict[tuple[str, int], EconomyYearTelemetry] = {(r.iso3, r.year): r for r in panel}

    with PANEL_CSV.open("w", newline="", encoding="utf-8") as fp:
        w = csv.writer(fp)
        w.writerow(["iso3", "country", "year", "co2_total_mt", "co2_per_capita_t", "gdp_const2015_usd", "population", "renewables_pct", "carbon_intensity_t_per_musd"])
        for r in panel:
            ci = None if (r.co2_total_mt is None or r.gdp_const2015_usd is None) else (r.co2_total_mt * 1e6) / (r.gdp_const2015_usd / 1e6)
            w.writerow([
                r.iso3, SHORT_NAMES[r.iso3], r.year,
                "" if r.co2_total_mt is None else f"{r.co2_total_mt:.4f}",
                "" if r.co2_per_capita_t is None else f"{r.co2_per_capita_t:.6f}",
                "" if r.gdp_const2015_usd is None else f"{r.gdp_const2015_usd:.2f}",
                "" if r.population is None else f"{r.population:.0f}",
                "" if r.renewables_pct is None else f"{r.renewables_pct:.4f}",
                "" if ci is None else f"{ci:.4f}",
            ])

    total_co2_2000 = round(sum(panel_idx[(c, 2000)].co2_total_mt or 0.0 for c in VALID_ISO3), 4)
    total_co2_2024 = round(sum(panel_idx[(c, 2024)].co2_total_mt or 0.0 for c in VALID_ISO3), 4)
    total_co2_chg = round(((total_co2_2024 - total_co2_2000) / total_co2_2000) * 100.0, 4)
    total_pop_2024_m = round(sum((panel_idx[(c, 2024)].population or 0.0) / 1e6 for c in VALID_ISO3), 4)

    oecd5_2000 = round(sum(panel_idx[(c, 2000)].co2_total_mt or 0.0 for c in OECD5), 4)
    oecd5_2024 = round(sum(panel_idx[(c, 2024)].co2_total_mt or 0.0 for c in OECD5), 4)
    oecd5_chg = round(((oecd5_2024 - oecd5_2000) / oecd5_2000) * 100.0, 4)
    oecd5_gdp_chg = round(((sum(panel_idx[(c, 2024)].gdp_const2015_usd or 0.0 for c in OECD5) - sum(panel_idx[(c, 2000)].gdp_const2015_usd or 0.0 for c in OECD5)) / sum(panel_idx[(c, 2000)].gdp_const2015_usd or 0.0 for c in OECD5)) * 100.0, 4)

    em3_2000 = round(sum(panel_idx[(c, 2000)].co2_total_mt or 0.0 for c in EMERGING3), 4)
    em3_2024 = round(sum(panel_idx[(c, 2024)].co2_total_mt or 0.0 for c in EMERGING3), 4)
    em3_chg = round(((em3_2024 - em3_2000) / em3_2000) * 100.0, 4)
    em3_gdp_chg = round(((sum(panel_idx[(c, 2024)].gdp_const2015_usd or 0.0 for c in EMERGING3) - sum(panel_idx[(c, 2000)].gdp_const2015_usd or 0.0 for c in EMERGING3)) / sum(panel_idx[(c, 2000)].gdp_const2015_usd or 0.0 for c in EMERGING3)) * 100.0, 4)

    register("panel8_co2_2000_mt", total_co2_2000, "Mt CO2e", "wb_co2_total_mt.json", "sum 8 economies year=2000", f"sum_2000={total_co2_2000}")
    register("panel8_co2_2024_mt", total_co2_2024, "Mt CO2e", "wb_co2_total_mt.json", "sum 8 economies year=2024", f"sum_2024={total_co2_2024}")
    register("panel8_co2_change_2000_2024_pct", total_co2_chg, "%", "wb_co2_total_mt.json", "pct change 2000->2024", f"({total_co2_2024}-{total_co2_2000})/{total_co2_2000}*100={total_co2_chg}")
    register("panel8_population_2024_m", total_pop_2024_m, "million", "wb_population.json", "sum 8 economies population year=2024", f"pop_2024_m={total_pop_2024_m}")
    register("oecd5_co2_2000_mt", oecd5_2000, "Mt CO2e", "wb_co2_total_mt.json", "sum OECD-5 year=2000", f"oecd5_2000={oecd5_2000}")
    register("oecd5_co2_2024_mt", oecd5_2024, "Mt CO2e", "wb_co2_total_mt.json", "sum OECD-5 year=2024", f"oecd5_2024={oecd5_2024}")
    register("oecd5_co2_change_2000_2024_pct", oecd5_chg, "%", "wb_co2_total_mt.json", "OECD-5 pct change 2000->2024", f"oecd5_chg={oecd5_chg}")
    register("oecd5_gdp_growth_2000_2024_pct", oecd5_gdp_chg, "%", "wb_gdp_const2015.json", "OECD-5 real GDP growth 2000->2024", f"oecd5_gdp_chg={oecd5_gdp_chg}")
    register("em3_co2_2000_mt", em3_2000, "Mt CO2e", "wb_co2_total_mt.json", "sum Emerging-3 year=2000", f"em3_2000={em3_2000}")
    register("em3_co2_2024_mt", em3_2024, "Mt CO2e", "wb_co2_total_mt.json", "sum Emerging-3 year=2024", f"em3_2024={em3_2024}")
    register("em3_co2_change_2000_2024_pct", em3_chg, "%", "wb_co2_total_mt.json", "Emerging-3 pct change 2000->2024", f"em3_chg={em3_chg}")
    register("em3_gdp_growth_2000_2024_pct", em3_gdp_chg, "%", "wb_gdp_const2015.json", "Emerging-3 real GDP growth 2000->2024", f"em3_gdp_chg={em3_gdp_chg}")

    economies_summary: list[dict[str, Any]] = []
    for iso3 in VALID_ISO3:
        r00 = panel_idx[(iso3, 2000)]
        r20 = panel_idx[(iso3, 2020)]
        r19 = panel_idx[(iso3, 2019)]
        r21 = panel_idx[(iso3, 2021)]
        r24 = panel_idx[(iso3, 2024)]
        r25 = panel_idx[(iso3, 2025)]

        assert r00.co2_total_mt and r24.co2_total_mt and r00.gdp_const2015_usd and r24.gdp_const2015_usd
        assert r00.co2_per_capita_t and r24.co2_per_capita_t and r24.population
        assert r00.renewables_pct is not None and r21.renewables_pct is not None
        assert r19.co2_total_mt and r20.co2_total_mt

        co2_00 = round(r00.co2_total_mt, 4)
        co2_24 = round(r24.co2_total_mt, 4)
        co2_chg = round(((co2_24 - co2_00) / co2_00) * 100.0, 4)
        pc_00 = round(r00.co2_per_capita_t, 4)
        pc_24 = round(r24.co2_per_capita_t, 4)
        pc_chg = round(((pc_24 - pc_00) / pc_00) * 100.0, 4)
        pop_24_m = round(r24.population / 1e6, 4)
        gdp_chg = round(((r24.gdp_const2015_usd - r00.gdp_const2015_usd) / r00.gdp_const2015_usd) * 100.0, 4)
        ci_00 = round((r00.co2_total_mt * 1e6) / (r00.gdp_const2015_usd / 1e6), 4)
        ci_24 = round((r24.co2_total_mt * 1e6) / (r24.gdp_const2015_usd / 1e6), 4)
        ci_chg = round(((ci_24 - ci_00) / ci_00) * 100.0, 4)
        ren_00 = round(r00.renewables_pct, 4)
        ren_21 = round(r21.renewables_pct, 4)
        share_24 = round((co2_24 / total_co2_2024) * 100.0, 4)
        covid_yoy_2020 = round(((r20.co2_total_mt - r19.co2_total_mt) / r19.co2_total_mt) * 100.0, 4)

        k = iso3.lower()
        register(f"{k}_co2_2000_mt", co2_00, "Mt CO2e", "wb_co2_total_mt.json", f"{iso3} year=2000", f"{iso3} 2000={r00.co2_total_mt}")
        register(f"{k}_co2_2024_mt", co2_24, "Mt CO2e", "wb_co2_total_mt.json", f"{iso3} year=2024", f"{iso3} 2024={r24.co2_total_mt}")
        register(f"{k}_co2_2025_mt", r25.co2_total_mt, "Mt CO2e", "wb_co2_total_mt.json", f"{iso3} year=2025", f"{iso3} 2025={r25.co2_total_mt} (null)")
        register(f"{k}_co2_change_pct", co2_chg, "%", "wb_co2_total_mt.json", f"{iso3} 2000->2024 delta", f"({co2_24}-{co2_00})/{co2_00}*100={co2_chg}")
        register(f"{k}_co2_per_capita_2000_t", pc_00, "t CO2e/capita", "wb_co2_per_capita.json", f"{iso3} year=2000", f"{iso3} 2000={r00.co2_per_capita_t}")
        register(f"{k}_co2_per_capita_2024_t", pc_24, "t CO2e/capita", "wb_co2_per_capita.json", f"{iso3} year=2024", f"{iso3} 2024={r24.co2_per_capita_t}")
        register(f"{k}_co2_per_capita_change_pct", pc_chg, "%", "wb_co2_per_capita.json", f"{iso3} per-capita pct change 2000->2024", f"({pc_24}-{pc_00})/{pc_00}*100={pc_chg}")
        register(f"{k}_population_2024_m", pop_24_m, "million", "wb_population.json", f"{iso3} year=2024", f"{iso3} 2024 pop={r24.population}")
        register(f"{k}_gdp_growth_2000_2024_pct", gdp_chg, "%", "wb_gdp_const2015.json", f"{iso3} real GDP growth 2000->2024", f"{iso3} gdp_chg={gdp_chg}")
        register(f"{k}_carbon_intensity_2000", ci_00, "t CO2e/$1M", "wb_co2_total_mt.json", f"{iso3} year=2000 CO2/GDP", f"{iso3} ci_2000={ci_00}")
        register(f"{k}_carbon_intensity_2024", ci_24, "t CO2e/$1M", "wb_co2_total_mt.json", f"{iso3} year=2024 CO2/GDP", f"{iso3} ci_2024={ci_24}")
        register(f"{k}_carbon_intensity_change_pct", ci_chg, "%", "wb_co2_total_mt.json", f"{iso3} CI pct change 2000->2024", f"{iso3} ci_chg={ci_chg}")
        register(f"{k}_renewables_2000_pct", ren_00, "%", "wb_renewables_share.json", f"{iso3} year=2000", f"{iso3} ren_2000={r00.renewables_pct}")
        register(f"{k}_renewables_2021_pct", ren_21, "%", "wb_renewables_share.json", f"{iso3} year=2021", f"{iso3} ren_2021={r21.renewables_pct}")
        register(f"{k}_renewables_2024_pct", r24.renewables_pct, "%", "wb_renewables_share.json", f"{iso3} year=2024", f"{iso3} ren_2024={r24.renewables_pct} (null)")
        register(f"{k}_panel8_share_2024_pct", share_24, "%", "wb_co2_total_mt.json", f"{iso3} 2024 share of panel", f"{co2_24}/{total_co2_2024}*100={share_24}")
        register(f"{k}_covid_2020_yoy_pct", covid_yoy_2020, "%", "wb_co2_total_mt.json", f"{iso3} 2019->2020 YoY CO2 delta", f"({r20.co2_total_mt}-{r19.co2_total_mt})/{r19.co2_total_mt}*100={covid_yoy_2020}")

        co2_series = [round(panel_idx[(iso3, y)].co2_total_mt or 0.0, 2) for y in range(2000, 2025)]
        gdp_series = [panel_idx[(iso3, y)].gdp_const2015_usd or 0.0 for y in range(2000, 2025)]
        co2_indexed = [round((v / co2_series[0]) * 100.0, 2) for v in co2_series]
        gdp_indexed = [round((v / gdp_series[0]) * 100.0, 2) for v in gdp_series]
        yoy_series = [
            round(((co2_series[i] - co2_series[i - 1]) / co2_series[i - 1]) * 100.0, 2)
            for i in range(1, len(co2_series))
        ]

        economies_summary.append(
            {
                "iso3": iso3,
                "name": SHORT_NAMES[iso3],
                "bloc": "OECD-5" if iso3 in OECD5 else "Emerging-3",
                "co2_2000_mt": co2_00,
                "co2_2024_mt": co2_24,
                "co2_2025_mt": r25.co2_total_mt,
                "co2_change_pct": co2_chg,
                "co2_per_capita_2000_t": pc_00,
                "co2_per_capita_2024_t": pc_24,
                "co2_per_capita_change_pct": pc_chg,
                "population_2024_m": pop_24_m,
                "gdp_growth_2000_2024_pct": gdp_chg,
                "carbon_intensity_2000": ci_00,
                "carbon_intensity_2024": ci_24,
                "carbon_intensity_change_pct": ci_chg,
                "renewables_2000_pct": ren_00,
                "renewables_2021_pct": ren_21,
                "renewables_2024_pct": r24.renewables_pct,
                "panel8_share_2024_pct": share_24,
                "covid_2020_yoy_pct": covid_yoy_2020,
                "co2_series_2000_2024": co2_series,
                "co2_indexed_2000_2024": co2_indexed,
                "gdp_indexed_2000_2024": gdp_indexed,
                "yoy_pct_2001_2024": yoy_series,
            }
        )

    economies_summary.sort(key=lambda e: e["co2_2024_mt"], reverse=True)

    summary = {
        "metadata": {
            "noaa_start": f"{first_obs.year}-{first_obs.month:02d}",
            "noaa_end": f"{latest_obs.year}-{latest_obs.month:02d}",
            "noaa_peak_month": f"{peak_obs.year}-{peak_obs.month:02d}",
            "wb_co2_years": "2000-2024 (2025 unreported)",
            "wb_gdp_years": "2000-2025",
            "wb_renewables_years": "2000-2021 (2022-2025 unreported)",
            "raw_file_hashes": file_hashes,
        },
        "metrics": metrics,
        "noaa_series": {
            "decimal_dates": [o.decimal_date for o in noaa],
            "average_ppm": [o.average_ppm for o in noaa],
            "deseasonalized_ppm": [o.deseasonalized_ppm for o in noaa],
            "decadal_growth": decade_growth,
            "yoy_years": yoy_years,
            "yoy_jumps_ppm": yoy_jumps,
            "seasonal_profiles": {
                "1960s": prof_1960s,
                "1990s": prof_1990s,
                "2020-25": prof_2020s,
            },
        },
        "panel_years": list(range(2000, 2025)),
        "yoy_years": list(range(2001, 2025)),
        "economies": economies_summary,
    }

    LEDGER_PATH.write_text(json.dumps(ledger, indent=2) + "\n", encoding="utf-8")
    SUMMARY_PATH.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(f"[OK] Registered {len(ledger)} atomic provenance tuples in {LEDGER_PATH}")
    print(f"[OK] Wrote extended keynote summary metrics to {SUMMARY_PATH}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
