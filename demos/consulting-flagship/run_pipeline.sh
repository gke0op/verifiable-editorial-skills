#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# Ensure macOS Homebrew Pango/GObject libraries are visible to WeasyPrint
if [ -d "/opt/homebrew/lib" ]; then
  export DYLD_FALLBACK_LIBRARY_PATH="/opt/homebrew/lib:${DYLD_FALLBACK_LIBRARY_PATH:-}"
fi

echo "=== Phase 1: Live Open-Data Ingestion & SHA-256 Manifest ==="
python3 scripts/fetch_data.py

echo "=== Phase 2: Reality & Accounting Invariant Validation ==="
python3 scripts/validate_reality.py

echo "=== Phase 3: Synthesis & 165-Tuple Atomic Provenance Ledger ==="
python3 scripts/process_data.py

echo "=== Phase 4: Independent Verification Veto Gate (AST Rule 3 + Raw Re-Parse) ==="
python3 scripts/verify_integrity.py

echo "=== Phase 5a: WeasyPrint + Pure Vector Inline SVG 10-Slide Compilation ==="
python3 report/compile_consulting_flagship.py

echo "=== Phase 5b: PyMuPDF Visual Bounding-Box QA Audit & 180-DPI Previews ==="
python3 scripts/audit_pdf.py report/CONSULTING_FLAGSHIP_DECK.pdf --pages 10 --min-fill 72 --previews previews --prefix flagship_slide

echo "[OK] Consulting Flagship 10-slide verifiable deck pipeline succeeded."
