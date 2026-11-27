#!/usr/bin/env bash
# Zero-Python Verifiable Editorial Build & 6-Gate Certification Latch (`build.sh`)
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VEDIT_BIN="${VEDIT_BIN:-vedit}"
ZIG_BIN="${ZIG_BIN:-$( [ -x "$HOME/zig-toolchains/zig-0.17.0/zig" ] && echo "$HOME/zig-toolchains/zig-0.17.0/zig" || command -v zig )}"
FONT_DIR="${VEDIT_FONT_DIR:-$HOME/.cache/verifiable-editorial/fonts}"

echo "=== [1/4] Pure-Zig 0.17.0 Data Parsing, Invariants & Provenance Sealing ==="
"$ZIG_BIN" run "$DIR/scripts/pipeline.zig" -- "$DIR"

echo "=== [2/4] Rule 4 + Rule 6 Compilation Latch & SIL-OFL Font Provisioning ==="
"$VEDIT_BIN" latch "$DIR"
"$VEDIT_BIN" fetch-fonts --dir "$FONT_DIR"

echo "=== [3/4] Compiling Rust-Native Typst PDF/UA-1 Publication ==="
OUT_PDF="$DIR/report/OUTPUT_UA1.pdf"
typst compile --pdf-standard ua-1 --root "$DIR" --font-path "$FONT_DIR" "$DIR/report/main.typ" "$OUT_PDF"

echo "=== [4/4] Sovereign Zig 6-Gate Court (WCAG, Geometry, Rule 10, Prepress + veraPDF, Rule 11 Live Links) ==="
"$VEDIT_BIN" audit-all "$OUT_PDF" \
  --ledger "$DIR/data/provenance_ledger.json" \
  --summary "$DIR/data/summary_metrics.json" \
  --citations "$DIR/data/background_citations.json" \
  --manifest "$DIR/data/manifest.sha256" \
  --require-ua \
  --verify-links

mkdir -p "$DIR/previews"
mutool draw -F png -r 180 -o "$DIR/previews/page_%02d.png" "$OUT_PDF" 2>/dev/null
echo "[done] Certified PDF/UA-1 -> $OUT_PDF"
