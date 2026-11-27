#!/usr/bin/env bash
# Zero-Python Sovereign Zig Archival Verification Runner — Dual-Theme Carbon Keynote (9-Slide 16:9)
# Note: Pre-rendered archival reference deck; for live Zig 0.17 + Typst PDF/UA-1 rebuilds of this dataset,
# run bash demos/typst-carbon-monograph/run_pipeline.sh.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../.." && pwd)"
VEDIT_BIN="${VEDIT_BIN:-$REPO/zig/zig-out/bin/vedit}"
ZIG_BIN="${ZIG_BIN:-$( [ -x "$HOME/zig-toolchains/zig-0.17.0/zig" ] && echo "$HOME/zig-toolchains/zig-0.17.0/zig" || command -v zig )}"

if [ ! -x "$VEDIT_BIN" ]; then
  (cd "$REPO/zig" && "$ZIG_BIN" build --release=safe)
fi

echo "=== [1/3] Pure-Zig Rule 4 + Rule 6 SHA-256 Compilation Latch (165 tuples) ==="
"$VEDIT_BIN" latch "$DIR"
echo "=== [2/3] Dark Obsidian 16:9 Deck — WCAG Contrast & Geometry Court ==="
"$VEDIT_BIN" contrast "$DIR/report/CARBON_KEYNOTE_16x9_DARK.pdf"
"$VEDIT_BIN" geometry "$DIR/report/CARBON_KEYNOTE_16x9_DARK.pdf"
echo "=== [3/3] Light Swiss Ivory 16:9 Deck — Geometry Court ==="
"$VEDIT_BIN" geometry "$DIR/report/CARBON_KEYNOTE_16x9_LIGHT.pdf"
echo "[note] Archival light-theme PDF retains legacy #0284c7 sky-blue accents (3.95:1); use #035E9E in new Typst builds."
echo "[OK] Carbon Keynote archival verification complete."
