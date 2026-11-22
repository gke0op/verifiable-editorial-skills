"""Print Pre-Press Preflight & PDF/UA-1 Standards Certification Auditor (`vedit prepress`).

Checks five print-production & legal-accessibility invariants:
  1. Effective Placed Image DPI (`native_px / placed_inches`) — catches low-res upscaled plates honestly
  2. Embedded Font Subsetting — ensures zero unembedded fonts that fail on print-shop RIPs
  3. PDF Geometry Boxes (`/MediaBox`, `/TrimBox`, `/BleedBox`) — verifies real bleed margins on prepress PDFs
  4. Color-Space & Simulated CMYK Total Area Coverage (TAC <= 300%) — flags muddy over-inked shadows
  5. PDF/UA-1 Structural Tag Tree (`/StructTreeRoot`, `/MarkInfo`, `/Lang`, XMP `pdfuaid:part`, bookmarks)
     plus live `verapdf --flavour ua1` ISO 14289-1 certification when `verapdf` is installed on PATH.
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
from pathlib import Path
import fitz  # PyMuPDF

BOX_NUMS_RE = re.compile(r"[-+]?\d+(?:\.\d+)?")


def _parse_pdf_box(doc: fitz.Document, page_xref: int, key: str) -> list[float] | None:
    kind, val = doc.xref_get_key(page_xref, key)
    if kind == "null" or not val:
        return None
    nums = [float(x) for x in BOX_NUMS_RE.findall(val)]
    return nums if len(nums) == 4 else None


def _estimate_cmyk_tac_pct(r: int, g: int, b: int) -> float:
    """Standard UCR/GCR sRGB -> CMYK Total Area Coverage (%) estimate (0..400%).

    Uses realistic 80% Gray Component Replacement (typical ISO Coated v2 / GRACoL offset profile)
    so pure black (0,0,0) maps to ~260% rich black rather than naive 400%, while heavily saturated
    dark chromas reveal true ink buildup.
    """
    rf, gf, bf = r / 255.0, g / 255.0, b / 255.0
    k_raw = 1.0 - max(rf, gf, bf)
    if k_raw >= 0.999:
        # Neutral black under typical GCR offset separation (~60C 50M 50Y 100K = 260%)
        return 260.0
    c0 = (1.0 - rf - k_raw) / (1.0 - k_raw)
    m0 = (1.0 - gf - k_raw) / (1.0 - k_raw)
    y0 = (1.0 - bf - k_raw) / (1.0 - k_raw)
    # Apply 80% GCR
    gcr = 0.80
    k = k_raw * gcr
    rem = k_raw * (1.0 - gcr)
    c = min(1.0, c0 * (1.0 - k_raw) + rem)
    m = min(1.0, m0 * (1.0 - k_raw) + rem)
    y = min(1.0, y0 * (1.0 - k_raw) + rem)
    return (c + m + y + k) * 100.0


def _check_pdf_ua_structure(doc: fitz.Document) -> dict:
    """Pure-PyMuPDF structural PDF/UA-1 preflight (runs even without Java veraPDF)."""
    cat = doc.pdf_catalog()
    mark_kind, mark_val = doc.xref_get_key(cat, "MarkInfo")
    struct_kind, _ = doc.xref_get_key(cat, "StructTreeRoot")
    lang_kind, lang_val = doc.xref_get_key(cat, "Lang")
    vp_kind, vp_val = doc.xref_get_key(cat, "ViewerPreferences")
    xmp = doc.get_xml_metadata() or ""

    marked = mark_kind != "null" and ("true" in mark_val.lower())
    has_struct_tree = struct_kind != "null"
    has_lang = lang_kind != "null" and bool(lang_val.strip("() "))
    has_pdfua_xmp = "pdfuaid:part" in xmp
    has_title = bool((doc.metadata or {}).get("title")) or ("dc:title" in xmp)
    display_doc_title = vp_kind != "null" and ("displaydoctitle" in vp_val.lower())
    toc = doc.get_toc()

    issues = []
    if not marked:
        issues.append("Missing /MarkInfo << /Marked true >>")
    if not has_struct_tree:
        issues.append("Missing /StructTreeRoot semantic tag tree")
    if not has_lang:
        issues.append("Missing document /Lang attribute")
    if not has_title:
        issues.append("Missing PDF document title")

    return {
        "marked": marked,
        "has_struct_tree": has_struct_tree,
        "lang": lang_val.strip("() ") if has_lang else None,
        "has_title": has_title,
        "has_pdfua_xmp": has_pdfua_xmp,
        "display_doc_title": display_doc_title,
        "bookmark_count": len(toc),
        "issues": issues,
        "structural_pass": len(issues) == 0,
    }


def _run_verapdf_ua1(pdf_path: Path) -> dict | None:
    """Invoke official open-source `verapdf --flavour ua1 --format json` if installed on PATH."""
    vp_bin = shutil.which("verapdf")
    if not vp_bin:
        return None
    proc = subprocess.run(
        [vp_bin, "--flavour", "ua1", "--format", "json", str(pdf_path)],
        capture_output=True,
        text=True,
        check=False,
    )
    raw_out = proc.stdout.strip()
    if not raw_out:
        return {"available": True, "compliant": False, "error": proc.stderr.strip()[:300]}
    try:
        payload = json.loads(raw_out)
        jobs = payload.get("report", {}).get("jobs", [])
        if not jobs:
            return {"available": True, "compliant": False, "error": "Empty veraPDF jobs report"}
        vr = jobs[0].get("validationResult", [{}])[0]
        details = vr.get("details", {})
        failed_clauses = [
            {
                "clause": r.get("clause"),
                "testNumber": r.get("testNumber"),
                "description": (r.get("description") or "")[:140],
                "failedChecks": r.get("failedChecks"),
            }
            for r in details.get("ruleSummaries", [])
            if r.get("ruleStatus") == "FAILED"
        ]
        return {
            "available": True,
            "profile": vr.get("profileName"),
            "compliant": bool(vr.get("compliant", False)),
            "passed_rules": details.get("passedRules", 0),
            "failed_rules": details.get("failedRules", 0),
            "passed_checks": details.get("passedChecks", 0),
            "failed_checks": details.get("failedChecks", 0),
            "failed_rule_samples": failed_clauses[:10],
        }
    except Exception as exc:
        return {"available": True, "compliant": False, "error": f"veraPDF JSON parse error: {exc}"}


def audit_prepress(
    pdf_path: Path | str,
    min_dpi: float = 300.0,
    max_tac_pct: float = 300.0,
    require_bleed: bool = False,
    require_ua: bool = False,
    run_verapdf: bool = True,
) -> dict:
    """Run full print pre-press & ISO PDF/UA-1 certification audit."""
    pdf_path = Path(pdf_path)
    doc = fitz.open(pdf_path)
    failures: list[str] = []
    warnings: list[str] = []

    unembedded_fonts: set[str] = set()
    image_reports: list[dict] = []
    color_spaces: set[str] = set()
    bleed_reports: list[dict] = []
    peak_tac_pct = 0.0
    p99_tac_max = 0.0

    for idx, page in enumerate(doc, start=1):
        # 1. Embedded font check
        for f in page.get_fonts(full=True):
            # tuple: (xref, ext, type, basefont, name, encoding, ...)
            ext, ftype, basefont = f[1], f[2], f[3]
            if ftype != "Type3" and ext == "n/a":
                unembedded_fonts.add(basefont or f[4])

        # 2. Effective placed DPI + color space check (skip synthetic xref==0 soft-masks/gradients)
        for info in page.get_image_info(xrefs=True):
            xref = int(info.get("xref", 0))
            if xref <= 0:
                continue
            nw, nh = int(info.get("width", 0)), int(info.get("height", 0))
            cs = str(info.get("cs-name", "unknown"))
            color_spaces.add(cs)
            bbox = fitz.Rect(info["bbox"])
            placed_w_in = max(1e-4, bbox.width / 72.0)
            placed_h_in = max(1e-4, bbox.height / 72.0)
            eff_dpi = min(nw / placed_w_in, nh / placed_h_in) if nw and nh else 0.0
            image_reports.append(
                {
                    "page": idx,
                    "xref": xref,
                    "native_px": [nw, nh],
                    "placed_pt": [round(bbox.width, 1), round(bbox.height, 1)],
                    "effective_dpi": round(eff_dpi, 1),
                    "colorspace": cs,
                }
            )
            if eff_dpi < min_dpi:
                failures.append(
                    f"Page {idx} image xref={xref}: effective DPI {eff_dpi:.1f} < {min_dpi:.0f} "
                    f"({nw}x{nh}px placed at {bbox.width:.0f}x{bbox.height:.0f}pt)"
                )

        # 3. MediaBox / TrimBox / BleedBox geometry
        mb = _parse_pdf_box(doc, page.xref, "MediaBox") or [0.0, 0.0, page.rect.width, page.rect.height]
        tb = _parse_pdf_box(doc, page.xref, "TrimBox")
        bb = _parse_pdf_box(doc, page.xref, "BleedBox")
        has_bleed = False
        bleed_margin_pt = 0.0
        if tb and bb:
            margins = [tb[0] - bb[0], tb[1] - bb[1], bb[2] - tb[2], bb[3] - tb[3]]
            bleed_margin_pt = min(margins)
            has_bleed = bleed_margin_pt >= 5.0
        elif tb:
            margins = [tb[0] - mb[0], tb[1] - mb[1], mb[2] - tb[2], mb[3] - tb[3]]
            bleed_margin_pt = min(margins)
            has_bleed = bleed_margin_pt >= 5.0

        bleed_reports.append(
            {
                "page": idx,
                "mediabox": [round(v, 1) for v in mb],
                "trimbox": [round(v, 1) for v in tb] if tb else None,
                "bleedbox": [round(v, 1) for v in bb] if bb else None,
                "bleed_margin_pt": round(bleed_margin_pt, 1),
                "has_bleed": has_bleed,
            }
        )
        if require_bleed and not has_bleed:
            failures.append(f"Page {idx}: missing prepress bleed box (margin={bleed_margin_pt:.1f}pt < 5pt)")

        # 4. Simulated CMYK Total Area Coverage (TAC) at 36 DPI (fast full-page ink density scan)
        pix = page.get_pixmap(dpi=36, alpha=False)
        samples = pix.samples
        tacs = []
        for off in range(0, len(samples), 12):  # stride 4 pixels for speed
            t = _estimate_cmyk_tac_pct(samples[off], samples[off + 1], samples[off + 2])
            tacs.append(t)
        if tacs:
            tacs.sort()
            p_max = tacs[-1]
            p99 = tacs[int(0.99 * (len(tacs) - 1))]
            peak_tac_pct = max(peak_tac_pct, p_max)
            p99_tac_max = max(p99_tac_max, p99)

    if unembedded_fonts:
        failures.append(f"Unembedded font(s) found: {sorted(unembedded_fonts)}")
    if p99_tac_max > max_tac_pct:
        failures.append(f"Simulated CMYK 99th-percentile TAC {p99_tac_max:.1f}% > {max_tac_pct:.0f}% limit")
    if any("RGB" in cs.upper() for cs in color_spaces):
        warnings.append("Document contains RGB raster images (convert with ICC CMYK profile before offset plates)")

    # 5. PDF/UA-1 Structural Tag Tree + optional live veraPDF ISO 14289-1 validation
    ua_struct = _check_pdf_ua_structure(doc)
    doc.close()

    if require_ua and not ua_struct["structural_pass"]:
        for iss in ua_struct["issues"]:
            failures.append(f"PDF/UA structure: {iss}")

    verapdf_res = _run_verapdf_ua1(pdf_path) if run_verapdf else None
    if require_ua and verapdf_res and verapdf_res.get("available") and not verapdf_res.get("compliant"):
        failures.append(
            f"veraPDF ISO 14289-1 (PDF/UA-1) non-compliant: {verapdf_res.get('failed_rules')} failed rule(s)"
        )

    min_eff_dpi = min((r["effective_dpi"] for r in image_reports), default=None)

    return {
        "gate": "prepress",
        "pdf": pdf_path.name,
        "pages": len(bleed_reports),
        "image_count": len(image_reports),
        "min_effective_dpi": round(min_eff_dpi, 1) if min_eff_dpi is not None else None,
        "min_dpi_threshold": min_dpi,
        "unembedded_fonts": sorted(unembedded_fonts),
        "colorspaces": sorted(color_spaces),
        "bleed_all_pages": all(b["has_bleed"] for b in bleed_reports),
        "simulated_cmyk_p99_tac_pct": round(p99_tac_max, 1),
        "simulated_cmyk_peak_tac_pct": round(peak_tac_pct, 1),
        "pdf_ua_structure": ua_struct,
        "verapdf_ua1": verapdf_res,
        "warnings": warnings,
        "failures": failures,
        "passed": len(failures) == 0,
        "images": image_reports,
        "bleed_boxes": bleed_reports,
    }
