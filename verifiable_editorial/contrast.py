"""Background-sampled WCAG 2.1 PDF contrast auditor (PyMuPDF).

Clones the target PDF in memory, strips BT...ET text operators from page and Form XObject streams,
renders a 72-DPI text-free background raster, and samples the actual background pixels inside every
text span's bounding box. Works across light themes, dark modes, gradients, SVGs, and photos.
"""

from __future__ import annotations

import re
from pathlib import Path
import fitz  # PyMuPDF

BT_ET_RE = re.compile(rb"(?:^|[\s\r\n])BT(?=[\s\r\n]).*?[\s\r\n]ET(?=$|[\s\r\n])", re.DOTALL)


def int_to_rgb(c: int) -> tuple[int, int, int]:
    return ((c >> 16) & 255, (c >> 8) & 255, c & 255)


def rel_luminance(rgb: tuple[int, int, int]) -> float:
    def lin(v: int) -> float:
        s = v / 255.0
        return s / 12.92 if s <= 0.04045 else ((s + 0.055) / 1.055) ** 2.4

    return 0.2126 * lin(rgb[0]) + 0.7152 * lin(rgb[1]) + 0.0722 * lin(rgb[2])


def contrast_ratio(c1: tuple[int, int, int], c2: tuple[int, int, int]) -> float:
    l1, l2 = rel_luminance(c1), rel_luminance(c2)
    hi, lo = max(l1, l2), min(l1, l2)
    return (hi + 0.05) / (lo + 0.05)


def render_background_only(pdf_bytes: bytes, page_index: int, dpi: int = 72) -> fitz.Pixmap:
    """Return a raster of the page with all BT...ET text blocks stripped from page & Form XObjects."""
    doc = fitz.open(stream=pdf_bytes, filetype="pdf")
    page = doc[page_index]
    for cxref in page.get_contents():
        raw = doc.xref_stream(cxref)
        if raw and b"BT" in raw:
            doc.update_stream(cxref, BT_ET_RE.sub(b"\n", raw))
    for xobj in page.get_xobjects():
        try:
            raw = doc.xref_stream(xobj[0])
            if raw and b"BT" in raw:
                doc.update_stream(xobj[0], BT_ET_RE.sub(b"\n", raw))
        except Exception:
            pass
    pix = page.get_pixmap(dpi=dpi, alpha=False)
    doc.close()
    return pix


def audit_contrast(pdf_path: Path | str, min_normal_aa: float = 4.5, min_large_aa: float = 3.0) -> dict:
    """Audit WCAG 2.1 contrast of every text span against true rendered background pixels."""
    pdf_path = Path(pdf_path)
    pdf_bytes = pdf_path.read_bytes()
    doc = fitz.open(stream=pdf_bytes, filetype="pdf")

    pages_out = []
    total_violations = 0
    total_spans = 0
    worst_cr = 21.0

    for idx, page in enumerate(doc, start=1):
        bg = render_background_only(pdf_bytes, idx - 1, dpi=72)
        w, h, samples = bg.width, bg.height, bg.samples
        checked = 0
        min_cr = 21.0
        violations = []

        for block in page.get_text("dict").get("blocks", []):
            if block.get("type") != 0:
                continue
            for line in block.get("lines", []):
                for span in line.get("spans", []):
                    txt = span.get("text", "").strip()
                    if not txt or (len(txt) <= 1 and not txt.isalnum()):
                        continue
                    size = float(span.get("size", 10.0))
                    font_name = str(span.get("font", ""))
                    x0, y0, x1, y1 = span["bbox"]
                    ix0 = max(0, min(w - 1, int(round(x0))))
                    ix1 = max(ix0 + 1, min(w, int(round(x1))))
                    iy0 = max(0, min(h - 1, int(round(y0))))
                    iy1 = max(iy0 + 1, min(h, int(round(y1))))

                    rs, gs, bs = [], [], []
                    sx = max(1, (ix1 - ix0) // 12)
                    sy = max(1, (iy1 - iy0) // 6)
                    for py in range(iy0, iy1, sy):
                        row = py * w * 3
                        for px in range(ix0, ix1, sx):
                            i = row + px * 3
                            rs.append(samples[i])
                            gs.append(samples[i + 1])
                            bs.append(samples[i + 2])
                    if not rs:
                        continue
                    rs.sort()
                    gs.sort()
                    bs.sort()
                    mid = len(rs) // 2
                    bg_rgb = (rs[mid], gs[mid], bs[mid])
                    fg_rgb = int_to_rgb(int(span.get("color", 0)))
                    cr = contrast_ratio(fg_rgb, bg_rgb)

                    checked += 1
                    total_spans += 1
                    min_cr = min(min_cr, cr)
                    worst_cr = min(worst_cr, cr)

                    is_bold = bool(span.get("flags", 0) & 16) or ("Bold" in font_name) or ("SemiBold" in font_name)
                    req = min_large_aa if (size >= 18.0 or (size >= 14.0 and is_bold)) else min_normal_aa
                    if cr < req:
                        violations.append(
                            {
                                "page": idx,
                                "text": txt[:50],
                                "size_pt": round(size, 1),
                                "fg": f"#{fg_rgb[0]:02x}{fg_rgb[1]:02x}{fg_rgb[2]:02x}",
                                "bg": f"#{bg_rgb[0]:02x}{bg_rgb[1]:02x}{bg_rgb[2]:02x}",
                                "ratio": round(cr, 2),
                                "required": req,
                            }
                        )

        total_violations += len(violations)
        pages_out.append(
            {
                "page": idx,
                "checked_spans": checked,
                "min_contrast_ratio": round(min_cr, 2) if checked else 21.0,
                "violation_count": len(violations),
                "violations": violations,
            }
        )

    doc.close()
    return {
        "gate": "wcag_contrast",
        "pdf": pdf_path.name,
        "pages": len(pages_out),
        "total_spans": total_spans,
        "total_violations": total_violations,
        "worst_contrast_ratio": round(worst_cr, 2) if total_spans else 21.0,
        "passed": total_violations == 0,
        "page_reports": pages_out,
    }
