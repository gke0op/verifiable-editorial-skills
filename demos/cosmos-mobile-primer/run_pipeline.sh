#!/usr/bin/env bash
set -euo pipefail

DEMO="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$DEMO/../.." && pwd)"
ZIG_BIN="${ZIG_BIN:-$HOME/zig-toolchains/zig-0.17.0/zig}"
if [[ ! -x "$ZIG_BIN" ]]; then
  ZIG_BIN="$(command -v zig)"
fi
VEDIT_ZIG="${VEDIT_ZIG:-$REPO/zig/zig-out/bin/vedit}"
FONT_DIR="${VEDIT_FONT_DIR:-$HOME/.cache/verifiable-editorial/fonts}"
OUT_PDF="$DEMO/report/COSMOS_MOBILE_PRIMER_UA1.pdf"

echo "=== [1/4] Pure-Zig 0.17.0 Celestial Physics, Provenance & Mobile OLED SVG Compiler ==="
"$ZIG_BIN" run -O ReleaseSafe "$DEMO/scripts/pipeline.zig" -- "$DEMO"

echo "=== [2/4] Engaging Pure-Zig Rule 4 + Rule 6 Compilation Latch ==="
"$VEDIT_ZIG" latch "$DEMO"

echo "=== [3/4] Compiling Mobile-Native 9:16 PDF/UA-1 Field Primer (WhatsApp-Ready, Zero Python!) ==="
if [[ ! -d "$FONT_DIR" ]]; then
  vedit fetch-fonts --out-dir "$FONT_DIR"
fi
typst compile --root "$DEMO" --font-path "$FONT_DIR" --pdf-standard ua-1 \
  "$DEMO/report/primer.typ" "$OUT_PDF"

echo "=== [4/4] Running Sovereign Zig 6-Gate Court (incl. Rule 11 Live Links + veraPDF ISO 14289-1) ==="
LINK_FLAG="${VEDIT_LINK_FLAG:---verify-links}"
"$VEDIT_ZIG" audit-all "$OUT_PDF" \
  --ledger "$DEMO/data/provenance_ledger.json" \
  --summary "$DEMO/data/summary_metrics.json" \
  --citations "$DEMO/data/background_citations.json" \
  --manifest "$DEMO/data/manifest.sha256" \
  --require-ua \
  "$LINK_FLAG"

mkdir -p "$DEMO/previews"
if command -v mutool >/dev/null 2>&1; then
  rm -f "$DEMO/previews"/mobile_card_*.png
  PAGES="$(mutool info "$OUT_PDF" 2>/dev/null | awk '/Pages:/ {print $2}')"
  for p in $(seq 1 "${PAGES:-12}"); do
    printf -v pad "%02d" "$p"
    mutool draw -r 200 -o "$DEMO/previews/mobile_card_${pad}.png" "$OUT_PDF" "$p" 2>/dev/null
  done
  echo "[previews] Exported ${PAGES:-12} 200-DPI mobile card PNGs via pure-C mutool -> $DEMO/previews"
fi
ls -lh "$OUT_PDF"
