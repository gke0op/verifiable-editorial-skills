"""Exact clip-aware dual-key pixel-diff visible photo coverage auditor (PyMuPDF).

Replaces embedded image XObjects with two distinct solid key colors (magenta vs lime) in two
in-memory copies of the PDF and diffs the 72-DPI rasterizations. Unlike raw `get_image_rects(xref)`,
this respects CSS `object-fit: cover` clip paths, white gutters, and z-order occlusion.
"""

from __future__ import annotations

import io
from pathlib import Path
from PIL import Image
import fitz  # PyMuPDF


def _solid_png(rgb: tuple[int, int, int]) -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", (4, 4), rgb).save(buf, format="PNG")
    return buf.getvalue()


def measure_page_photo_coverage(pdf_bytes: bytes, page_index: int) -> tuple[float, list[str], int]:
    key_a = _solid_png((255, 0, 255))
    key_b = _solid_png((0, 255, 0))

    doc_a = fitz.open(stream=pdf_bytes, filetype="pdf")
    doc_b = fitz.open(stream=pdf_bytes, filetype="pdf")
    page_a = doc_a[page_index]
    page_b = doc_b[page_index]

    xrefs = sorted({img[0] for img in page_a.get_images(full=True) if page_a.get_image_rects(img[0])})
    if not xrefs:
        doc_a.close()
        doc_b.close()
        return 0.0, [], 0

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
    edges = {"L": 0, "R": 0, "T": 0, "B": 0}
    for y in range(h):
        row = y * w * 3
        for x in range(w):
            i = row + x * 3
            if sa[i] != sb[i] or sa[i + 1] != sb[i + 1] or sa[i + 2] != sb[i + 2]:
                changed += 1
                if x <= 1:
                    edges["L"] += 1
                if x >= w - 2:
                    edges["R"] += 1
                if y <= 1:
                    edges["T"] += 1
                if y >= h - 2:
                    edges["B"] += 1

    pct = (changed / total_px) * 100.0 if total_px else 0.0
    bleed = []
    if edges["L"] >= h * 0.25:
        bleed.append("L")
    if edges["R"] >= h * 0.25:
        bleed.append("R")
    if edges["T"] >= w * 0.25:
        bleed.append("T")
    if edges["B"] >= w * 0.25:
        bleed.append("B")
    return pct, sorted(bleed), len(xrefs)


def audit_coverage(
    pdf_path: Path | str,
    min_pct: float = 50.0,
    min_bleed_edges: int = 2,
    pages: set[int] | None = None,
) -> dict:
    """Audit visible clip-aware photo coverage across all pages (or selected 1-based page numbers)."""
    pdf_path = Path(pdf_path)
    pdf_bytes = pdf_path.read_bytes()
    doc = fitz.open(stream=pdf_bytes, filetype="pdf")
    n_pages = len(doc)
    doc.close()

    target_pages = pages if pages is not None else set(range(1, n_pages + 1))
    reports = []
    failures = []

    for idx in range(1, n_pages + 1):
        pct, bleed, img_cnt = measure_page_photo_coverage(pdf_bytes, idx - 1)
        enforced = idx in target_pages
        ok = True
        if enforced:
            if pct < min_pct:
                ok = False
                failures.append(f"Page {idx}: visible photo coverage {pct:.1f}% < {min_pct:.1f}%")
            if len(bleed) < min_bleed_edges:
                ok = False
                failures.append(f"Page {idx}: full-bleed edges {bleed} < {min_bleed_edges}")
        reports.append(
            {
                "page": idx,
                "enforced": enforced,
                "image_count": img_cnt,
                "visible_photo_pct": round(pct, 2),
                "bleed_edges": bleed,
                "passed": ok,
            }
        )

    enforced_pcts = [r["visible_photo_pct"] for r in reports if r["enforced"]]
    return {
        "gate": "photo_coverage",
        "pdf": pdf_path.name,
        "pages": n_pages,
        "enforced_pages": sorted(target_pages),
        "min_visible_pct": round(min(enforced_pcts), 2) if enforced_pcts else 0.0,
        "avg_visible_pct": round(sum(enforced_pcts) / len(enforced_pcts), 2) if enforced_pcts else 0.0,
        "passed": len(failures) == 0,
        "failures": failures,
        "page_reports": reports,
    }
