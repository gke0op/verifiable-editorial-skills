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
OUT_PDF="$DEMO/report/EXOMUNDUS_NASA_TELEMETRY_UA1.pdf"

echo "=== [1/4] Pure-Zig 0.17.0 NASA Reality Compiler, SHA-256 Sealer & Vector SVG Engine ==="
"$ZIG_BIN" run -O ReleaseSafe "$DEMO/scripts/pipeline.zig" -- "$DEMO"

echo "=== [2/4] Engaging Pure-Zig Rule 4 + Rule 6 Compilation Latch ==="
"$VEDIT_ZIG" latch "$DEMO"

echo "=== [3/4] Compiling Rust-Native Typst PDF/UA-1 Monograph (Zero Python!) ==="
if [[ ! -d "$FONT_DIR" ]]; then
  vedit fetch-fonts --out-dir "$FONT_DIR"
fi
typst compile --root "$DEMO" --font-path "$FONT_DIR" --pdf-standard ua-1 \
  "$DEMO/report/monograph.typ" "$OUT_PDF"

echo "=== [4/4] Running Sovereign Zig 5-Gate Verification Court + Live veraPDF ISO 14289-1 ==="
"$VEDIT_ZIG" audit-all "$OUT_PDF" \
  --ledger "$DEMO/data/provenance_ledger.json" \
  --summary "$DEMO/data/summary_metrics.json" \
  --citations "$DEMO/data/background_citations.json" \
  --manifest "$DEMO/data/manifest.sha256" \
  --require-ua

mkdir -p "$DEMO/previews"
if command -v mutool >/dev/null 2>&1; then
  for p in 1 2 3 4; do
    mutool draw -r 180 -o "$DEMO/previews/exo_page_0${p}.png" "$OUT_PDF" "$p" 2>/dev/null
  done
  echo "[previews] Exported 4 180-DPI PNG pages via pure-C mutool -> $DEMO/previews"
fi
