#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DYLD_FALLBACK_LIBRARY_PATH="/opt/homebrew/lib:${DYLD_FALLBACK_LIBRARY_PATH:-}"

echo "=== [1/3] Sealing 11 Nano Banana editorial plates (SHA-256) ==="
python3 "$DIR/scripts/seal_assets.py"

echo "=== [2/3] Compiling FELIS MUNDI 8-page full-bleed magazine PDF ==="
python3 "$DIR/report/compile_magazine.py"

echo "=== [3/3] Auditing >=50% full-bleed photo coverage & rendering previews ==="
python3 "$DIR/scripts/audit_magazine.py"
