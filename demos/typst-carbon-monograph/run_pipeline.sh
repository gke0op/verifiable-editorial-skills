#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../.." && pwd)"
FONT_DIR="${VERIFIABLE_EDITORIAL_FONTS:-$HOME/.cache/verifiable-editorial/fonts}"
VEDIT_BIN="${VEDIT_BIN:-$REPO/zig/zig-out/bin/vedit}"
ZIG_BIN="${ZIG_BIN:-$( [ -x "$HOME/zig-toolchains/zig-0.17.0/zig" ] && echo "$HOME/zig-toolchains/zig-0.17.0/zig" || command -v zig )}"

if [ ! -x "$VEDIT_BIN" ]; then
  (cd "$REPO/zig" && "$ZIG_BIN" build --release=safe)
fi

echo "=== [1/5] Engaging Sovereign Zig Rule 4 + Rule 6 Compilation Latch (NOAA + World Bank) ==="
"$VEDIT_BIN" latch "$REPO/demos/global-carbon-telemetry"

echo "=== [2/5] Ensuring cross-platform SIL-OFL open-source font bundle (pure Zig) ==="
"$VEDIT_BIN" fetch-fonts --dir "$FONT_DIR"

echo "=== [3/5] Generating pure-vector SVG exhibits in Zig 0.17.0 (infinite print DPI) ==="
"$ZIG_BIN" run "$DIR/scripts/pipeline.zig" -- "$REPO"

echo "=== [4/5] Compiling Rust-native Typst PDF/UA-1 monograph (Zero Python!) ==="
OUT_PDF="$DIR/report/TYPST_CARBON_MONOGRAPH_UA1.pdf"
typst compile \
  --pdf-standard ua-1 \
  --root "$REPO" \
  --font-path "$FONT_DIR" \
  "$DIR/report/monograph.typ" \
  "$OUT_PDF"
echo "[typst] Compiled '$OUT_PDF' (--pdf-standard ua-1)"

echo "=== [5/5] Running Sovereign Zig 5-gate audit court (WCAG, geometry, Rule 10, prepress + veraPDF ISO 14289-1) ==="
"$VEDIT_BIN" audit-all "$OUT_PDF" \
  --ledger "$REPO/demos/global-carbon-telemetry/data/provenance_ledger.json" \
  --summary "$REPO/demos/global-carbon-telemetry/data/summary_metrics.json" \
  --citations "$DIR/data/background_citations.json" \
  --manifest "$REPO/demos/global-carbon-telemetry/data/manifest.sha256" \
  --min-dpi 300 \
  --require-ua

# Export 180-DPI page previews via pure-C mutool
mkdir -p "$DIR/previews"
mutool draw -F png -r 180 -o "$DIR/previews/typst_page_%02d.png" "$OUT_PDF" 2>/dev/null
echo "[previews] Exported 180-DPI PNG pages via pure-C mutool -> $DIR/previews"
