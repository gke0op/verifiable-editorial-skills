#!/usr/bin/env python3
"""
Phase 4: Independent External Verification (Veto Gate).

Enforces the Anti-Cheat Constitution independently of process_data.py:
  1. Cryptographic Manifest Check: Re-hashes every file in data/raw/ against data/manifest.sha256.
  2. AST Anti-Circular Check (Rule 3): Parses verifier scripts and bans asserting
     domain variables against hardcoded numeric literals.
  3. Atomic Provenance Coverage (Rule 4): Confirms 100% of metrics in summary_metrics.json
     have a verified tuple in provenance_ledger.json with matching live file SHA-256.
  4. Independent Raw Re-Computation: Re-parses raw NOAA CSV and World Bank JSON files
     from scratch and checks summary_metrics.json against raw ground truth.
  5. Negative Capability Check (Rule 5): Confirms genuinely unreported fields (2025 CO2,
     2024 renewables share) remain explicit null rather than fabricated proxies.
"""
from __future__ import annotations

import ast
import csv
import hashlib
import json
import math
import sys
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = BASE_DIR / "data"
RAW_DIR = DATA_DIR / "raw"
SCRIPTS_DIR = BASE_DIR / "scripts"
MANIFEST_PATH = DATA_DIR / "manifest.sha256"
LEDGER_PATH = DATA_DIR / "provenance_ledger.json"
SUMMARY_PATH = DATA_DIR / "summary_metrics.json"

ALLOWED_STRUCTURAL_CONSTANTS = {0, 1, 2, 100, 1e-6, 1e-4, 1e-9}


def verify_manifest() -> dict[str, str]:
    print("[*] [1/5] Auditing cryptographic SHA-256 manifest...")
    if not MANIFEST_PATH.exists():
        raise AssertionError(f"Missing manifest: {MANIFEST_PATH}")

    expected: dict[str, str] = {}
    for raw_line in MANIFEST_PATH.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(None, 1)
        if len(parts) != 2:
            raise AssertionError(f"Malformed manifest line: {line}")
        digest, fname = parts
        if fname in expected:
            raise AssertionError(f"Duplicate entry in manifest.sha256: {fname}")
        expected[fname] = digest

    actual_files = {p.name for p in RAW_DIR.iterdir() if p.is_file()}
    if set(expected.keys()) != actual_files:
        raise AssertionError(
            f"Manifest/raw directory mismatch: manifest={sorted(expected)} vs disk={sorted(actual_files)}"
        )

    for fname, exp_hash in sorted(expected.items()):
        actual_hash = hashlib.sha256((RAW_DIR / fname).read_bytes()).hexdigest()
        if actual_hash != exp_hash:
            raise AssertionError(f"SHA-256 mismatch for {fname}: {actual_hash} != {exp_hash}")

    print(f"[OK] {len(expected)} raw source files match SHA-256 manifest (zero extras, zero duplicates).")
    return expected


def verify_no_circular_literals() -> None:
    print("[*] [2/5] Running Rule 3 AST Anti-Circular Verification linter...")
    verifier_files = sorted(SCRIPTS_DIR.glob("verify_*.py"))
    if not verifier_files:
        raise AssertionError("No verifier scripts found to audit.")

    violations: list[str] = []
    for path in verifier_files:
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        for node in ast.walk(tree):
            if isinstance(node, ast.Assert) and isinstance(node.test, ast.Compare):
                # Reject comparing an expression directly against a non-trivial numeric literal
                operands = [node.test.left, *node.test.comparators]
                for op in operands:
                    if isinstance(op, ast.Constant) and isinstance(op.value, (int, float)):
                        if not isinstance(op.value, bool) and op.value not in ALLOWED_STRUCTURAL_CONSTANTS:
                            violations.append(
                                f"{path.name}:{node.lineno} compares against hardcoded numeric literal {op.value!r}"
                            )
    if violations:
        raise AssertionError("AST Rule 3 violation(s):\n  " + "\n  ".join(violations))
    print(f"[OK] Audited {len(verifier_files)} verifier script(s): zero hardcoded domain literals in assertions.")


def verify_provenance_ledger(raw_hashes: dict[str, str]) -> tuple[dict, dict]:
    print("[*] [3/5] Auditing atomic provenance ledger coverage (Rule 4)...")
    summary = json.loads(SUMMARY_PATH.read_text(encoding="utf-8"))
    ledger = json.loads(LEDGER_PATH.read_text(encoding="utf-8"))

    ledger_by_id: dict[str, dict] = {}
    for entry in ledger:
        mid = entry["metric_id"]
        if mid in ledger_by_id:
            raise AssertionError(f"Duplicate metric_id in provenance ledger: {mid}")
        for req_key in (
            "metric_id",
            "unit",
            "source_document",
            "source_locator",
            "exact_extracted_quote",
            "raw_file_sha256",
            "parser_script",
        ):
            if not entry.get(req_key):
                raise AssertionError(f"Ledger entry {mid} missing required field {req_key}")

        src_path = BASE_DIR / entry["source_document"]
        if not src_path.exists():
            raise AssertionError(f"Ledger entry {mid} references missing source: {entry['source_document']}")
        if raw_hashes.get(src_path.name) != entry["raw_file_sha256"]:
            raise AssertionError(f"Ledger SHA-256 mismatch for {mid}")
        ledger_by_id[mid] = entry

    published_metrics: dict = summary["metrics"]
    missing = set(published_metrics.keys()) - set(ledger_by_id.keys())
    if missing:
        raise AssertionError(f"Ghost metrics without provenance tuples: {sorted(missing)}")

    for mid, pub_val in published_metrics.items():
        led_val = ledger_by_id[mid]["value"]
        if pub_val != led_val:
            raise AssertionError(f"Metric mismatch between summary and ledger for {mid}: {pub_val} != {led_val}")

    print(f"[OK] All {len(published_metrics)} published metrics have cryptographically verified provenance tuples.")
    return summary, ledger_by_id


def _assert_close(label: str, actual: float, expected: float, tol: float = 1e-4) -> None:
    if not math.isclose(actual, expected, rel_tol=tol, abs_tol=tol):
        raise AssertionError(f"Independent recomputation mismatch for {label}: published={actual}, raw={expected}")


def verify_independent_recomputation(summary: dict) -> None:
    print("[*] [4/5] Re-parsing data/raw/ independently from scratch...")
    pub = summary["metrics"]

    # Independently parse NOAA CSV
    noaa_lines = [
        ln
        for ln in (RAW_DIR / "noaa_co2_mm_mlo.csv").read_text(encoding="utf-8").splitlines()
        if ln.strip() and not ln.lstrip().startswith("#")
    ]
    noaa_rows = list(csv.DictReader(noaa_lines))
    first_deseas = float(noaa_rows[0]["deseasonalized"])
    latest_avg = float(noaa_rows[-1]["average"])
    latest_deseas = float(noaa_rows[-1]["deseasonalized"])
    peak_avg = max(float(r["average"]) for r in noaa_rows)

    _assert_close("noaa_first_deseasonalized_ppm", pub["noaa_first_deseasonalized_ppm"], first_deseas)
    _assert_close("noaa_latest_average_ppm", pub["noaa_latest_average_ppm"], latest_avg)
    _assert_close("noaa_latest_deseasonalized_ppm", pub["noaa_latest_deseasonalized_ppm"], latest_deseas)
    _assert_close("noaa_peak_average_ppm", pub["noaa_peak_average_ppm"], peak_avg)
    _assert_close("noaa_cumulative_rise_ppm", pub["noaa_cumulative_rise_ppm"], latest_deseas - first_deseas)
    assert pub["noaa_observation_count"] == len(noaa_rows)

    # Independently parse World Bank JSON files
    def wb_map(fname: str) -> dict[tuple[str, str], float | None]:
        rows = json.loads((RAW_DIR / fname).read_text(encoding="utf-8"))[1]
        return {(r["countryiso3code"], r["date"]): r["value"] for r in rows}

    wb_co2 = wb_map("wb_co2_total_mt.json")
    wb_pc = wb_map("wb_co2_per_capita.json")
    wb_gdp = wb_map("wb_gdp_const2015.json")
    wb_ren = wb_map("wb_renewables_share.json")

    isos = sorted({iso for iso, _ in wb_co2})
    sum_2000 = sum(float(wb_co2[(c, "2000")]) for c in isos)  # type: ignore[arg-type]
    sum_2024 = sum(float(wb_co2[(c, "2024")]) for c in isos)  # type: ignore[arg-type]
    _assert_close("panel8_co2_2000_mt", pub["panel8_co2_2000_mt"], sum_2000)
    _assert_close("panel8_co2_2024_mt", pub["panel8_co2_2024_mt"], sum_2024)
    _assert_close(
        "panel8_co2_change_2000_2024_pct",
        pub["panel8_co2_change_2000_2024_pct"],
        ((sum_2024 - sum_2000) / sum_2000) * 100.0,
    )

    for iso in isos:
        k = iso.lower()
        c00 = float(wb_co2[(iso, "2000")])  # type: ignore[arg-type]
        c24 = float(wb_co2[(iso, "2024")])  # type: ignore[arg-type]
        g24 = float(wb_gdp[(iso, "2024")])  # type: ignore[arg-type]
        pc24 = float(wb_pc[(iso, "2024")])  # type: ignore[arg-type]
        ren21 = float(wb_ren[(iso, "2021")])  # type: ignore[arg-type]

        _assert_close(f"{k}_co2_2000_mt", pub[f"{k}_co2_2000_mt"], c00)
        _assert_close(f"{k}_co2_2024_mt", pub[f"{k}_co2_2024_mt"], c24)
        _assert_close(f"{k}_co2_per_capita_2024_t", pub[f"{k}_co2_per_capita_2024_t"], pc24)
        _assert_close(f"{k}_renewables_2021_pct", pub[f"{k}_renewables_2021_pct"], ren21)
        _assert_close(
            f"{k}_carbon_intensity_2024",
            pub[f"{k}_carbon_intensity_2024"],
            (c24 * 1e6) / (g24 / 1e6),
        )

    print(f"[OK] Independently re-verified NOAA & all {len(isos)} economies from immutable raw files.")

    print("[*] [5/5] Auditing Rule 5 Negative Capability (Sacred N/A)...")
    for iso in isos:
        k = iso.lower()
        raw_co2_25 = wb_co2.get((iso, "2025"))
        raw_ren_24 = wb_ren.get((iso, "2024"))
        if raw_co2_25 is None and pub[f"{k}_co2_2025_mt"] is not None:
            raise AssertionError(f"Rule 5 fraud: fabricated {iso} 2025 CO2 when raw is null!")
        if raw_ren_24 is None and pub[f"{k}_renewables_2024_pct"] is not None:
            raise AssertionError(f"Rule 5 fraud: fabricated {iso} 2024 renewables when raw is null!")
    print("[OK] Unreported upstream fields preserved cleanly as explicit null (Sacred N/A).")


def main() -> int:
    try:
        raw_hashes = verify_manifest()
        verify_no_circular_literals()
        summary, _ = verify_provenance_ledger(raw_hashes)
        verify_independent_recomputation(summary)
    except Exception as exc:
        print(f"[!] INTEGRITY VETO TRIGGERED: {exc}", file=sys.stderr)
        return 1

    print("[OK] All 5 independent zero-mock gates PASSED. PDF compilation unlocked.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
