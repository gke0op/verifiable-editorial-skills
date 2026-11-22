"""Deterministic Geometric Collision, Clip-Path Slicing, Trim Overflow, Orphan-Headline & Texture-Energy Linter.

Operates strictly on compiled PDF bytes via PyMuPDF (HTML text + embedded SVG <text>) in ~50-150ms,
catching layout defects before visual review:
  1. Text-on-text bounding-box collisions (cross-line & same-line overlaps)
  2. Clip-path text slicing (comparing fitz.TEXT_CLIP vs unclipped character streams)
  3. Trim-box boundary overflow
  4. Wide-headline 1-word orphan wraps
  5. High-frequency photo-overlay background texture energy behind unprotected text
"""

from __future__ import annotations

import math
import re
import subprocess
from collections import Counter
from pathlib import Path
import fitz  # PyMuPDF

from .contrast import render_background_only

_TALL_GLYPHS = frozenset("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789bdfhiklt")
_DESC_GLYPHS = frozenset("gjpqy")
_ATTR_CACHE: dict[str, re.Pattern[str]] = {}


def _xml_attr(tag: str, key: str) -> str | None:
    pat = _ATTR_CACHE.get(key)
    if pat is None:
        pat = re.compile(rf'(?:^|\s){key}="([^"]*)"')
        _ATTR_CACHE[key] = pat
    m = pat.search(tag)
    return m.group(1) if m else None


def _extract_page_trace_xml(page: fitz.Page, pdf_path: Path | None = None, page_num: int = 1) -> str:
    """Capture MuPDF display-list trace XML in-memory via PyMuPDF C++ binding (zero subprocesses)."""
    try:
        from pymupdf import mupdf  # type: ignore

        buf = mupdf.FzBuffer(4096)
        out = mupdf.FzOutput(buf)
        dev = mupdf.fz_new_trace_device(out)
        dl = page.get_displaylist()
        mupdf.fz_run_display_list(
            dl.this,
            dev,
            mupdf.FzMatrix(),
            mupdf.FzRect(mupdf.FzRect.Fixed_INFINITE),
            mupdf.FzCookie(),
        )
        mupdf.fz_close_device(dev)
        out.fz_close_output()
        return buf.fz_string_from_buffer()
    except Exception:
        if pdf_path is not None:
            res = subprocess.run(
                ["mutool", "draw", "-F", "trace", str(pdf_path), str(page_num)],
                capture_output=True,
                text=True,
                check=False,
            )
            if res.returncode == 0:
                return res.stdout
        return ""


def _count_trace_clipped_alnum(trace_xml: str, page_w: float, page_h: float, tol: float = 1.0) -> list[dict]:
    """Audit every alphanumeric glyph's 4-corner ink core against the active `<clip_path>`/`<clip_text>` stack.

    Catches partial horizontal/vertical slicing (e.g. top half of letters cut off) that MuPDF's `stext`
    `TEXT_CLIP` stream misses because glyph origins remain inside the clip rectangle.
    """
    if not trace_xml:
        return []

    stack: list[tuple[float, float, float, float]] = [(0.0, 0.0, page_w, page_h)]
    in_clip_path = False
    in_clip_text = False
    clip_tf = [1.0, 0.0, 0.0, 1.0, 0.0, 0.0]
    clip_trm = [10.0, 0.0, 0.0, 10.0]
    cp_x0, cp_y0, cp_x1, cp_y1, cp_has = 1e18, 1e18, -1e18, -1e18, False

    in_text = False
    txt_tf = [1.0, 0.0, 0.0, 1.0, 0.0, 0.0]
    trm = [10.0, 0.0, 0.0, 10.0]

    sliced_chars: list[str] = []
    sbx0, sby0, sbx1, sby1 = 1e18, 1e18, -1e18, -1e18

    for m in re.finditer(r"<([^>]+)>", trace_xml):
        tag = m.group(1)
        self_closing = tag.endswith("/")

        if tag.startswith("clip_path"):
            in_clip_path = not self_closing
            tv = _xml_attr(tag, "transform")
            clip_tf = [float(v) for v in tv.split()] if tv else [1.0, 0.0, 0.0, 1.0, 0.0, 0.0]
            cp_x0, cp_y0, cp_x1, cp_y1, cp_has = 1e18, 1e18, -1e18, -1e18, False
            if self_closing:
                stack.append(stack[-1])
        elif tag == "/clip_path":
            in_clip_path = False
            px0, py0, px1, py1 = stack[-1]
            stack.append((max(px0, cp_x0), max(py0, cp_y0), min(px1, cp_x1), min(py1, cp_y1)) if cp_has else stack[-1])
        elif tag.startswith("clip_text"):
            in_clip_text = not self_closing
            tv = _xml_attr(tag, "transform")
            clip_tf = [float(v) for v in tv.split()] if tv else [1.0, 0.0, 0.0, 1.0, 0.0, 0.0]
            clip_trm = [10.0, 0.0, 0.0, 10.0]
            cp_x0, cp_y0, cp_x1, cp_y1, cp_has = 1e18, 1e18, -1e18, -1e18, False
            if self_closing:
                stack.append(stack[-1])
        elif tag == "/clip_text":
            in_clip_text = False
            px0, py0, px1, py1 = stack[-1]
            stack.append((max(px0, cp_x0), max(py0, cp_y0), min(px1, cp_x1), min(py1, cp_y1)) if cp_has else stack[-1])
        elif tag.startswith(("clip_stroke_path", "clip_image_mask")):
            stack.append(stack[-1])
        elif tag.startswith("pop_clip"):
            if len(stack) > 1:
                stack.pop()
        elif in_clip_path:
            if tag.startswith(("moveto ", "lineto ")):
                xv, yv = _xml_attr(tag, "x"), _xml_attr(tag, "y")
                if xv is not None and yv is not None:
                    x, y = float(xv), float(yv)
                    tx = clip_tf[0] * x + clip_tf[2] * y + clip_tf[4]
                    ty = clip_tf[1] * x + clip_tf[3] * y + clip_tf[5]
                    cp_x0, cp_y0 = min(cp_x0, tx), min(cp_y0, ty)
                    cp_x1, cp_y1 = max(cp_x1, tx), max(cp_y1, ty)
                    cp_has = True
            elif tag.startswith("curveto "):
                for ki in ("1", "2", "3"):
                    xv, yv = _xml_attr(tag, "x" + ki), _xml_attr(tag, "y" + ki)
                    if xv is not None and yv is not None:
                        x, y = float(xv), float(yv)
                        tx = clip_tf[0] * x + clip_tf[2] * y + clip_tf[4]
                        ty = clip_tf[1] * x + clip_tf[3] * y + clip_tf[5]
                        cp_x0, cp_y0 = min(cp_x0, tx), min(cp_y0, ty)
                        cp_x1, cp_y1 = max(cp_x1, tx), max(cp_y1, ty)
                        cp_has = True
        elif in_clip_text:
            if tag.startswith("span "):
                trv = _xml_attr(tag, "trm")
                clip_trm = [float(v) for v in trv.split()] if trv else [10.0, 0.0, 0.0, 10.0]
            elif tag.startswith("g "):
                xv, yv = _xml_attr(tag, "x"), _xml_attr(tag, "y")
                if xv is not None and yv is not None:
                    x, y = float(xv), float(yv)
                    av = _xml_attr(tag, "adv")
                    adv = float(av) if av is not None else 0.5
                    ox = clip_tf[0] * x + clip_tf[2] * y + clip_tf[4]
                    oy = clip_tf[1] * x + clip_tf[3] * y + clip_tf[5]
                    dx = clip_tf[0] * (adv * clip_trm[0]) + clip_tf[2] * (adv * clip_trm[1])
                    dy = clip_tf[1] * (adv * clip_trm[0]) + clip_tf[3] * (adv * clip_trm[1])
                    ax = clip_tf[0] * clip_trm[2] + clip_tf[2] * clip_trm[3]
                    ay = clip_tf[1] * clip_trm[2] + clip_tf[3] * clip_trm[3]
                    for u in (0.0, 1.0):
                        for v in (-0.25, 0.85):
                            px, py = ox + u * dx + v * ax, oy + u * dy + v * ay
                            cp_x0, cp_y0 = min(cp_x0, px), min(cp_y0, py)
                            cp_x1, cp_y1 = max(cp_x1, px), max(cp_y1, py)
                            cp_has = True
        elif tag.startswith(("fill_text", "stroke_text")):
            in_text = not self_closing
            tv = _xml_attr(tag, "transform")
            txt_tf = [float(v) for v in tv.split()] if tv else [1.0, 0.0, 0.0, 1.0, 0.0, 0.0]
            trm = [10.0, 0.0, 0.0, 10.0]
        elif tag in ("/fill_text", "/stroke_text"):
            in_text = False
        elif in_text and tag.startswith("span "):
            trv = _xml_attr(tag, "trm")
            trm = [float(v) for v in trv.split()] if trv else [10.0, 0.0, 0.0, 10.0]
        elif in_text and len(stack) > 1 and tag.startswith("g "):
            uval = _xml_attr(tag, "unicode")
            if not uval or len(uval) != 1 or not uval.isalnum():
                continue
            xv, yv = _xml_attr(tag, "x"), _xml_attr(tag, "y")
            if xv is None or yv is None:
                continue
            x, y = float(xv), float(yv)
            av = _xml_attr(tag, "adv")
            adv = float(av) if av is not None else 0.5
            ox = txt_tf[0] * x + txt_tf[2] * y + txt_tf[4]
            oy = txt_tf[1] * x + txt_tf[3] * y + txt_tf[5]
            dx = txt_tf[0] * (adv * trm[0]) + txt_tf[2] * (adv * trm[1])
            dy = txt_tf[1] * (adv * trm[0]) + txt_tf[3] * (adv * trm[1])
            ax = txt_tf[0] * trm[2] + txt_tf[2] * trm[3]
            ay = txt_tf[1] * trm[2] + txt_tf[3] * trm[3]
            v0 = -0.14 if uval in _DESC_GLYPHS else 0.05
            v1 = 0.62 if uval in _TALL_GLYPHS else 0.48
            pts = (
                (ox + 0.15 * dx + v0 * ax, oy + 0.15 * dy + v0 * ay),
                (ox + 0.85 * dx + v0 * ax, oy + 0.85 * dy + v0 * ay),
                (ox + 0.15 * dx + v1 * ax, oy + 0.15 * dy + v1 * ay),
                (ox + 0.85 * dx + v1 * ax, oy + 0.85 * dy + v1 * ay),
            )
            gx0 = min(p[0] for p in pts)
            gx1 = max(p[0] for p in pts)
            gy0 = min(p[1] for p in pts)
            gy1 = max(p[1] for p in pts)
            mx = 0.5 * (gx0 + gx1)
            my = 0.5 * (gy0 + gy1)
            if 0.0 <= mx <= page_w and 0.0 <= my <= page_h:
                cx0, cy0, cx1, cy1 = stack[-1]
                if gx0 < cx0 - tol or gx1 > cx1 + tol or gy0 < cy0 - tol or gy1 > cy1 + tol:
                    sliced_chars.append(uval)
                    sbx0, sby0 = min(sbx0, gx0), min(sby0, gy0)
                    sbx1, sby1 = max(sbx1, gx1), max(sby1, gy1)

    if not sliced_chars:
        return []
    return [
        {
            "unclipped_text": "".join(sliced_chars[:50]),
            "visible_chars": 0,
            "total_chars": len(sliced_chars),
            "bbox": [round(sbx0, 1), round(sby0, 1), round(sbx1, 1), round(sby1, 1)],
        }
    ]


def _alnum(s: str) -> str:
    return "".join(ch for ch in s if ch.isalnum())


def _extract_spans(page: fitz.Page, clipped: bool = True) -> list[dict]:
    flags = (fitz.TEXTFLAGS_DICT | fitz.TEXT_ACCURATE_BBOXES) if clipped else 0
    spans: list[dict] = []
    td = page.get_text("dict", flags=flags)
    for b_idx, block in enumerate(td.get("blocks", [])):
        if block.get("type") != 0:
            continue
        for l_idx, line in enumerate(block.get("lines", [])):
            direction = tuple(round(v, 2) for v in line.get("dir", (1.0, 0.0)))
            for s_idx, span in enumerate(line.get("spans", [])):
                txt = span.get("text", "").strip()
                if not txt:
                    continue
                x0, y0, x1, y1 = span["bbox"]
                spans.append(
                    {
                        "line_key": (b_idx, l_idx),
                        "span_idx": s_idx,
                        "text": txt,
                        "size": float(span.get("size", 10.0)),
                        "font": str(span.get("font", "")),
                        "dir": direction,
                        "bbox": (x0, y0, x1, y1),
                    }
                )
    return spans


def _detect_collisions(spans: list[dict]) -> list[dict]:
    collisions: list[dict] = []
    n = len(spans)
    for i in range(n):
        a = spans[i]
        ax0, ay0, ax1, ay1 = a["bbox"]
        aw, ah = ax1 - ax0, ay1 - ay0
        if aw < 1.0 or ah < 1.0:
            continue
        # Only compare spans with matching orientation (horizontal vs horizontal, vertical vs vertical)
        # Shrink slightly inward vertically (20%) to ignore normal tall-ascender line box touching
        ay_pad = ah * 0.20
        ax_pad = min(1.0, aw * 0.10)
        ca0, cb0, ca1, cb1 = ax0 + ax_pad, ay0 + ay_pad, ax1 - ax_pad, ay1 - ay_pad
        if ca1 <= ca0 or cb1 <= cb0:
            continue

        for j in range(i + 1, n):
            b = spans[j]
            if a["dir"] != b["dir"]:
                continue
            bx0, by0, bx1, by1 = b["bbox"]
            bw, bh = bx1 - bx0, by1 - by0
            if bw < 1.0 or bh < 1.0:
                continue

            by_pad = bh * 0.20
            bx_pad = min(1.0, bw * 0.10)
            da0, db0, da1, db1 = bx0 + bx_pad, by0 + by_pad, bx1 - bx_pad, by1 - by_pad
            if da1 <= da0 or db1 <= db0:
                continue

            iw = min(ca1, da1) - max(ca0, da0)
            ih = min(cb1, db1) - max(cb0, db0)
            if iw <= 0 or ih <= 0:
                continue

            same_line = a["line_key"] == b["line_key"]
            if same_line:
                # Inline styled spans (e.g. italic + roman) can kiss slightly at kerning edges;
                # flag real overlap > 3.5pt horizontally and > 35% of shorter glyph height
                if iw > 3.5 and ih > 0.35 * min(ah, bh):
                    collisions.append(
                        {
                            "kind": "same_line_overlap",
                            "text_a": a["text"][:40],
                            "text_b": b["text"][:40],
                            "overlap_pt": [round(iw, 1), round(ih, 1)],
                        }
                    )
            else:
                if iw > 2.5 and ih > 2.5:
                    collisions.append(
                        {
                            "kind": "cross_line_overlap",
                            "text_a": a["text"][:40],
                            "text_b": b["text"][:40],
                            "overlap_pt": [round(iw, 1), round(ih, 1)],
                        }
                    )
    return collisions


def _detect_clipping(page: fitz.Page, pdf_path: Path | None = None, page_num: int = 1) -> list[dict]:
    """Compare unclipped vs PDF-clip-path-clipped text AND audit per-glyph ink cores against active clip stack."""
    vis_spans = _extract_spans(page, clipped=True)
    raw_spans = _extract_spans(page, clipped=False)

    vis_chars = Counter(_alnum("".join(s["text"] for s in vis_spans)))
    raw_chars = Counter(_alnum("".join(s["text"] for s in raw_spans)))
    missing = raw_chars - vis_chars

    clipped_items: list[dict] = []
    if missing:
        # Pinpoint exact raw spans whose visible intersection lost characters
        for rs in raw_spans:
            r_al = _alnum(rs["text"])
            if not r_al:
                continue
            rx0, ry0, rx1, ry1 = rs["bbox"]
            matched_vis = []
            for vs in vis_spans:
                vx0, vy0, vx1, vy1 = vs["bbox"]
                if min(rx1, vx1) - max(rx0, vx0) > 0.5 and min(ry1, vy1) - max(ry0, vy0) > 0.5:
                    matched_vis.append(vs["text"])
            v_al = _alnum("".join(matched_vis))
            if len(v_al) < len(r_al):
                clipped_items.append(
                    {
                        "unclipped_text": rs["text"][:50],
                        "visible_chars": len(v_al),
                        "total_chars": len(r_al),
                        "bbox": [round(v, 1) for v in rs["bbox"]],
                    }
                )

    if not clipped_items:
        trace_xml = _extract_page_trace_xml(page, pdf_path=pdf_path, page_num=page_num)
        clipped_items.extend(_count_trace_clipped_alnum(trace_xml, page.rect.width, page.rect.height))

    return clipped_items


def _detect_trim_overflow(spans: list[dict], pr: fitz.Rect, eps: float = 1.5) -> list[dict]:
    out = []
    for s in spans:
        x0, y0, x1, y1 = s["bbox"]
        if x0 < -eps or y0 < -eps or x1 > pr.width + eps or y1 > pr.height + eps:
            out.append({"text": s["text"][:45], "bbox": [round(v, 1) for v in s["bbox"]]})
    return out


def _detect_headline_orphans(spans: list[dict]) -> list[dict]:
    """Flag wide display headlines (>=20pt, first line >=260pt wide) wrapping a single short orphan word onto the final line."""
    # Group horizontal spans into visual lines by y-center & font size
    h_spans = [s for s in spans if s["dir"] == (1.0, 0.0) and s["size"] >= 20.0]
    if not h_spans:
        return []
    h_spans.sort(key=lambda s: (round(s["bbox"][1], 1), s["bbox"][0]))

    lines: list[dict] = []
    for s in h_spans:
        x0, y0, x1, y1 = s["bbox"]
        yc = (y0 + y1) / 2.0
        if lines and abs(yc - lines[-1]["yc"]) < s["size"] * 0.45 and abs(s["size"] - lines[-1]["size"]) < 2.0:
            lines[-1]["text"] += " " + s["text"]
            lines[-1]["x0"] = min(lines[-1]["x0"], x0)
            lines[-1]["x1"] = max(lines[-1]["x1"], x1)
            lines[-1]["y1"] = max(lines[-1]["y1"], y1)
        else:
            lines.append({"text": s["text"], "size": s["size"], "x0": x0, "x1": x1, "y0": y0, "y1": y1, "yc": yc})

    # Group consecutive lines of matching font size into headline blocks (excludes drop caps beneath headlines)
    blocks: list[list[dict]] = []
    for ln in lines:
        if blocks:
            prev = blocks[-1][-1]
            v_gap = ln["y0"] - prev["y1"]
            if (
                -4.0 <= v_gap <= prev["size"] * 0.65
                and abs(ln["x0"] - prev["x0"]) < 45.0
                and abs(ln["size"] - prev["size"]) < 2.0
            ):
                blocks[-1].append(ln)
                continue
        blocks.append([ln])

    orphans: list[dict] = []
    for blk in blocks:
        if len(blk) < 2:
            continue
        w0 = blk[0]["x1"] - blk[0]["x0"]
        last = blk[-1]
        w_last = last["x1"] - last["x0"]
        words_last = [w for w in last["text"].split() if re.search(r"[A-Za-z0-9]", w)]
        if w0 >= 260.0 and len(words_last) == 1 and len(words_last[0]) <= 15 and (w_last / max(1.0, w0)) < 0.38:
            orphans.append(
                {
                    "first_line": blk[0]["text"][:50],
                    "orphan_word": words_last[0],
                    "width_ratio": round(w_last / w0, 2),
                }
            )
    return orphans


def _measure_texture_energy(bg_pix: fitz.Pixmap, spans: list[dict], max_rms: float = 55.0) -> tuple[float, list[dict]]:
    """Compute local luminance gradient RMS behind text spans to flag busy/cluttered photo textures."""
    w, h, samples = bg_pix.width, bg_pix.height, bg_pix.samples
    worst_rms = 0.0
    noisy: list[dict] = []

    def luma(px: int, py: int) -> float:
        i = (py * w + px) * 3
        return 0.299 * samples[i] + 0.587 * samples[i + 1] + 0.114 * samples[i + 2]

    for s in spans:
        if s["size"] >= 22.0 or len(s["text"]) <= 2:
            continue
        x0, y0, x1, y1 = s["bbox"]
        ix0 = max(1, min(w - 2, int(round(x0))))
        ix1 = max(ix0 + 1, min(w - 1, int(round(x1))))
        iy0 = max(1, min(h - 2, int(round(y0))))
        iy1 = max(iy0 + 1, min(h - 1, int(round(y1))))
        if (ix1 - ix0) < 6 or (iy1 - iy0) < 4:
            continue

        sq_sum = 0.0
        cnt = 0
        sx = max(1, (ix1 - ix0) // 16)
        sy = max(1, (iy1 - iy0) // 6)
        for py in range(iy0, iy1, sy):
            for px in range(ix0, ix1, sx):
                gx = luma(px + 1, py) - luma(px - 1, py)
                gy = luma(px, py + 1) - luma(px, py - 1)
                sq_sum += (gx * gx + gy * gy) * 0.25
                cnt += 1
        if cnt == 0:
            continue
        rms = math.sqrt(sq_sum / cnt)
        if rms > worst_rms:
            worst_rms = rms
        if rms > max_rms:
            noisy.append({"text": s["text"][:40], "bg_edge_rms": round(rms, 1)})

    return round(worst_rms, 1), noisy


def audit_geometry(
    pdf_path: Path | str,
    check_orphans: bool = True,
    max_bg_edge_rms: float = 55.0,
) -> dict:
    """Run full deterministic geometric layout, collision, clip-path, orphan, and texture audit."""
    pdf_path = Path(pdf_path)
    pdf_bytes = pdf_path.read_bytes()
    doc = fitz.open(stream=pdf_bytes, filetype="pdf")

    page_reports = []
    tot_collisions = 0
    tot_clipped = 0
    tot_overflow = 0
    tot_orphans = 0
    tot_noisy = 0

    for idx, page in enumerate(doc, start=1):
        vis_spans = _extract_spans(page, clipped=True)
        collisions = _detect_collisions(vis_spans)
        clipped = _detect_clipping(page, pdf_path=pdf_path, page_num=idx)
        overflow = _detect_trim_overflow(vis_spans, page.rect)
        orphans = _detect_headline_orphans(vis_spans) if check_orphans else []
        bg = render_background_only(pdf_bytes, idx - 1, dpi=72)
        worst_rms, noisy = _measure_texture_energy(bg, vis_spans, max_rms=max_bg_edge_rms)

        tot_collisions += len(collisions)
        tot_clipped += len(clipped)
        tot_overflow += len(overflow)
        tot_orphans += len(orphans)
        tot_noisy += len(noisy)

        page_ok = (len(collisions) == 0 and len(clipped) == 0 and len(overflow) == 0 and len(orphans) == 0 and len(noisy) == 0)
        page_reports.append(
            {
                "page": idx,
                "spans": len(vis_spans),
                "collisions": collisions,
                "clipped": clipped,
                "trim_overflow": overflow,
                "headline_orphans": orphans,
                "worst_bg_edge_rms": worst_rms,
                "noisy_overlays": noisy,
                "passed": page_ok,
            }
        )

    doc.close()
    passed = (tot_collisions == 0 and tot_clipped == 0 and tot_overflow == 0 and tot_orphans == 0 and tot_noisy == 0)
    return {
        "gate": "geometry",
        "pdf": pdf_path.name,
        "pages": len(page_reports),
        "total_collisions": tot_collisions,
        "total_clipped": tot_clipped,
        "total_trim_overflow": tot_overflow,
        "total_headline_orphans": tot_orphans,
        "total_noisy_overlays": tot_noisy,
        "passed": passed,
        "page_reports": page_reports,
    }
