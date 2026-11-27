#!/usr/bin/env bash
# Zero-Python Sovereign Zig Archival Verification Runner — Consulting Flagship Deck (10-Slide 16:9)
# Note: Pre-rendered archival visual showcase; for live Zig 0.17 + Typst PDF/UA-1 rebuilds,
# see demos/{cosmos-mobile-primer,prl-yang-mills-chaos,caie-flowshop-journal,exomundus-nasa-telemetry,typst-carbon-monograph}/.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../.." && pwd)"
VEDIT_BIN="${VEDIT_BIN:-$REPO/zig/zig-out/bin/vedit}"
ZIG_BIN="${ZIG_BIN:-$( [ -x "$HOME/zig-toolchains/zig-0.17.0/zig" ] && echo "$HOME/zig-toolchains/zig-0.17.0/zig" || command -v zig )}"

if [ ! -x "$VEDIT_BIN" ]; then
  (cd "$REPO/zig" && "$ZIG_BIN" build --release=safe)
fi

echo "=== [1/2] Pure-Zig Rule 4 + Rule 6 SHA-256 Compilation Latch (165 tuples) ==="
"$VEDIT_BIN" latch "$DIR"
echo "=== [2/2] Geometry Court (OBB/AABB collisions, Bezier W/W* clip, overflow, orphans) ==="
"$VEDIT_BIN" geometry "$DIR/report/CONSULTING_FLAGSHIP_DECK.pdf"
echo "[note] Archival consulting PDF retains legacy #0284c7 sky-blue labels (4.10:1); use #035E9E in new Typst builds."
echo "[OK] Consulting Flagship archival verification complete."
