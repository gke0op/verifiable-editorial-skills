#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "=== Phase 1: Live Open-Data Ingestion & SHA-256 Manifest ==="
python3 scripts/fetch_data.py

echo "=== Phase 2: Reality & Accounting Invariant Validation ==="
python3 scripts/validate_reality.py

echo "=== Phase 3: Extended Keynote Synthesis & 165-Tuple Provenance Ledger ==="
python3 scripts/process_data.py

echo "=== Phase 4: Independent Verification Veto Gate (AST Rule 3 + Raw Re-Parse) ==="
python3 scripts/verify_integrity.py

echo "=== Phase 5a: 7-Exhibit 300-DPI Chart Generation (Dark & Light Themes) ==="
python3 scripts/generate_charts.py

echo "=== Phase 5b: Latched Dual-Theme 9-Slide 16:9 Presentation Compilation ==="
python3 report/compile_presentation_16x9.py --theme all

echo "=== Phase 5c: PyMuPDF Visual Bounding-Box QA Audit & Preview Export ==="
python3 scripts/audit_pdf.py report/CARBON_KEYNOTE_16x9_DARK.pdf --pages 9 --min-fill 72 --previews previews --prefix dark_slide
python3 scripts/audit_pdf.py report/CARBON_KEYNOTE_16x9_LIGHT.pdf --pages 9 --min-fill 72 --previews previews --prefix light_slide

echo "[OK] Full 9-slide dual-theme verifiable keynote pipeline succeeded."
