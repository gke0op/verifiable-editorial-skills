#!/usr/bin/env python3
"""
Template — Phase 5b: Post-Render Visual Bounding-Box QA Auditor (PyMuPDF / fitz).

Supports both Letter portrait reports (612x792 pt) and 16:9 widescreen decks (960x540 pt).
Measures actual visual vertical fill combining text blocks, embedded chart images, and
non-background vector drawings while excluding running headers, footers, and full-bleed
page backgrounds. Optionally exports PNG previews for visual inspection.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import fitz


def audit_pdf(
    pdf_path: Path,
    expected_pages: int | None = None,
    min_fill_pct: float = 70.0,
    preview_dir: Path | None = None,
    preview_prefix: str = "page",
    preview_dpi: int = 180,
) -> bool:
    doc = fitz.open(str(pdf_path))
    n_pages = len(doc)
    if expected_pages is not None and n_pages != expected_pages:
        raise AssertionError(f"Page count mismatch: got {n_pages}, expected {expected_pages}")

    if preview_dir is not None:
        preview_dir.mkdir(parents=True, exist_ok=True)

    all_ok = True
    print(f"[*] Auditing {pdf_path.name} ({n_pages} pages)...")

    for idx, page in enumerate(doc):
        pw, ph = page.rect.width, page.rect.height
        is_widescreen = pw > ph

        if is_widescreen:
            top_folio_y, bot_folio_y, printable_h = 32.0, ph - 28.0, ph - 72.0
        else:
            top_folio_y, bot_folio_y, printable_h = 50.0, ph - 50.0, ph - 108.0

        boxes: list[tuple[float, float, float, float]] = []

        for blk in page.get_text("blocks"):
            x0, y0, x1, y1 = blk[:4]
            if (blk[4] or "").strip() and y0 >= top_folio_y and y1 <= bot_folio_y:
                boxes.append((x0, y0, x1, y1))

        for img in page.get_images(full=True):
            for r in page.get_image_rects(img[0]):
                if r.width < pw * 0.98 and r.height < ph * 0.98:
                    boxes.append((r.x0, r.y0, r.x1, r.y1))

        for d in page.get_drawings():
            r = d["rect"]
            if r.width >= pw * 0.95 and r.height >= ph * 0.95:
                continue
            if r.y0 >= top_folio_y and r.y1 <= bot_folio_y and (r.height > 1.5 or r.width > 40):
                boxes.append((r.x0, r.y0, r.x1, r.y1))

        if boxes:
            min_x = min(b[0] for b in boxes)
            min_y = min(b[1] for b in boxes)
            max_x = max(b[2] for b in boxes)
            max_y = max(b[3] for b in boxes)
            fill_pct = min(100.0, ((max_y - min_y) / printable_h) * 100.0)
            overflow = (min_x < 10.0) or (max_x > pw - 10.0) or (max_y > ph - 10.0)
        else:
            fill_pct, overflow = 0.0, False

        status = "OK" if (fill_pct >= min_fill_pct and not overflow) else "FAIL"
        if status == "FAIL":
            all_ok = False
        print(
            f"  Page {idx + 1:2d}/{n_pages} ({pw:.0f}x{ph:.0f} pt): "
            f"vertical fill = {fill_pct:5.1f}% (min {min_fill_pct:.0f}%), overflow={overflow} [{status}]"
        )

        if preview_dir is not None:
            page.get_pixmap(dpi=preview_dpi).save(str(preview_dir / f"{preview_prefix}_{idx + 1:02d}.png"))

    doc.close()
    if not all_ok:
        raise AssertionError(f"Visual layout audit failed for {pdf_path.name}")
    print(f"[OK] {pdf_path.name} passed visual QA audit.")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit PDF vertical fill & export PNG previews.")
    parser.add_argument("pdf", type=Path)
    parser.add_argument("--pages", type=int, default=None)
    parser.add_argument("--min-fill", type=float, default=70.0)
    parser.add_argument("--previews", type=Path, default=None)
    parser.add_argument("--prefix", type=str, default="page")
    args = parser.parse_args()

    try:
        audit_pdf(args.pdf, args.pages, args.min_fill, args.previews, args.prefix)
    except Exception as exc:
        print(f"[!] AUDIT FAILED: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
