#!/usr/bin/env python3
"""
Phase 2: Reality & Invariant Compiler (Domain Bounds + Accounting Identities).

Parses raw files directly from data/raw/ and enforces physical, temporal, and
accounting invariants via Pydantic v2. Fails closed (exit code 1) on any breach.
"""
from __future__ import annotations

import csv
import json
import sys
from pathlib import Path
from typing import Literal, Optional

from pydantic import BaseModel, Field, model_validator

BASE_DIR = Path(__file__).resolve().parent.parent
RAW_DIR = BASE_DIR / "data" / "raw"

VALID_ISO3 = ("USA", "CHN", "DEU", "IND", "JPN", "GBR", "FRA", "BRA")


class MaunaLoaObservation(BaseModel):
    """Physical domain model for NOAA GML Mauna Loa monthly mean CO2."""

    year: int = Field(..., ge=1958, le=2030)
    month: int = Field(..., ge=1, le=12)
    decimal_date: float = Field(..., ge=1958.0, le=2031.0)
    average_ppm: float = Field(..., ge=300.0, le=460.0)
    deseasonalized_ppm: float = Field(..., ge=300.0, le=460.0)
    ndays: Optional[int] = Field(None, ge=0, le=31)
    sdev: Optional[float] = Field(None, ge=0.0, le=20.0)
    unc: Optional[float] = Field(None, ge=0.0, le=10.0)

    @model_validator(mode="after")
    def check_seasonal_physics(self) -> "MaunaLoaObservation":
        # Mauna Loa seasonal cycle peak-to-trough is ~6-7 ppm; deviation > 12 ppm
        # indicates corrupted parsing or unit mismatch.
        if abs(self.average_ppm - self.deseasonalized_ppm) > 12.0:
            raise ValueError(
                f"FATAL PHYSICS VIOLATION ({self.year}-{self.month:02d}): "
                f"|average ({self.average_ppm}) - deseasonalized ({self.deseasonalized_ppm})| > 12 ppm"
            )
        return self


class EconomyYearTelemetry(BaseModel):
    """Economic & emissions domain model for a single country-year row."""

    iso3: Literal["USA", "CHN", "DEU", "IND", "JPN", "GBR", "FRA", "BRA"]
    country_name: str = Field(..., min_length=2)
    year: int = Field(..., ge=2000, le=2025)
    co2_total_mt: Optional[float] = Field(None, ge=10.0, le=25000.0)
    co2_per_capita_t: Optional[float] = Field(None, ge=0.1, le=40.0)
    gdp_const2015_usd: Optional[float] = Field(None, ge=1e11, le=5e13)
    population: Optional[float] = Field(None, ge=1e7, le=2e9)
    renewables_pct: Optional[float] = Field(None, ge=0.0, le=100.0)

    @model_validator(mode="after")
    def check_accounting_identities(self) -> "EconomyYearTelemetry":
        # Identity 1: Total CO2 (Mt) * 1e6 / Population == Per-Capita CO2 (t/capita)
        if (
            self.co2_total_mt is not None
            and self.co2_per_capita_t is not None
            and self.population is not None
        ):
            recomputed = (self.co2_total_mt * 1e6) / self.population
            rel_err = abs(recomputed - self.co2_per_capita_t) / self.co2_per_capita_t
            if rel_err > 1e-6:
                raise ValueError(
                    f"FATAL ACCOUNTING BREACH ({self.iso3} {self.year}): "
                    f"CO2_total/pop={recomputed:.6f} != CO2_per_capita={self.co2_per_capita_t:.6f} "
                    f"(rel_err={rel_err:.2e})"
                )

        # Identity 2: Carbon intensity of constant-2015 GDP must be physically plausible
        if self.co2_total_mt is not None and self.gdp_const2015_usd is not None:
            intensity_t_per_musd = (self.co2_total_mt * 1e6) / (
                self.gdp_const2015_usd / 1e6
            )
            if not (20.0 <= intensity_t_per_musd <= 5000.0):
                raise ValueError(
                    f"FATAL ECONOMIC BOUND ({self.iso3} {self.year}): "
                    f"carbon intensity {intensity_t_per_musd:.2f} t CO2e/$1M GDP out of bounds [20, 5000]"
                )
        return self


def parse_noaa_raw(path: Path) -> list[MaunaLoaObservation]:
    if not path.exists():
        raise FileNotFoundError(f"Missing raw NOAA dataset: {path}")

    lines = [
        ln
        for ln in path.read_text(encoding="utf-8").splitlines()
        if ln.strip() and not ln.lstrip().startswith("#")
    ]
    reader = csv.DictReader(lines)
    observations: list[MaunaLoaObservation] = []

    for row in reader:
        ndays_raw = int(row["ndays"])
        sdev_raw = float(row["sdev"])
        unc_raw = float(row["unc"])
        obs = MaunaLoaObservation(
            year=int(row["year"]),
            month=int(row["month"]),
            decimal_date=float(row["decimal date"]),
            average_ppm=float(row["average"]),
            deseasonalized_ppm=float(row["deseasonalized"]),
            ndays=None if ndays_raw < 0 else ndays_raw,
            sdev=None if sdev_raw < 0 else sdev_raw,
            unc=None if unc_raw < 0 else unc_raw,
        )
        observations.append(obs)

    if len(observations) < 700:
        raise ValueError(f"Expected >= 700 NOAA monthly rows, got {len(observations)}")

    # Check chronological monotonicity
    for prev, curr in zip(observations, observations[1:]):
        if curr.decimal_date <= prev.decimal_date:
            raise ValueError(
                f"Non-monotonic NOAA date sequence: {prev.year}-{prev.month} -> {curr.year}-{curr.month}"
            )
    return observations


def _load_wb_series(filename: str) -> tuple[dict[tuple[str, int], Optional[float]], dict[str, str]]:
    path = RAW_DIR / filename
    if not path.exists():
        raise FileNotFoundError(f"Missing raw World Bank file: {path}")
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, list) or len(payload) < 2 or not isinstance(payload[1], list):
        raise ValueError(f"Unexpected World Bank JSON envelope in {filename}")

    values: dict[tuple[str, int], Optional[float]] = {}
    names: dict[str, str] = {}
    for item in payload[1]:
        iso3 = item["countryiso3code"]
        year = int(item["date"])
        val = item["value"]
        values[(iso3, year)] = None if val is None else float(val)
        names[iso3] = item["country"]["value"]
    return values, names


def parse_wb_panel() -> list[EconomyYearTelemetry]:
    co2_tot, names = _load_wb_series("wb_co2_total_mt.json")
    co2_pc, _ = _load_wb_series("wb_co2_per_capita.json")
    gdp, _ = _load_wb_series("wb_gdp_const2015.json")
    pop, _ = _load_wb_series("wb_population.json")
    ren, _ = _load_wb_series("wb_renewables_share.json")

    panel: list[EconomyYearTelemetry] = []
    for iso3 in VALID_ISO3:
        for year in range(2000, 2026):
            row = EconomyYearTelemetry(
                iso3=iso3,
                country_name=names[iso3],
                year=year,
                co2_total_mt=co2_tot.get((iso3, year)),
                co2_per_capita_t=co2_pc.get((iso3, year)),
                gdp_const2015_usd=gdp.get((iso3, year)),
                population=pop.get((iso3, year)),
                renewables_pct=ren.get((iso3, year)),
            )
            panel.append(row)
    return panel


def validate_all() -> tuple[list[MaunaLoaObservation], list[EconomyYearTelemetry]]:
    noaa = parse_noaa_raw(RAW_DIR / "noaa_co2_mm_mlo.csv")
    panel = parse_wb_panel()
    return noaa, panel


def main() -> int:
    print("[*] Running Phase 2 Reality & Invariant Compiler...")
    try:
        noaa, panel = validate_all()
    except Exception as exc:
        print(f"[!] REALITY INVARIANT BREACH: {exc}", file=sys.stderr)
        return 1

    print(
        f"[OK] Validated {len(noaa)} NOAA monthly observations "
        f"({noaa[0].year}-{noaa[0].month:02d} to {noaa[-1].year}-{noaa[-1].month:02d})"
    )
    print(
        f"[OK] Validated {len(panel)} World Bank economy-year records "
        f"(8 economies x 26 years, 100% identity checks passed)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
