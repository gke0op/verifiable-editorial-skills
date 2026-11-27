#!/usr/bin/env bash
# Zero-Python Sovereign Zig Archival Verification Runner — BOTANICA VERIDICA
# Note: BOTANICA_VERIDICA_MONOGRAPH.pdf is a preserved archival visual showcase;
# for live end-to-end Zig 0.17 + Typst PDF/UA-1 rebuilds, see demos/{cosmos-mobile-primer,prl-yang-mills-chaos,caie-flowshop-journal,exomundus-nasa-telemetry,typst-carbon-monograph}/.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../.." && pwd)"
VEDIT_BIN="${VEDIT_BIN:-$REPO/zig/zig-out/bin/vedit}"
ZIG_BIN="${ZIG_BIN:-$( [ -x "$HOME/zig-toolchains/zig-0.17.0/zig" ] && echo "$HOME/zig-toolchains/zig-0.17.0/zig" || command -v zig )}"

if [ ! -x "$VEDIT_BIN" ]; then
  (cd "$REPO/zig" && "$ZIG_BIN" build --release=safe)
fi

PDF="$DIR/report/BOTANICA_VERIDICA_MONOGRAPH.pdf"
echo "=== [1/6] Pure-Zig Rule 4 + Rule 6 SHA-256 Compilation Latch (52 raw files) ==="
"$VEDIT_BIN" latch "$DIR"
echo "=== [2/6] Composited 144/360-DPI WCAG 2.1 AA Contrast Gate ==="
"$VEDIT_BIN" contrast "$PDF"
echo "=== [3/6] Geometry (OBB/AABB collisions, Bezier W/W* clip, overflow, orphans) ==="
"$VEDIT_BIN" geometry "$PDF"
echo "=== [4/6] Clip-Aware Dual-Key Visible Photo Coverage (pages 1,4-9 >= 50%) ==="
"$VEDIT_BIN" coverage "$PDF" --min-pct 50 --pages "1,4-9"
echo "=== [5/6] Rule 10 Post-Render Prose Grounding ==="
"$VEDIT_BIN" prose "$PDF" \
  --ledger "$DIR/data/provenance_ledger.json" \
  --summary "$DIR/data/summary_metrics.json" \
  --citations "$DIR/data/background_citations.json" \
  --manifest "$DIR/data/manifest.sha256"
echo "=== [6/6] Rule 11 Offline Clickable Link Integrity ==="
"$VEDIT_BIN" links "$PDF" --offline
echo "[OK] BOTANICA VERIDICA archival monograph passed all 6 sovereign Zig verification gates."
