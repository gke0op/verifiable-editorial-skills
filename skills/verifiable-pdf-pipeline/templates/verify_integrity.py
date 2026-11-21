#!/usr/bin/env python3
"""
Template — Phase 4: Independent External Verification Veto Gate.

Enforces:
  1. Cryptographic SHA-256 verification of every file in data/raw/ vs data/manifest.sha256.
  2. Rule 3 Python AST Linter banning hardcoded numeric literals in verifier assertions.
  3. Rule 4 Atomic Provenance Ledger verification (100% coverage of summary_metrics.json).
  4. Hook point for independent raw-file recomputation (override verify_independent_raw_parse).
"""
from __future__ import annotations

import ast
import hashlib
import json
import sys
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = BASE_DIR / "data"
RAW_DIR = DATA_DIR / "raw"
SCRIPTS_DIR = BASE_DIR / "scripts"
MANIFEST_PATH = DATA_DIR / "manifest.sha256"
LEDGER_PATH = DATA_DIR / "provenance_ledger.json"
SUMMARY_PATH = DATA_DIR / "summary_metrics.json"

ALLOWED_STRUCTURAL_CONSTANTS = {0, 1, 2, 100, 1e-4, 1e-6, 1e-9}


def verify_manifest() -> dict[str, str]:
    if not MANIFEST_PATH.exists():
        raise AssertionError(f"Missing cryptographic manifest: {MANIFEST_PATH}")

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
            raise AssertionError(f"Duplicate manifest entry: {fname}")
        expected[fname] = digest

    disk_files = {p.name for p in RAW_DIR.iterdir() if p.is_file()}
    if set(expected.keys()) != disk_files:
        raise AssertionError(
            f"Raw directory diverges from manifest: manifest={sorted(expected)} vs disk={sorted(disk_files)}"
        )

    for fname, exp_hash in sorted(expected.items()):
        actual_hash = hashlib.sha256((RAW_DIR / fname).read_bytes()).hexdigest()
        if actual_hash != exp_hash:
            raise AssertionError(f"SHA-256 tamper/corruption detected in {fname}!")

    print(f"[OK] Manifest verified ({len(expected)} immutable raw files).")
    return expected


def verify_ast_no_circular_literals(scripts_dir: Path = SCRIPTS_DIR) -> None:
    """Rule 3: Reject verifier assertions comparing domain values to hardcoded numeric literals."""
    verifier_files = sorted(scripts_dir.glob("verify_*.py"))
    violations: list[str] = []

    for path in verifier_files:
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        for node in ast.walk(tree):
            if isinstance(node, ast.Assert) and isinstance(node.test, ast.Compare):
                operands = [node.test.left, *node.test.comparators]
                for op in operands:
                    if (
                        isinstance(op, ast.Constant)
                        and isinstance(op.value, (int, float))
                        and not isinstance(op.value, bool)
                        and op.value not in ALLOWED_STRUCTURAL_CONSTANTS
                    ):
                        violations.append(
                            f"{path.name}:{node.lineno} compares against numeric literal {op.value!r}"
                        )

    if violations:
        raise AssertionError("Rule 3 AST Anti-Circular violation(s):\n  " + "\n  ".join(violations))
    print(f"[OK] Rule 3 AST linter clean across {len(verifier_files)} verifier script(s).")


def verify_provenance_ledger(raw_hashes: dict[str, str]) -> dict:
    summary = json.loads(SUMMARY_PATH.read_text(encoding="utf-8"))
    ledger = json.loads(LEDGER_PATH.read_text(encoding="utf-8"))

    by_id: dict[str, dict] = {}
    for entry in ledger:
        mid = entry["metric_id"]
        if mid in by_id:
            raise AssertionError(f"Duplicate metric_id in provenance_ledger.json: {mid}")
        for req in ("metric_id", "unit", "source_document", "source_locator", "exact_extracted_quote", "raw_file_sha256"):
            if not entry.get(req):
                raise AssertionError(f"Ledger record {mid} missing required field '{req}'")
        src_path = BASE_DIR / entry["source_document"]
        if not src_path.exists():
            raise AssertionError(f"Ledger record {mid} cites missing source: {entry['source_document']}")
        if raw_hashes.get(src_path.name) != entry["raw_file_sha256"]:
            raise AssertionError(f"Ledger SHA-256 mismatch for {mid}")
        by_id[mid] = entry

    published = summary.get("metrics", {})
    ghosts = set(published.keys()) - set(by_id.keys())
    if ghosts:
        raise AssertionError(f"Ghost metrics lacking provenance tuples: {sorted(ghosts)}")

    for mid, pub_val in published.items():
        if pub_val != by_id[mid]["value"]:
            raise AssertionError(f"Summary/ledger value mismatch for {mid}: {pub_val} != {by_id[mid]['value']}")

    print(f"[OK] Provenance ledger verified ({len(published)} metrics, 100% coverage).")
    return summary


def verify_independent_raw_parse(summary: dict) -> None:
    """
    Implement independent raw-file parsing here (without importing process_data.py)
    and compare recomputed aggregates against summary['metrics'].
    """
    _ = summary


def main() -> int:
    try:
        raw_hashes = verify_manifest()
        verify_ast_no_circular_literals()
        summary = verify_provenance_ledger(raw_hashes)
        verify_independent_raw_parse(summary)
    except Exception as exc:
        print(f"[!] INTEGRITY VETO TRIGGERED: {exc}", file=sys.stderr)
        return 1

    print("[OK] Independent zero-mock verification PASSED. Compilation unlocked.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
