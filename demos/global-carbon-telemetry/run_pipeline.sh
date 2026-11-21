#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "=== Phase 1: Live Open-Data Ingestion & SHA-256 Manifest ==="
python3 scripts/fetch_data.py

echo "=== Phase 2: Reality & Accounting Invariant Validation ==="
python3 scripts/validate_reality.py

echo "=== Phase 3: Synthesis & Atomic Provenance Registration ==="
python3 scripts/process_data.py

echo "=== Phase 4: Independent Verification Veto Gate ==="
python3 scripts/verify_integrity.py

echo "=== Phase 5a: 300-DPI Vector Chart Generation (Dark & Light) ==="
python3 scripts/generate_charts.py

echo "=== Phase 5b: Latched PDF Compilation (16:9 Deck + Letter Report) ==="
python3 report/compile_deck_16x9.py
python3 report/compile_report_letter.py

echo "=== Phase 5c: PyMuPDF Visual Bounding-Box QA Audit & Preview Export ==="
python3 scripts/audit_pdf.py report/EXECUTIVE_DECK_16x9.pdf --pages 6 --min-fill 72 --previews previews --prefix deck_slide
python3 scripts/audit_pdf.py report/INSTITUTIONAL_REPORT_LETTER.pdf --pages 4 --min-fill 82 --previews previews --prefix report_page

echo "[OK] Full 5-phase verifiable editorial pipeline succeeded."
