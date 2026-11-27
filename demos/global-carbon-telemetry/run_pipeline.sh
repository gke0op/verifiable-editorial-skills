#!/usr/bin/env bash
# Zero-Python Sovereign Zig Archival Verification Runner — Global Carbon Telemetry (Raw Data Hub + Letter Archive)
# Note: This directory serves as the SHA-256-sealed raw NOAA + World Bank telemetry hub for
# demos/typst-carbon-monograph/run_pipeline.sh (live Zig 0.17 + Typst PDF/UA-1 build).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../.." && pwd)"
VEDIT_BIN="${VEDIT_BIN:-$REPO/zig/zig-out/bin/vedit}"
ZIG_BIN="${ZIG_BIN:-$( [ -x "$HOME/zig-toolchains/zig-0.17.0/zig" ] && echo "$HOME/zig-toolchains/zig-0.17.0/zig" || command -v zig )}"

if [ ! -x "$VEDIT_BIN" ]; then
  (cd "$REPO/zig" && "$ZIG_BIN" build --release=safe)
fi

echo "=== [1/3] Pure-Zig Rule 4 + Rule 6 SHA-256 Compilation Latch (6 raw files, 129 tuples) ==="
"$VEDIT_BIN" latch "$DIR"
echo "=== [2/3] Archival Executive 16:9 Deck Geometry Court ==="
"$VEDIT_BIN" geometry "$DIR/report/EXECUTIVE_DECK_16x9.pdf"
echo "=== [3/3] Archival Letter Report Geometry Court ==="
"$VEDIT_BIN" geometry "$DIR/report/INSTITUTIONAL_REPORT_LETTER.pdf"
echo "[note] Archival Letter PDF retains legacy #0284c7 sky-blue accents (3.95:1); use #035E9E in new Typst builds."
echo "[note] For the live zero-Python Zig 0.17 + Typst PDF/UA-1 rebuild of this dataset, run:"
echo "       bash $REPO/demos/typst-carbon-monograph/run_pipeline.sh"
echo "[OK] Global Carbon Telemetry data hub verified."
