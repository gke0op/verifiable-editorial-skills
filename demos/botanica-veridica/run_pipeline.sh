#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DYLD_FALLBACK_LIBRARY_PATH="/opt/homebrew/lib:${DYLD_FALLBACK_LIBRARY_PATH:-}"

if [[ "${FETCH_LIVE:-0}" == "1" ]]; then
  echo "=== [0/5] Fetching live GBIF, iNaturalist, and Open Tree of Life payloads ==="
  python3 "$DIR/scripts/fetch_botanical_data.py"
fi

echo "=== [1/5] Validating live botanical taxonomy, phylogeny & accounting invariants (Rule 2 + Rule 9) ==="
python3 "$DIR/scripts/validate_botany.py"

echo "=== [2/5] Running AST anti-circular, SHA-256 & 1:1 provenance integrity gate (Rule 3/4/6/9) ==="
python3 "$DIR/scripts/verify_integrity.py"

echo "=== [3/5] Compiling digital interactive PDF/UA-1 monograph ==="
python3 "$DIR/report/compile_monograph.py"

echo "=== [4/5] Compiling print-shop prepress PDF (3mm bleed + crop/registration marks) ==="
python3 "$DIR/report/compile_monograph.py" --prepress

echo "=== [5/5] Auditing WCAG 2.1 contrast, clip-aware plate coverage, bookmarks/links & facing spreads ==="
python3 "$DIR/scripts/audit_monograph.py"
