#!/usr/bin/env python3
"""
Phase 1: Deterministic Open-Data Ingestion & Cryptographic Sealing.

Streams raw public datasets from NOAA Global Monitoring Laboratory and the
World Bank Open Data REST API v2 into immutable files under data/raw/, then
writes a deduplicated, sorted SHA-256 manifest at data/manifest.sha256.
"""
from __future__ import annotations

import hashlib
import json
import os
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
RAW_DIR = BASE_DIR / "data" / "raw"
MANIFEST_PATH = BASE_DIR / "data" / "manifest.sha256"
SOURCE_META_PATH = BASE_DIR / "data" / "source_urls.json"

COUNTRIES = "USA;CHN;DEU;IND;JPN;GBR;FRA;BRA"

SOURCES: list[tuple[str, str, str]] = [
    (
        "noaa_co2_mm_mlo.csv",
        "https://gml.noaa.gov/webdata/ccgg/trends/co2/co2_mm_mlo.csv",
        "NOAA Global Monitoring Laboratory — Mauna Loa Monthly Mean CO2 (ppm)",
    ),
    (
        "wb_co2_total_mt.json",
        f"https://api.worldbank.org/v2/country/{COUNTRIES}/indicator/EN.GHG.CO2.MT.CE.AR5?format=json&per_page=500&date=2000:2025",
        "World Bank WDI (EDGAR/AR5) — Total CO2 Emissions excl. LULUCF (Mt CO2e)",
    ),
    (
        "wb_co2_per_capita.json",
        f"https://api.worldbank.org/v2/country/{COUNTRIES}/indicator/EN.GHG.CO2.PC.CE.AR5?format=json&per_page=500&date=2000:2025",
        "World Bank WDI (EDGAR/AR5) — CO2 Emissions per Capita excl. LULUCF (t CO2e/capita)",
    ),
    (
        "wb_gdp_const2015.json",
        f"https://api.worldbank.org/v2/country/{COUNTRIES}/indicator/NY.GDP.MKTP.KD?format=json&per_page=500&date=2000:2025",
        "World Bank WDI — GDP in Constant 2015 US$",
    ),
    (
        "wb_population.json",
        f"https://api.worldbank.org/v2/country/{COUNTRIES}/indicator/SP.POP.TOTL?format=json&per_page=500&date=2000:2025",
        "World Bank WDI — Total Population",
    ),
    (
        "wb_renewables_share.json",
        f"https://api.worldbank.org/v2/country/{COUNTRIES}/indicator/EG.FEC.RNEW.ZS?format=json&per_page=500&date=2000:2025",
        "World Bank WDI (IEA/IRENA/UNSD) — Renewable Energy Share of Final Energy Consumption (%)",
    ),
]


def fetch_raw_file(url: str, dest: Path) -> tuple[str, int]:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "verifiable-editorial-skills/1.0 (open-data-audit)",
            "Accept": "*/*",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        if resp.status != 200:
            raise RuntimeError(f"Unexpected HTTP {resp.status} for {url}")
        payload = resp.read()

    if not payload:
        raise RuntimeError(f"Empty response payload from {url}")

    tmp_path = dest.with_suffix(dest.suffix + ".tmp")
    tmp_path.write_bytes(payload)
    os.replace(tmp_path, dest)

    digest = hashlib.sha256(payload).hexdigest()
    return digest, len(payload)


def main() -> int:
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    fetched_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    manifest_entries: dict[str, str] = {}
    source_records: list[dict[str, object]] = []

    for filename, url, label in SOURCES:
        dest = RAW_DIR / filename
        print(f"[*] Fetching {filename} <- {url}")
        digest, size_bytes = fetch_raw_file(url, dest)
        manifest_entries[filename] = digest
        source_records.append(
            {
                "filename": filename,
                "label": label,
                "url": url,
                "bytes": size_bytes,
                "sha256": digest,
                "fetched_at_utc": fetched_at,
            }
        )
        print(f"[OK] Sealed {filename} ({size_bytes:,} bytes | SHA-256: {digest[:16]}...)")

    # Write deduplicated, deterministically sorted manifest
    manifest_lines = [
        f"{manifest_entries[name]}  {name}\n" for name in sorted(manifest_entries)
    ]
    MANIFEST_PATH.write_text("".join(manifest_lines), encoding="utf-8")

    SOURCE_META_PATH.write_text(
        json.dumps(
            {"fetched_at_utc": fetched_at, "sources": source_records}, indent=2
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"[OK] Wrote {len(manifest_entries)} hashes to {MANIFEST_PATH}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
