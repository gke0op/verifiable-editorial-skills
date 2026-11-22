#!/usr/bin/env python3
"""Rule 3, Rule 4, Rule 6, & Rule 9 Integrity Latch:
- Python AST anti-circular check (bans hardcoded domain literals in assertions)
- Live SHA-256 verification against data/manifest.sha256
- 1:1 Atomic Provenance Ledger reconciliation against data/summary_metrics.json
- Rule 9 Taxonomy Verification against raw GBIF & OpenTree API files
"""

from __future__ import annotations

import ast
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT / "data"
MANIFEST = DATA_DIR / "manifest.sha256"
SUMMARY = DATA_DIR / "summary_metrics.json"
LEDGER = DATA_DIR / "provenance_ledger.json"


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def ast_anti_circular_check(script_paths: list[Path]) -> list[str]:
    """Rule 3: Reject assert statements comparing values against non-trivial numeric literals."""
    allowed_trivials = {0, 1, 2, 12, 100}
    errors: list[str] = []
    for spath in script_paths:
        tree = ast.parse(spath.read_text(encoding="utf-8"), filename=str(spath))
        for node in ast.walk(tree):
            if isinstance(node, ast.Assert):
                for sub in ast.walk(node.test):
                    if isinstance(sub, ast.Constant) and isinstance(sub.value, (int, float)):
                        if sub.value not in allowed_trivials:
                            errors.append(
                                f"AST Rule 3 violation in {spath.name}:{node.lineno}: hardcoded numeric literal {sub.value!r} in assert"
                            )
    return errors


def verify_manifest() -> tuple[list[str], int]:
    errors: list[str] = []
    if not MANIFEST.exists():
        return [f"Missing manifest: {MANIFEST}"], 0
    lines = [ln.strip() for ln in MANIFEST.read_text(encoding="utf-8").splitlines() if ln.strip()]
    for ln in lines:
        digest, rel = ln.split("  ", 1)
        fpath = ROOT / rel
        if not fpath.exists():
            errors.append(f"Manifest file missing: {rel}")
            continue
        actual = sha256_file(fpath)
        if actual != digest:
            errors.append(f"SHA-256 mismatch for {rel}: expected {digest[:12]}, got {actual[:12]}")
    return errors, len(lines)


def verify_provenance_and_taxonomy() -> list[str]:
    errors: list[str] = []
    summary = json.loads(SUMMARY.read_text(encoding="utf-8"))
    ledger = json.loads(LEDGER.read_text(encoding="utf-8"))

    # Check every species record against raw GBIF & OpenTree JSON (Rule 9)
    tnrs_raw = json.loads((DATA_DIR / "raw" / "opentree_tnrs.json").read_text(encoding="utf-8"))
    ott_truth = {
        item["name"].lower(): int(item["matches"][0]["taxon"]["ott_id"])
        for item in tnrs_raw.get("results", [])
        if item.get("matches")
    }

    for sp in summary["species"]:
        slug = sp["slug"]
        raw_match = json.loads((DATA_DIR / "raw" / f"gbif_match_{slug}.json").read_text(encoding="utf-8"))
        if sp["gbif_usage_key"] != raw_match["usageKey"]:
            errors.append(f"Rule 9 mismatch: {slug} gbif_usage_key differs from raw GBIF match")
        if sp["family"] != raw_match["family"] or sp["order"] != raw_match["order"]:
            errors.append(f"Rule 9 mismatch: {slug} family/order differs from raw GBIF match")
        if sp["opentree_ott_id"] != ott_truth.get(sp["canonical_name"].lower()):
            errors.append(f"Rule 9 mismatch: {slug} opentree_ott_id differs from raw OpenTree TNRS")

        required_keys = [
            "gbif_usage_key",
            "family",
            "order",
            "opentree_ott_id",
            "iucn_effective_code",
            "gbif_total_occurrences",
            "gbif_georeferenced_occurrences",
            "gbif_preserved_specimens",
            "gbif_human_observations",
            "herbarium_share_pct",
            "inat_observations_total",
            "inat_flowering_total",
            "inat_peak_flowering_month",
        ]
        for rk in required_keys:
            lkey = f"{slug}.{rk}"
            if lkey not in ledger:
                errors.append(f"Rule 4 missing provenance key: {lkey}")
            elif ledger[lkey]["value"] != sp[rk]:
                errors.append(f"Rule 4 value drift on {lkey}: ledger={ledger[lkey]['value']} vs summary={sp[rk]}")

    # Re-verify SHA-256 for every ledger source reference
    checked_hashes: dict[str, str] = {}
    for k, entry in ledger.items():
        rel = entry["source_file"]
        if rel not in checked_hashes:
            checked_hashes[rel] = sha256_file(ROOT / rel)
        if checked_hashes[rel] != entry["source_sha256"]:
            errors.append(f"Rule 4 stale hash on {k} ({rel})")

    return errors


def main() -> int:
    errors: list[str] = []
    errors.extend(ast_anti_circular_check([Path(__file__), ROOT / "scripts" / "validate_botany.py"]))
    m_errs, m_count = verify_manifest()
    errors.extend(m_errs)
    if not m_errs and SUMMARY.exists() and LEDGER.exists():
        errors.extend(verify_provenance_and_taxonomy())
    else:
        if not SUMMARY.exists() or not LEDGER.exists():
            errors.append("Missing summary_metrics.json or provenance_ledger.json")

    if errors:
        for e in errors:
            print(f"[FAIL] {e}", file=sys.stderr)
        return 1

    ledger = json.loads(LEDGER.read_text(encoding="utf-8"))
    print(f"[verify_integrity] PASS: AST clean | {m_count} manifest files sealed | {len(ledger)} provenance tuples + Rule 9 taxonomy verified.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
