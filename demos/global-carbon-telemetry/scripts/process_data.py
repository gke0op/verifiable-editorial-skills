#!/usr/bin/env python3
"""
Phase 3: Synthesis & Atomic Provenance Registration.

Transforms validated raw datasets into:
  - data/processed_panel.csv      (clean 8-economy 2000-2025 panel)
  - data/provenance_ledger.json   (atomic provenance tuple for every scalar metric)
  - data/summary_metrics.json     (audited aggregates + chart series)
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
    print("[*] Phase 3: Validating raw inputs before synthesis...")
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
            raise ValueError(f"Duplicate metric_id registration: {metric_id}")
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
    # 1. NOAA Mauna Loa Atmospheric CO2 Telemetry
    # ------------------------------------------------------------------
    first_obs = noaa[0]
    latest_obs = noaa[-1]
    peak_obs = max(noaa, key=lambda o: o.average_ppm)
    rise_ppm = round(latest_obs.deseasonalized_ppm - first_obs.deseasonalized_ppm, 4)

    register(
        "noaa_first_deseasonalized_ppm",
        first_obs.deseasonalized_ppm,
        "ppm",
        "noaa_co2_mm_mlo.csv",
        f"row {first_obs.year}-{first_obs.month:02d} (deseasonalized)",
        f"{first_obs.year},{first_obs.month},{first_obs.decimal_date},{first_obs.average_ppm},{first_obs.deseasonalized_ppm}",
    )
    register(
        "noaa_latest_average_ppm",
        latest_obs.average_ppm,
        "ppm",
        "noaa_co2_mm_mlo.csv",
        f"row {latest_obs.year}-{latest_obs.month:02d} (average)",
        f"{latest_obs.year},{latest_obs.month},{latest_obs.decimal_date},{latest_obs.average_ppm},{latest_obs.deseasonalized_ppm}",
    )
    register(
        "noaa_latest_deseasonalized_ppm",
        latest_obs.deseasonalized_ppm,
        "ppm",
        "noaa_co2_mm_mlo.csv",
        f"row {latest_obs.year}-{latest_obs.month:02d} (deseasonalized)",
        f"{latest_obs.year},{latest_obs.month},{latest_obs.decimal_date},{latest_obs.average_ppm},{latest_obs.deseasonalized_ppm}",
    )
    register(
        "noaa_peak_average_ppm",
        peak_obs.average_ppm,
        "ppm",
        "noaa_co2_mm_mlo.csv",
        f"row {peak_obs.year}-{peak_obs.month:02d} (all-time monthly mean peak)",
        f"{peak_obs.year},{peak_obs.month},{peak_obs.decimal_date},{peak_obs.average_ppm},{peak_obs.deseasonalized_ppm}",
    )
    register(
        "noaa_cumulative_rise_ppm",
        rise_ppm,
        "ppm",
        "noaa_co2_mm_mlo.csv",
        f"deseasonalized delta {first_obs.year}-{first_obs.month:02d} -> {latest_obs.year}-{latest_obs.month:02d}",
        f"{latest_obs.deseasonalized_ppm} - {first_obs.deseasonalized_ppm} = {rise_ppm}",
    )
    register(
        "noaa_observation_count",
        len(noaa),
        "months",
        "noaa_co2_mm_mlo.csv",
        f"all valid rows {first_obs.year}-{first_obs.month:02d}..{latest_obs.year}-{latest_obs.month:02d}",
        f"count={len(noaa)} monthly records",
    )

    # Full-year annual means (only years with all 12 months)
    by_year: dict[int, list[MaunaLoaObservation]] = {}
    for o in noaa:
        by_year.setdefault(o.year, []).append(o)
    annual_means: dict[int, float] = {
        yr: sum(x.average_ppm for x in obs) / len(obs)
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
    decade_growth: list[dict[str, Any]] = []
    for label, y0, y1 in decades:
        rate = round((annual_means[y1] - annual_means[y0]) / (y1 - y0), 4)
        mid = f"noaa_growth_rate_{label.lower().replace('-', '_')}"
        register(
            mid,
            rate,
            "ppm/yr",
            "noaa_co2_mm_mlo.csv",
            f"annual mean slope {y0} ({annual_means[y0]:.2f}) -> {y1} ({annual_means[y1]:.2f})",
            f"({annual_means[y1]:.4f} - {annual_means[y0]:.4f}) / {y1 - y0} = {rate}",
        )
        decade_growth.append({"label": label, "start_year": y0, "end_year": y1, "ppm_per_yr": rate})

    # Recent seasonal amplitude (average over last 5 complete years: 2021-2025)
    recent_amps = [
        max(x.average_ppm for x in by_year[yr]) - min(x.average_ppm for x in by_year[yr])
        for yr in range(2021, 2026)
    ]
    avg_seasonal_amp = round(sum(recent_amps) / len(recent_amps), 4)
    register(
        "noaa_recent_seasonal_amplitude_ppm",
        avg_seasonal_amp,
        "ppm",
        "noaa_co2_mm_mlo.csv",
        "mean annual (max - min) monthly ppm across complete years 2021-2025",
        f"2021-2025 yearly amplitudes={[round(a, 2) for a in recent_amps]}, mean={avg_seasonal_amp}",
    )

    # ------------------------------------------------------------------
    # 2. World Bank 8-Economy Decarbonization & Decoupling Panel
    # ------------------------------------------------------------------
    panel_idx: dict[tuple[str, int], EconomyYearTelemetry] = {
        (r.iso3, r.year): r for r in panel
    }

    # Write clean processed panel CSV
    with PANEL_CSV.open("w", newline="", encoding="utf-8") as fp:
        writer = csv.writer(fp)
        writer.writerow(
            [
                "iso3",
                "country",
                "year",
                "co2_total_mt",
                "co2_per_capita_t",
                "gdp_const2015_usd",
                "population",
                "renewables_pct",
                "carbon_intensity_t_per_musd",
            ]
        )
        for r in panel:
            ci: Optional[float] = None
            if r.co2_total_mt is not None and r.gdp_const2015_usd is not None:
                ci = (r.co2_total_mt * 1e6) / (r.gdp_const2015_usd / 1e6)
            writer.writerow(
                [
                    r.iso3,
                    SHORT_NAMES[r.iso3],
                    r.year,
                    "" if r.co2_total_mt is None else f"{r.co2_total_mt:.4f}",
                    "" if r.co2_per_capita_t is None else f"{r.co2_per_capita_t:.6f}",
                    "" if r.gdp_const2015_usd is None else f"{r.gdp_const2015_usd:.2f}",
                    "" if r.population is None else f"{r.population:.0f}",
                    "" if r.renewables_pct is None else f"{r.renewables_pct:.4f}",
                    "" if ci is None else f"{ci:.4f}",
                ]
            )

    # Panel totals (2000 vs 2024)
    total_co2_2000 = round(sum(panel_idx[(c, 2000)].co2_total_mt or 0.0 for c in VALID_ISO3), 4)
    total_co2_2024 = round(sum(panel_idx[(c, 2024)].co2_total_mt or 0.0 for c in VALID_ISO3), 4)
    total_co2_change_pct = round(((total_co2_2024 - total_co2_2000) / total_co2_2000) * 100.0, 4)

    oecd5_2000 = round(sum(panel_idx[(c, 2000)].co2_total_mt or 0.0 for c in OECD5), 4)
    oecd5_2024 = round(sum(panel_idx[(c, 2024)].co2_total_mt or 0.0 for c in OECD5), 4)
    oecd5_change_pct = round(((oecd5_2024 - oecd5_2000) / oecd5_2000) * 100.0, 4)

    em3_2000 = round(sum(panel_idx[(c, 2000)].co2_total_mt or 0.0 for c in EMERGING3), 4)
    em3_2024 = round(sum(panel_idx[(c, 2024)].co2_total_mt or 0.0 for c in EMERGING3), 4)
    em3_change_pct = round(((em3_2024 - em3_2000) / em3_2000) * 100.0, 4)

    oecd5_gdp_2000 = sum(panel_idx[(c, 2000)].gdp_const2015_usd or 0.0 for c in OECD5)
    oecd5_gdp_2024 = sum(panel_idx[(c, 2024)].gdp_const2015_usd or 0.0 for c in OECD5)
    oecd5_gdp_growth_pct = round(((oecd5_gdp_2024 - oecd5_gdp_2000) / oecd5_gdp_2000) * 100.0, 4)

    em3_gdp_2000 = sum(panel_idx[(c, 2000)].gdp_const2015_usd or 0.0 for c in EMERGING3)
    em3_gdp_2024 = sum(panel_idx[(c, 2024)].gdp_const2015_usd or 0.0 for c in EMERGING3)
    em3_gdp_growth_pct = round(((em3_gdp_2024 - em3_gdp_2000) / em3_gdp_2000) * 100.0, 4)

    register(
        "panel8_co2_2000_mt",
        total_co2_2000,
        "Mt CO2e",
        "wb_co2_total_mt.json",
        "sum(EN.GHG.CO2.MT.CE.AR5, 8 economies, year=2000)",
        f"sum_2000={total_co2_2000} Mt CO2e",
    )
    register(
        "panel8_co2_2024_mt",
        total_co2_2024,
        "Mt CO2e",
        "wb_co2_total_mt.json",
        "sum(EN.GHG.CO2.MT.CE.AR5, 8 economies, year=2024)",
        f"sum_2024={total_co2_2024} Mt CO2e",
    )
    register(
        "panel8_co2_change_2000_2024_pct",
        total_co2_change_pct,
        "%",
        "wb_co2_total_mt.json",
        "pct change of 8-economy CO2 total 2000 -> 2024",
        f"({total_co2_2024} - {total_co2_2000}) / {total_co2_2000} * 100 = {total_co2_change_pct}%",
    )
    register(
        "oecd5_co2_2000_mt",
        oecd5_2000,
        "Mt CO2e",
        "wb_co2_total_mt.json",
        "sum(USA,DEU,JPN,GBR,FRA, year=2000)",
        f"oecd5_2000={oecd5_2000} Mt CO2e",
    )
    register(
        "oecd5_co2_2024_mt",
        oecd5_2024,
        "Mt CO2e",
        "wb_co2_total_mt.json",
        "sum(USA,DEU,JPN,GBR,FRA, year=2024)",
        f"oecd5_2024={oecd5_2024} Mt CO2e",
    )
    register(
        "oecd5_co2_change_2000_2024_pct",
        oecd5_change_pct,
        "%",
        "wb_co2_total_mt.json",
        "OECD-5 CO2 pct change 2000 -> 2024",
        f"({oecd5_2024} - {oecd5_2000}) / {oecd5_2000} * 100 = {oecd5_change_pct}%",
    )
    register(
        "oecd5_gdp_growth_2000_2024_pct",
        oecd5_gdp_growth_pct,
        "%",
        "wb_gdp_const2015.json",
        "OECD-5 constant-2015 GDP pct change 2000 -> 2024",
        f"({oecd5_gdp_2024:.2f} - {oecd5_gdp_2000:.2f}) / {oecd5_gdp_2000:.2f} * 100 = {oecd5_gdp_growth_pct}%",
    )
    register(
        "em3_co2_2000_mt",
        em3_2000,
        "Mt CO2e",
        "wb_co2_total_mt.json",
        "sum(CHN,IND,BRA, year=2000)",
        f"em3_2000={em3_2000} Mt CO2e",
    )
    register(
        "em3_co2_2024_mt",
        em3_2024,
        "Mt CO2e",
        "wb_co2_total_mt.json",
        "sum(CHN,IND,BRA, year=2024)",
        f"em3_2024={em3_2024} Mt CO2e",
    )
    register(
        "em3_co2_change_2000_2024_pct",
        em3_change_pct,
        "%",
        "wb_co2_total_mt.json",
        "Emerging-3 (CHN,IND,BRA) CO2 pct change 2000 -> 2024",
        f"({em3_2024} - {em3_2000}) / {em3_2000} * 100 = {em3_change_pct}%",
    )
    register(
        "em3_gdp_growth_2000_2024_pct",
        em3_gdp_growth_pct,
        "%",
        "wb_gdp_const2015.json",
        "Emerging-3 constant-2015 GDP pct change 2000 -> 2024",
        f"({em3_gdp_2024:.2f} - {em3_gdp_2000:.2f}) / {em3_gdp_2000:.2f} * 100 = {em3_gdp_growth_pct}%",
    )

    # Per-economy records
    economies_summary: list[dict[str, Any]] = []
    for iso3 in VALID_ISO3:
        r00 = panel_idx[(iso3, 2000)]
        r21 = panel_idx[(iso3, 2021)]
        r24 = panel_idx[(iso3, 2024)]
        r25 = panel_idx[(iso3, 2025)]

        assert r00.co2_total_mt is not None and r24.co2_total_mt is not None
        assert r00.gdp_const2015_usd is not None and r24.gdp_const2015_usd is not None
        assert r24.co2_per_capita_t is not None and r21.renewables_pct is not None and r00.renewables_pct is not None

        co2_00 = round(r00.co2_total_mt, 4)
        co2_24 = round(r24.co2_total_mt, 4)
        co2_chg = round(((co2_24 - co2_00) / co2_00) * 100.0, 4)
        pc_24 = round(r24.co2_per_capita_t, 4)
        gdp_chg = round(((r24.gdp_const2015_usd - r00.gdp_const2015_usd) / r00.gdp_const2015_usd) * 100.0, 4)
        ci_00 = round((r00.co2_total_mt * 1e6) / (r00.gdp_const2015_usd / 1e6), 4)
        ci_24 = round((r24.co2_total_mt * 1e6) / (r24.gdp_const2015_usd / 1e6), 4)
        ci_chg = round(((ci_24 - ci_00) / ci_00) * 100.0, 4)
        ren_00 = round(r00.renewables_pct, 4)
        ren_21 = round(r21.renewables_pct, 4)
        share_24 = round((co2_24 / total_co2_2024) * 100.0, 4)

        k = iso3.lower()
        register(f"{k}_co2_2000_mt", co2_00, "Mt CO2e", "wb_co2_total_mt.json", f"{iso3} year=2000", f"{iso3} 2000 value={r00.co2_total_mt}")
        register(f"{k}_co2_2024_mt", co2_24, "Mt CO2e", "wb_co2_total_mt.json", f"{iso3} year=2024", f"{iso3} 2024 value={r24.co2_total_mt}")
        register(f"{k}_co2_2025_mt", r25.co2_total_mt, "Mt CO2e", "wb_co2_total_mt.json", f"{iso3} year=2025", f"{iso3} 2025 value={r25.co2_total_mt} (unreported in WDI)")
        register(f"{k}_co2_change_pct", co2_chg, "%", "wb_co2_total_mt.json", f"{iso3} pct change 2000->2024", f"({co2_24} - {co2_00}) / {co2_00} * 100 = {co2_chg}%")
        register(f"{k}_co2_per_capita_2024_t", pc_24, "t CO2e/capita", "wb_co2_per_capita.json", f"{iso3} year=2024", f"{iso3} 2024 value={r24.co2_per_capita_t}")
        register(f"{k}_gdp_growth_2000_2024_pct", gdp_chg, "%", "wb_gdp_const2015.json", f"{iso3} constant-2015 GDP growth 2000->2024", f"({r24.gdp_const2015_usd:.2f} - {r00.gdp_const2015_usd:.2f}) / {r00.gdp_const2015_usd:.2f} * 100 = {gdp_chg}%")
        register(f"{k}_carbon_intensity_2000", ci_00, "t CO2e / $1M const-2015 USD", "wb_co2_total_mt.json", f"{iso3} year=2000 CO2/GDP", f"co2={r00.co2_total_mt} Mt, gdp={r00.gdp_const2015_usd:.2f} USD -> {ci_00}")
        register(f"{k}_carbon_intensity_2024", ci_24, "t CO2e / $1M const-2015 USD", "wb_co2_total_mt.json", f"{iso3} year=2024 CO2/GDP", f"co2={r24.co2_total_mt} Mt, gdp={r24.gdp_const2015_usd:.2f} USD -> {ci_24}")
        register(f"{k}_carbon_intensity_change_pct", ci_chg, "%", "wb_co2_total_mt.json", f"{iso3} carbon intensity change 2000->2024", f"({ci_24} - {ci_00}) / {ci_00} * 100 = {ci_chg}%")
        register(f"{k}_renewables_2000_pct", ren_00, "%", "wb_renewables_share.json", f"{iso3} year=2000", f"{iso3} 2000 value={r00.renewables_pct}")
        register(f"{k}_renewables_2021_pct", ren_21, "%", "wb_renewables_share.json", f"{iso3} year=2021", f"{iso3} 2021 value={r21.renewables_pct}")
        register(f"{k}_renewables_2024_pct", r24.renewables_pct, "%", "wb_renewables_share.json", f"{iso3} year=2024", f"{iso3} 2024 value={r24.renewables_pct} (unreported in WDI)")
        register(f"{k}_panel8_share_2024_pct", share_24, "%", "wb_co2_total_mt.json", f"{iso3} 2024 share of 8-economy CO2", f"{co2_24} / {total_co2_2024} * 100 = {share_24}%")

        co2_series = [round(panel_idx[(iso3, y)].co2_total_mt or 0.0, 2) for y in range(2000, 2025)]
        ci_series = [
            round(
                ((panel_idx[(iso3, y)].co2_total_mt or 0.0) * 1e6)
                / ((panel_idx[(iso3, y)].gdp_const2015_usd or 1.0) / 1e6),
                2,
            )
            for y in range(2000, 2025)
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
                "co2_per_capita_2024_t": pc_24,
                "gdp_growth_2000_2024_pct": gdp_chg,
                "carbon_intensity_2000": ci_00,
                "carbon_intensity_2024": ci_24,
                "carbon_intensity_change_pct": ci_chg,
                "renewables_2000_pct": ren_00,
                "renewables_2021_pct": ren_21,
                "renewables_2024_pct": r24.renewables_pct,
                "panel8_share_2024_pct": share_24,
                "co2_series_2000_2024": co2_series,
                "ci_series_2000_2024": ci_series,
            }
        )

    # Sort economies descending by 2024 CO2 total for clean visual tables
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
        },
        "panel_years": list(range(2000, 2025)),
        "economies": economies_summary,
    }

    LEDGER_PATH.write_text(json.dumps(ledger, indent=2) + "\n", encoding="utf-8")
    SUMMARY_PATH.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(f"[OK] Registered {len(ledger)} atomic provenance tuples in {LEDGER_PATH}")
    print(f"[OK] Wrote audited summary metrics to {SUMMARY_PATH}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
