#!/usr/bin/env python3
"""PyMuPDF visual + exact PDF-clip-aware full-bleed photo-coverage audit gate for FELIS MUNDI."""

from __future__ import annotations

import io
import json
import sys
from pathlib import Path
from PIL import Image
import fitz  # PyMuPDF

ROOT = Path(__file__).resolve().parent.parent
PDF_PATH = ROOT / "report" / "FELIS_MUNDI_MAGAZINE.pdf"
PREVIEW_DIR = ROOT / "previews"
AUDIT_JSON = ROOT / "data" / "magazine_audit.json"

EXPECTED_PAGES = 8
MIN_PHOTO_COVERAGE_PCT = 50.0


def make_solid_png(rgb: tuple[int, int, int]) -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", (4, 4), rgb).save(buf, format="PNG")
    return buf.getvalue()


def measure_exact_visible_photo_coverage(pdf_bytes: bytes, page_index: int) -> tuple[float, list[str], int]:
    """Measure exact visible photo pixels (respecting all PDF clip paths & z-order occlusion).

    Replaces every embedded image XObject on two in-memory copies of the PDF with distinct solid
    key colors (magenta vs lime) and diffs the 72-DPI rasterizations. A pixel differs if and only
    if a clipped, unoccluded photograph contributes to that pixel (including under translucent scrims).
    """
    key_a = make_solid_png((255, 0, 255))
    key_b = make_solid_png((0, 255, 0))

    doc_a = fitz.open(stream=pdf_bytes, filetype="pdf")
    doc_b = fitz.open(stream=pdf_bytes, filetype="pdf")
    page_a = doc_a[page_index]
    page_b = doc_b[page_index]

    xrefs = sorted({img[0] for img in page_a.get_images(full=True) if page_a.get_image_rects(img[0])})
    for xref in xrefs:
        page_a.replace_image(xref, stream=key_a)
        page_b.replace_image(xref, stream=key_b)

    pix_a = page_a.get_pixmap(dpi=72, alpha=False)
    pix_b = page_b.get_pixmap(dpi=72, alpha=False)
    w, h = pix_a.width, pix_a.height
    sa, sb = pix_a.samples, pix_b.samples

    doc_a.close()
    doc_b.close()

    total_px = w * h
    changed = 0
    edge_hits = {"L": 0, "R": 0, "T": 0, "B": 0}

    # Stride 3 (RGB)
    for y in range(h):
        row_off = y * w * 3
        for x in range(w):
            i = row_off + x * 3
            if sa[i] != sb[i] or sa[i + 1] != sb[i + 1] or sa[i + 2] != sb[i + 2]:
                changed += 1
                if x <= 1:
                    edge_hits["L"] += 1
                if x >= w - 2:
                    edge_hits["R"] += 1
                if y <= 1:
                    edge_hits["T"] += 1
                if y >= h - 2:
                    edge_hits["B"] += 1

    pct = (changed / total_px) * 100.0 if total_px else 0.0
    # Require >= 25% of an edge's length to carry visible photo pixels to count as a full-bleed edge
    bleed_edges = []
    if edge_hits["L"] >= h * 0.25:
        bleed_edges.append("L")
    if edge_hits["R"] >= h * 0.25:
        bleed_edges.append("R")
    if edge_hits["T"] >= w * 0.25:
        bleed_edges.append("T")
    if edge_hits["B"] >= w * 0.25:
        bleed_edges.append("B")

    return pct, sorted(bleed_edges), len(xrefs)


def main() -> int:
    if not PDF_PATH.exists():
        print(f"FAIL: PDF missing at {PDF_PATH}", file=sys.stderr)
        return 1

    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    pdf_bytes = PDF_PATH.read_bytes()
    doc = fitz.open(stream=pdf_bytes, filetype="pdf")
    page_count = len(doc)

    failures: list[str] = []
    if page_count != EXPECTED_PAGES:
        failures.append(f"Expected {EXPECTED_PAGES} pages, found {page_count}")

    report_pages = []
    print(f"{'Page':<6} {'Trim (pt)':<13} {'Imgs':<5} {'Visible %':<10} {'Bleed Edges':<13} {'Text Blks':<10} {'Status'}")
    print("-" * 74)

    for idx, page in enumerate(doc, start=1):
        pr = page.rect
        photo_pct, bleed_edges, img_count = measure_exact_visible_photo_coverage(pdf_bytes, idx - 1)

        text_blocks = [b for b in page.get_text("blocks") if b[6] == 0 and b[4].strip()]
        text_overflow = False
        for b in text_blocks:
            x0, y0, x1, y1 = b[:4]
            if x0 < -2.0 or y0 < -2.0 or x1 > pr.width + 2.0 or y1 > pr.height + 2.0:
                text_overflow = True

        page_ok = True
        if photo_pct < MIN_PHOTO_COVERAGE_PCT:
            page_ok = False
            failures.append(f"Page {idx}: visible photo coverage {photo_pct:.1f}% < {MIN_PHOTO_COVERAGE_PCT:.1f}%")
        if len(bleed_edges) < 2:
            page_ok = False
            failures.append(f"Page {idx}: insufficient full-bleed edges ({bleed_edges})")
        if text_overflow:
            page_ok = False
            failures.append(f"Page {idx}: text block spills beyond trim")
        if not text_blocks:
            page_ok = False
            failures.append(f"Page {idx}: zero text blocks rendered")

        edges_str = "".join(bleed_edges) or "NONE"
        status = "PASS" if page_ok else "FAIL"
        print(
            f"{idx:<6d} {pr.width:.0f}x{pr.height:<9.0f} {img_count:<5d} "
            f"{photo_pct:6.1f}%    {edges_str:<13s} {len(text_blocks):<10d} {status}"
        )

        # Render 180-DPI preview PNG
        pix = page.get_pixmap(dpi=180, alpha=False)
        out_png = PREVIEW_DIR / f"mag_page_{idx:02d}.png"
        pix.save(out_png)

        report_pages.append(
            {
                "page": idx,
                "width_pt": round(pr.width, 2),
                "height_pt": round(pr.height, 2),
                "image_count": img_count,
                "visible_photo_coverage_pct": round(photo_pct, 2),
                "bleed_edges": bleed_edges,
                "text_blocks": len(text_blocks),
                "text_overflow": text_overflow,
                "pass": page_ok,
            }
        )

    doc.close()

    min_cov = min(p["visible_photo_coverage_pct"] for p in report_pages) if report_pages else 0.0
    avg_cov = sum(p["visible_photo_coverage_pct"] for p in report_pages) / len(report_pages) if report_pages else 0.0

    summary = {
        "pdf": PDF_PATH.name,
        "measurement_method": "exact_raster_dual_key_pixel_diff_72dpi",
        "page_count": page_count,
        "min_visible_photo_coverage_pct": round(min_cov, 2),
        "avg_visible_photo_coverage_pct": round(avg_cov, 2),
        "all_pages_ge_50pct": min_cov >= MIN_PHOTO_COVERAGE_PCT,
        "passed": len(failures) == 0,
        "failures": failures,
        "pages": report_pages,
    }
    AUDIT_JSON.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")

    print("-" * 74)
    print(f"Summary: min_visible_photo={min_cov:.1f}% | avg_visible_photo={avg_cov:.1f}% | pages={page_count} | passed={summary['passed']}")
    if failures:
        for f in failures:
            print(f"  [!] {f}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
