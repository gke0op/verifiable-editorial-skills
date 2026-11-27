#!/usr/bin/env bash
# Zero-Python Sovereign Zig Archival Verification Runner — FELIS MUNDI Full-Bleed Photo Magazine
# Note: Pre-rendered archival visual showcase; audits exact >=50% clip-aware visible photography coverage.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../.." && pwd)"
VEDIT_BIN="${VEDIT_BIN:-$REPO/zig/zig-out/bin/vedit}"
ZIG_BIN="${ZIG_BIN:-$( [ -x "$HOME/zig-toolchains/zig-0.17.0/zig" ] && echo "$HOME/zig-toolchains/zig-0.17.0/zig" || command -v zig )}"

if [ ! -x "$VEDIT_BIN" ]; then
  (cd "$REPO/zig" && "$ZIG_BIN" build --release=safe)
fi

PDF="$DIR/report/FELIS_MUNDI_MAGAZINE.pdf"
echo "=== [1/2] Exact Clip-Aware Dual-Key Visible Photo Coverage (all 8 pages >= 50%, >= 2 bleed edges) ==="
"$VEDIT_BIN" coverage "$PDF" --min-pct 50 --min-bleed 2
echo "=== [2/2] Dissected Design DNA Structural Telemetry ==="
"$VEDIT_BIN" inspect "$PDF" >/dev/null
echo "[OK] FELIS MUNDI archival photo magazine passed sovereign Zig coverage & inspection."
