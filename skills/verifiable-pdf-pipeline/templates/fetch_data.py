#!/usr/bin/env python3
"""
Template — Phase 1: Deterministic Open-Data Ingestion & Cryptographic Sealing.

Streams upstream public files directly into data/raw/ using atomic file replacement
and writes a deduplicated, deterministically sorted data/manifest.sha256.
Safe to re-run repeatedly without appending duplicate manifest entries.
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

# Define (local_filename, upstream_url, human_label) tuples for your project:
SOURCES: list[tuple[str, str, str]] = [
    # Example:
    # (
    #     "noaa_co2_mm_mlo.csv",
    #     "https://gml.noaa.gov/webdata/ccgg/trends/co2/co2_mm_mlo.csv",
    #     "NOAA GML Mauna Loa Monthly Mean CO2 (ppm)",
    # ),
]


def fetch_raw_file(url: str, dest: Path, timeout: int = 30) -> tuple[str, int]:
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "verifiable-pdf-pipeline/1.0 (open-data-ingestion)"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        if resp.status != 200:
            raise RuntimeError(f"HTTP {resp.status} while fetching {url}")
        payload = resp.read()

    if not payload:
        raise RuntimeError(f"Empty payload returned from {url}")

    tmp_dest = dest.with_suffix(dest.suffix + ".tmp")
    tmp_dest.write_bytes(payload)
    os.replace(tmp_dest, dest)
    return hashlib.sha256(payload).hexdigest(), len(payload)


def write_sorted_manifest(entries: dict[str, str], manifest_path: Path = MANIFEST_PATH) -> None:
    """Write a clean, deduplicated, lexicographically sorted SHA-256 manifest."""
    lines = [f"{entries[name]}  {name}\n" for name in sorted(entries)]
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text("".join(lines), encoding="utf-8")


def main() -> int:
    if not SOURCES:
        print("[!] Configure SOURCES in scripts/fetch_data.py before running.", file=sys.stderr)
        return 1

    RAW_DIR.mkdir(parents=True, exist_ok=True)
    fetched_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    manifest: dict[str, str] = {}
    records: list[dict[str, object]] = []

    for filename, url, label in SOURCES:
        dest = RAW_DIR / filename
        print(f"[*] Fetching {filename} <- {url}")
        digest, nbytes = fetch_raw_file(url, dest)
        manifest[filename] = digest
        records.append(
            {
                "filename": filename,
                "label": label,
                "url": url,
                "bytes": nbytes,
                "sha256": digest,
                "fetched_at_utc": fetched_at,
            }
        )
        print(f"[OK] Sealed {filename} ({nbytes:,} bytes | SHA-256: {digest[:16]}...)")

    write_sorted_manifest(manifest, MANIFEST_PATH)
    SOURCE_META_PATH.write_text(
        json.dumps({"fetched_at_utc": fetched_at, "sources": records}, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"[OK] Manifest updated with {len(manifest)} unique files at {MANIFEST_PATH}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
