#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../.." && pwd)"
FONT_DIR="${VERIFIABLE_EDITORIAL_FONTS:-$HOME/.cache/verifiable-editorial/fonts}"

echo "=== [1/5] Engaging Rule 6 Compilation Latch (shared NOAA + World Bank raw data integrity) ==="
python3 "$REPO/demos/global-carbon-telemetry/scripts/verify_integrity.py"

echo "=== [2/5] Ensuring cross-platform SIL-OFL open-source font bundle ==="
python3 -m verifiable_editorial.cli fetch-fonts --dir "$FONT_DIR"

echo "=== [3/5] Generating pure-vector SVG exhibits (infinite print DPI) ==="
python3 "$DIR/scripts/generate_vector_charts.py"

echo "=== [4/5] Compiling Rust-native Typst PDF/UA-1 monograph (timing live compile) ==="
OUT_PDF="$DIR/report/TYPST_CARBON_MONOGRAPH_UA1.pdf"
python3 - <<PY
import subprocess, time, sys
t0 = time.perf_counter()
cmd = [
    "typst", "compile",
    "--pdf-standard", "ua-1",
    "--root", "$REPO",
    "--font-path", "$FONT_DIR",
    "$DIR/report/monograph.typ",
    "$OUT_PDF",
]
res = subprocess.run(cmd, capture_output=True, text=True)
dt_ms = (time.perf_counter() - t0) * 1000.0
if res.stdout: print(res.stdout.strip())
if res.stderr: print(res.stderr.strip(), file=sys.stderr)
if res.returncode != 0:
    raise SystemExit(res.returncode)
print(f"[typst] Compiled '$OUT_PDF' in {dt_ms:.1f} ms (--pdf-standard ua-1)")
PY

echo "=== [5/5] Running 5-gate audit court (WCAG contrast, geometry, Rule 10 prose, prepress + veraPDF ISO 14289-1) ==="
python3 -m verifiable_editorial.cli audit-all "$OUT_PDF" \
  --ledger "$REPO/demos/global-carbon-telemetry/data/provenance_ledger.json" \
  --summary "$REPO/demos/global-carbon-telemetry/data/summary_metrics.json" \
  --citations "$DIR/data/background_citations.json" \
  --manifest "$REPO/demos/global-carbon-telemetry/data/manifest.sha256" \
  --prepress-dpi 300 \
  --require-ua

# Export 180-DPI page previews for visual inspection
python3 - <<PY
import fitz
from pathlib import Path
out_dir = Path("$DIR/previews")
out_dir.mkdir(parents=True, exist_ok=True)
doc = fitz.open("$OUT_PDF")
for i, page in enumerate(doc, 1):
    page.get_pixmap(dpi=180, alpha=False).save(out_dir / f"typst_page_{i:02d}.png")
print(f"[previews] Exported {len(doc)} PNG pages -> {out_dir}")
doc.close()
PY
