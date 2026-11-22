#!/usr/bin/env python3
"""Master Quality Gate for BOTANICA VERIDICA:
1. True Background-Sampled WCAG 2.1 Contrast Audit (strips text streams in-memory to sample real bg pixels behind every span, including dark themes, gradients, and photos)
2. Dual-Key Pixel-Diff Exact Visible Photo/Plate Coverage Audit (strict >=50% gate on cover & all 6 species magazine plates)
3. Interactive PDF Bookmark Outline & Clickable Hyperlink Audit
4. Facing-Spread Contact-Sheet Assembler ([2|3], [4|5], [6|7], [8|9]) + 180-DPI Page Previews
"""

from __future__ import annotations

import io
import json
import re
import sys
from pathlib import Path
from PIL import Image, ImageDraw
import fitz  # PyMuPDF

ROOT = Path(__file__).resolve().parent.parent
PDF_PATH = ROOT / "report" / "BOTANICA_VERIDICA_MONOGRAPH.pdf"
PREVIEW_DIR = ROOT / "previews"
AUDIT_JSON = ROOT / "data" / "monograph_audit.json"

EXPECTED_PAGES = 10
# Cover + all 6 full-bleed species plates must carry >=50% visible photography/specimen plate
PLATE_PAGES = {1, 4, 5, 6, 7, 8, 9}
MIN_PLATE_COVERAGE_PCT = 50.0


def make_solid_png(rgb: tuple[int, int, int]) -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", (4, 4), rgb).save(buf, format="PNG")
    return buf.getvalue()


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


BT_ET_RE = re.compile(rb"(?:^|[\s\r\n])BT(?=[\s\r\n]).*?[\s\r\n]ET(?=$|[\s\r\n])", re.DOTALL)


def render_background_only_pixmap(pdf_bytes: bytes, page_index: int) -> fitz.Pixmap:
    """Clone PDF in memory, strip BT...ET text blocks from page & Form XObject streams, and render 72-DPI bg."""
    doc = fitz.open(stream=pdf_bytes, filetype="pdf")
    page = doc[page_index]

    # Strip text blocks from all content streams on this page
    for cxref in page.get_contents():
        raw = doc.xref_stream(cxref)
        if raw and b"BT" in raw:
            cleaned = BT_ET_RE.sub(b"\n", raw)
            doc.update_stream(cxref, cleaned)

    # Also strip text inside any Form XObjects referenced by the page (WeasyPrint embeds SVGs as Form XObjects)
    for xobj in page.get_xobjects():
        xref = xobj[0]
        try:
            raw = doc.xref_stream(xref)
            if raw and b"BT" in raw:
                cleaned = BT_ET_RE.sub(b"\n", raw)
                doc.update_stream(xref, cleaned)
        except Exception:
            pass

    pix = page.get_pixmap(dpi=72, alpha=False)
    doc.close()
    return pix


def audit_page_wcag_contrast(pdf_bytes: bytes, page: fitz.Page, page_index: int) -> dict:
    bg_pix = render_background_only_pixmap(pdf_bytes, page_index)
    w, h = bg_pix.width, bg_pix.height
    samples = bg_pix.samples

    checked_spans = 0
    violations: list[dict] = []
    min_ratio = 21.0

    for block in page.get_text("dict").get("blocks", []):
        if block.get("type") != 0:
            continue
        for line in block.get("lines", []):
            for span in line.get("spans", []):
                txt = span.get("text", "").strip()
                if not txt:
                    continue
                size = float(span.get("size", 10.0))
                font_name = str(span.get("font", ""))
                # Skip decorative hairline punctuation / tiny rotated marginal credits < 6.0pt from hard fail
                if len(txt) <= 1 and not txt.isalnum():
                    continue
                x0, y0, x1, y1 = span["bbox"]
                ix0 = max(0, min(w - 1, int(round(x0))))
                ix1 = max(ix0 + 1, min(w, int(round(x1))))
                iy0 = max(0, min(h - 1, int(round(y0))))
                iy1 = max(iy0 + 1, min(h, int(round(y1))))

                rs, gs, bs = [], [], []
                step_x = max(1, (ix1 - ix0) // 12)
                step_y = max(1, (iy1 - iy0) // 6)
                for py in range(iy0, iy1, step_y):
                    row = py * w * 3
                    for px in range(ix0, ix1, step_x):
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
                ratio = contrast_ratio(fg_rgb, bg_rgb)
                checked_spans += 1
                if ratio < min_ratio:
                    min_ratio = ratio

                is_bold = bool(span.get("flags", 0) & 16) or ("Bold" in font_name) or ("SemiBold" in font_name)
                is_large = size >= 18.0 or (size >= 14.0 and is_bold)
                # Standard WCAG 2.1 AA thresholds (3.0 large, 4.5 normal)
                req = 3.0 if is_large else 4.5
                if ratio < req:
                    violations.append(
                        {
                            "text": txt[:48],
                            "size_pt": round(size, 1),
                            "fg_hex": f"#{fg_rgb[0]:02x}{fg_rgb[1]:02x}{fg_rgb[2]:02x}",
                            "bg_hex": f"#{bg_rgb[0]:02x}{bg_rgb[1]:02x}{bg_rgb[2]:02x}",
                            "ratio": round(ratio, 2),
                            "required": req,
                            "bbox": [round(v, 1) for v in span["bbox"]],
                        }
                    )

    return {
        "checked_spans": checked_spans,
        "min_contrast_ratio": round(min_ratio, 2) if checked_spans else 21.0,
        "violation_count": len(violations),
        "violations": violations[:15],
    }


def measure_exact_visible_photo_coverage(pdf_bytes: bytes, page_index: int) -> tuple[float, list[str], int]:
    key_a = make_solid_png((255, 0, 255))
    key_b = make_solid_png((0, 255, 0))

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
    edge_hits = {"L": 0, "R": 0, "T": 0, "B": 0}
    for y in range(h):
        row = y * w * 3
        for x in range(w):
            i = row + x * 3
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


def build_facing_spread(left_png: Path, right_png: Path, out_png: Path) -> None:
    """Stitch two facing magazine pages with an archival desk mat and subtle spine gutter shadow."""
    im_l = Image.open(left_png).convert("RGB")
    im_r = Image.open(right_png).convert("RGB")
    pw, ph = im_l.size
    pad = 44
    canvas = Image.new("RGB", (pw * 2 + pad * 2, ph + pad * 2), (229, 224, 214))

    # Subtle outer drop frame
    draw = ImageDraw.Draw(canvas)
    draw.rectangle([pad - 2, pad - 2, pad + pw * 2 + 1, pad + ph + 1], outline=(188, 181, 170), width=2)

    canvas.paste(im_l, (pad, pad))
    canvas.paste(im_r, (pad + pw, pad))

    # Realistic soft spine gutter shadow across the center fold (width 28px)
    spine_x = pad + pw
    overlay = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    for dx in range(-18, 19):
        dist = abs(dx)
        alpha = int(56 * ((1.0 - dist / 19.0) ** 2.2))
        if alpha > 0:
            od.line([(spine_x + dx, pad), (spine_x + dx, pad + ph - 1)], fill=(20, 18, 16, alpha))
    od.line([(spine_x, pad), (spine_x, pad + ph - 1)], fill=(15, 14, 12, 85))

    final = Image.alpha_composite(canvas.convert("RGBA"), overlay).convert("RGB")
    # Downscale gently to crisp 1600px wide spread PNG so GitHub README loads fast
    scale = 1600 / final.width
    final = final.resize((1600, int(round(final.height * scale))), Image.Resampling.LANCZOS)
    final.save(out_png, optimize=True)


def main() -> int:
    if not PDF_PATH.exists():
        print(f"FAIL: PDF missing at {PDF_PATH}", file=sys.stderr)
        return 1

    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    pdf_bytes = PDF_PATH.read_bytes()
    doc = fitz.open(stream=pdf_bytes, filetype="pdf")
    page_count = len(doc)
    toc = doc.get_toc()

    failures: list[str] = []
    if page_count != EXPECTED_PAGES:
        failures.append(f"Expected {EXPECTED_PAGES} pages, found {page_count}")
    if len(toc) < 8:
        failures.append(f"Expected >= 8 interactive PDF bookmarks in outline, found {len(toc)}")

    total_links = 0
    total_wcag_violations = 0
    report_pages = []

    print(
        f"{'Pg':<4} {'Trim':<10} {'Imgs':<5} {'Photo%':<8} {'Bleed':<7} "
        f"{'Spans':<6} {'MinCR':<7} {'WCAG!':<6} {'Links':<6} {'Status'}"
    )
    print("-" * 78)

    for idx, page in enumerate(doc, start=1):
        pr = page.rect
        photo_pct, bleed_edges, img_count = measure_exact_visible_photo_coverage(pdf_bytes, idx - 1)
        wcag = audit_page_wcag_contrast(pdf_bytes, page, idx - 1)
        links = page.get_links()
        total_links += len(links)
        total_wcag_violations += wcag["violation_count"]

        text_blocks = [b for b in page.get_text("blocks") if b[6] == 0 and b[4].strip()]
        text_overflow = False
        for b in text_blocks:
            x0, y0, x1, y1 = b[:4]
            if x0 < -2.0 or y0 < -2.0 or x1 > pr.width + 2.0 or y1 > pr.height + 2.0:
                text_overflow = True

        page_ok = True
        if idx in PLATE_PAGES:
            if photo_pct < MIN_PLATE_COVERAGE_PCT:
                page_ok = False
                failures.append(f"Page {idx} (plate page): visible photo {photo_pct:.1f}% < {MIN_PLATE_COVERAGE_PCT:.1f}%")
            if len(bleed_edges) < 2:
                page_ok = False
                failures.append(f"Page {idx} (plate page): bleed edges {bleed_edges} < 2")
        if wcag["violation_count"] > 0:
            page_ok = False
            failures.append(
                f"Page {idx}: {wcag['violation_count']} WCAG contrast violation(s) "
                f"(worst={wcag['min_contrast_ratio']}:1, sample={wcag['violations'][0]})"
            )
        if text_overflow:
            page_ok = False
            failures.append(f"Page {idx}: text spills beyond trim")

        edges_str = "".join(bleed_edges) or "-"
        status = "PASS" if page_ok else "FAIL"
        print(
            f"{idx:<4d} {pr.width:.0f}x{pr.height:<6.0f} {img_count:<5d} {photo_pct:6.1f}%  {edges_str:<7s} "
            f"{wcag['checked_spans']:<6d} {wcag['min_contrast_ratio']:5.2f}x  {wcag['violation_count']:<6d} "
            f"{len(links):<6d} {status}"
        )

        # Render 180-DPI individual page preview
        pix = page.get_pixmap(dpi=180, alpha=False)
        pix.save(PREVIEW_DIR / f"page_{idx:02d}.png")

        report_pages.append(
            {
                "page": idx,
                "is_plate_page": idx in PLATE_PAGES,
                "width_pt": round(pr.width, 2),
                "height_pt": round(pr.height, 2),
                "image_count": img_count,
                "visible_photo_coverage_pct": round(photo_pct, 2),
                "bleed_edges": bleed_edges,
                "links_count": len(links),
                "text_overflow": text_overflow,
                "wcag": wcag,
                "pass": page_ok,
            }
        )

    doc.close()

    if total_links < 10:
        failures.append(f"Expected >= 10 clickable links (TOC + citations), found {total_links}")

    # Stitch 4 facing magazine spreads: [2|3], [4|5], [6|7], [8|9]
    spread_pairs = [(2, 3), (4, 5), (6, 7), (8, 9)]
    spread_files = []
    for l_pg, r_pg in spread_pairs:
        lp = PREVIEW_DIR / f"page_{l_pg:02d}.png"
        rp = PREVIEW_DIR / f"page_{r_pg:02d}.png"
        out_sp = PREVIEW_DIR / f"spread_{l_pg:02d}_{r_pg:02d}.png"
        if lp.exists() and rp.exists():
            build_facing_spread(lp, rp, out_sp)
            spread_files.append(out_sp.name)

    plate_covs = [p["visible_photo_coverage_pct"] for p in report_pages if p["is_plate_page"]]
    min_cr = min(p["wcag"]["min_contrast_ratio"] for p in report_pages)

    summary = {
        "pdf": PDF_PATH.name,
        "page_count": page_count,
        "bookmark_count": len(toc),
        "total_links": total_links,
        "plate_pages_min_photo_pct": round(min(plate_covs), 2) if plate_covs else 0.0,
        "plate_pages_avg_photo_pct": round(sum(plate_covs) / len(plate_covs), 2) if plate_covs else 0.0,
        "wcag_total_violations": total_wcag_violations,
        "wcag_worst_contrast_ratio": round(min_cr, 2),
        "facing_spreads_rendered": spread_files,
        "passed": len(failures) == 0,
        "failures": failures,
        "pages": report_pages,
    }
    AUDIT_JSON.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")

    print("-" * 78)
    print(
        f"Summary: pages={page_count} | bookmarks={len(toc)} | links={total_links} | "
        f"plate_min={summary['plate_pages_min_photo_pct']:.1f}% | wcag_violations={total_wcag_violations} "
        f"(min_cr={min_cr:.2f}:1) | spreads={len(spread_files)} | passed={summary['passed']}"
    )
    if failures:
        for f in failures:
            print(f"  [!] {f}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
