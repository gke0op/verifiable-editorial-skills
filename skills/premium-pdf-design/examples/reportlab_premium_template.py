#!/usr/bin/env python3
"""
Starter Template — Dual-Mode (Dark / Light) & Dual-Format (16:9 / Letter) ReportLab Builder.

Demonstrates all production design invariants cleanly and passes audit_pdf.py out of the box:
  - Full-bleed canvas background painting in onPage BEFORE flowables render
  - Two-pass EditorialNumberedCanvas for dynamic running headers & Page/Slide X of Y folios
  - Automatic Inter TTF discovery with graceful Helvetica fallback
  - Zero heavy boxed cards (borderless tonal bands + crisp hairline rules + Tufte ledgers)
  - Strict separation of layout template from verified domain data (pass --metrics JSON)

Usage:
  python3 reportlab_premium_template.py --mode dark --format 16x9 --out /tmp/preview_dark_16x9.pdf
  python3 reportlab_premium_template.py --mode light --format letter --out /tmp/preview_light_letter.pdf
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_RIGHT
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas
from reportlab.platypus import (
    PageBreak,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)

PALETTES = {
    "dark": {
        "bg": "#0b0f19",
        "band": "#111827",
        "rule": "#1e293b",
        "title": "#f8fafc",
        "body": "#cbd5e1",
        "muted": "#94a3b8",
        "accent": "#38bdf8",
        "emerald": "#34d399",
        "amber": "#f59e0b",
    },
    "light": {
        "bg": "#fcfbf9",
        "band": "#f1f5f9",
        "rule": "#cbd5e1",
        "title": "#0f172a",
        "body": "#334155",
        "muted": "#64748b",
        "accent": "#0284c7",
        "emerald": "#059669",
        "amber": "#d97706",
    },
}


def register_editorial_fonts() -> dict[str, str]:
    search: list[Path] = []
    if os.environ.get("INTER_FONT_DIR"):
        search.append(Path(os.environ["INTER_FONT_DIR"]))
    search.extend(
        [
            Path.home() / "Library" / "Fonts",
            Path("/Library/Fonts"),
            Path("/usr/share/fonts/truetype/inter"),
        ]
    )
    weight_files = {
        "regular": "Inter-Regular.ttf",
        "semibold": "Inter-SemiBold.ttf",
        "bold": "Inter-Bold.ttf",
        "italic": "Inter-Italic.ttf",
        "bold_italic": "Inter-BoldItalic.ttf",
    }
    found: dict[str, Path] = {}
    for d in search:
        if not d.is_dir():
            continue
        for role, fname in weight_files.items():
            if role not in found and (d / fname).is_file():
                found[role] = d / fname

    if {"regular", "bold", "italic", "bold_italic"}.issubset(found):
        pdfmetrics.registerFont(TTFont("Inter-Regular", str(found["regular"])))
        pdfmetrics.registerFont(TTFont("Inter-Bold", str(found["bold"])))
        pdfmetrics.registerFont(TTFont("Inter-Italic", str(found["italic"])))
        pdfmetrics.registerFont(TTFont("Inter-BoldItalic", str(found["bold_italic"])))
        semi = "Inter-Bold"
        if "semibold" in found:
            pdfmetrics.registerFont(TTFont("Inter-SemiBold", str(found["semibold"])))
            semi = "Inter-SemiBold"
        pdfmetrics.registerFontFamily(
            "Inter-Regular",
            normal="Inter-Regular",
            bold="Inter-Bold",
            italic="Inter-Italic",
            boldItalic="Inter-BoldItalic",
        )
        return {
            "regular": "Inter-Regular",
            "semibold": semi,
            "bold": "Inter-Bold",
            "italic": "Inter-Italic",
            "bold_italic": "Inter-BoldItalic",
            "mono": "Courier",
        }
    return {
        "regular": "Helvetica",
        "semibold": "Helvetica-Bold",
        "bold": "Helvetica-Bold",
        "italic": "Helvetica-Oblique",
        "bold_italic": "Helvetica-BoldOblique",
        "mono": "Courier",
    }


def make_canvas_class(
    fonts: dict[str, str],
    pal: dict[str, str],
    page_w: float,
    page_h: float,
    margin_x: float,
    is_widescreen: bool,
):
    class EditorialNumberedCanvas(canvas.Canvas):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, **kwargs)
            self._saved_states: list[dict] = []

        def showPage(self):
            self._saved_states.append(dict(self.__dict__))
            self._startPage()

        def save(self):
            total = len(self._saved_states)
            for state in self._saved_states:
                self.__dict__.update(state)
                self._draw_chrome(total)
                super().showPage()
            super().save()

        def _draw_chrome(self, total: int) -> None:
            self.saveState()
            if self._pageNumber > 1:
                hdr_y = page_h - (22 if is_widescreen else 36)
                rule_y = hdr_y - 7
                self.setFont(fonts["semibold"], 7.2)
                self.setFillColor(colors.HexColor(pal["muted"]))
                self.drawString(margin_x, hdr_y, "VERIFIABLE EDITORIAL TEMPLATE  //  LAYOUT PROOF")
                self.drawRightString(page_w - margin_x, hdr_y, "ZERO-MOCK PIPELINE READY")
                self.setStrokeColor(colors.HexColor(pal["rule"]))
                self.setLineWidth(0.55)
                self.line(margin_x, rule_y, page_w - margin_x, rule_y)

            foot_rule_y = 26 if is_widescreen else 44
            foot_txt_y = 13 if is_widescreen else 31
            self.setStrokeColor(colors.HexColor(pal["rule"]))
            self.setLineWidth(0.55)
            self.line(margin_x, foot_rule_y, page_w - margin_x, foot_rule_y)
            self.setFont(fonts["regular"], 7.0)
            self.setFillColor(colors.HexColor(pal["muted"]))
            self.drawString(margin_x, foot_txt_y, "PREMIUM-PDF-DESIGN  |  HAIRLINE & WHITESPACE GRAVITY SYSTEM")
            noun = "Slide" if is_widescreen else "Page"
            self.drawRightString(page_w - margin_x, foot_txt_y, f"{noun} {self._pageNumber} of {total}")
            self.restoreState()

    return EditorialNumberedCanvas


def build_template_pdf(
    output_path: Path,
    mode: str = "dark",
    fmt: str = "16x9",
    metrics_json: Path | None = None,
) -> None:
    pal = PALETTES[mode]
    fonts = register_editorial_fonts()
    is_widescreen = fmt == "16x9"

    page_w, page_h = (960.0, 540.0) if is_widescreen else letter
    margin_x = 42.0 if is_widescreen else 54.0
    margin_top = 38.0 if is_widescreen else 54.0
    margin_bot = 34.0 if is_widescreen else 54.0
    live_w = page_w - 2 * margin_x

    def paint_bg(canv: canvas.Canvas, _doc: SimpleDocTemplate) -> None:
        canv.saveState()
        canv.setFillColor(colors.HexColor(pal["bg"]))
        canv.rect(0, 0, page_w, page_h, fill=1, stroke=0)
        if canv.getPageNumber() == 1:
            canv.setFillColor(colors.HexColor(pal["accent"]))
            canv.rect(0, page_h - 4, page_w, 4, fill=1, stroke=0)
        canv.restoreState()

    styles = {
        "kicker": ParagraphStyle("kicker", fontName=fonts["bold"], fontSize=8.0, leading=10.5, textColor=colors.HexColor(pal["accent"]), spaceAfter=5),
        "title": ParagraphStyle("title", fontName=fonts["bold"], fontSize=26.0 if is_widescreen else 21.5, leading=32.0 if is_widescreen else 26.5, textColor=colors.HexColor(pal["title"]), spaceAfter=10),
        "action": ParagraphStyle("action", fontName=fonts["bold"], fontSize=15.0, leading=19.5, textColor=colors.HexColor(pal["title"]), spaceAfter=8),
        "deck": ParagraphStyle("deck", fontName=fonts["italic"], fontSize=11.0 if is_widescreen else 10.2, leading=16.0 if is_widescreen else 14.8, textColor=colors.HexColor(pal["body"]), spaceAfter=16),
        "body": ParagraphStyle("body", fontName=fonts["regular"], fontSize=8.8, leading=13.2, textColor=colors.HexColor(pal["body"]), spaceAfter=8),
        "col_h": ParagraphStyle("col_h", fontName=fonts["bold"], fontSize=8.5, leading=11.5, textColor=colors.HexColor(pal["title"]), spaceAfter=4),
        "col_b": ParagraphStyle("col_b", fontName=fonts["regular"], fontSize=8.3, leading=12.0, textColor=colors.HexColor(pal["body"]), spaceAfter=4),
        "quote": ParagraphStyle("quote", fontName=fonts["bold_italic"], fontSize=11.5, leading=16.0, textColor=colors.HexColor(pal["title"]), spaceAfter=8),
        "kpi_lbl": ParagraphStyle("kpi_lbl", fontName=fonts["bold"], fontSize=7.4, leading=9.5, textColor=colors.HexColor(pal["accent"]), spaceAfter=2),
        "kpi_val": ParagraphStyle("kpi_val", fontName=fonts["bold"], fontSize=21.0, leading=24.0, textColor=colors.HexColor(pal["title"]), spaceAfter=3),
        "kpi_sub": ParagraphStyle("kpi_sub", fontName=fonts["regular"], fontSize=7.8, leading=10.8, textColor=colors.HexColor(pal["muted"])),
        "th": ParagraphStyle("th", fontName=fonts["bold"], fontSize=7.5, leading=9.5, textColor=colors.HexColor(pal["accent"])),
        "th_r": ParagraphStyle("th_r", fontName=fonts["bold"], fontSize=7.5, leading=9.5, textColor=colors.HexColor(pal["accent"]), alignment=TA_RIGHT),
        "td": ParagraphStyle("td", fontName=fonts["regular"], fontSize=8.2, leading=11.2, textColor=colors.HexColor(pal["title"])),
        "td_r": ParagraphStyle("td_r", fontName=fonts["regular"], fontSize=8.2, leading=11.2, textColor=colors.HexColor(pal["body"]), alignment=TA_RIGHT),
        "na": ParagraphStyle("na", fontName=fonts["italic"], fontSize=7.8, leading=10.5, textColor=colors.HexColor(pal["amber"]), alignment=TA_RIGHT),
        "cap": ParagraphStyle("cap", fontName=fonts["italic"], fontSize=7.4, leading=10.2, textColor=colors.HexColor(pal["muted"])),
    }

    metric_count_label = "[Unbound Schema]"
    raw_file_count_label = "[Unbound Manifest]"
    if metrics_json and metrics_json.exists():
        payload = json.loads(metrics_json.read_text(encoding="utf-8"))
        metric_count_label = f"{len(payload.get('metrics', {}))} Audited"
        raw_file_count_label = f"{len(payload.get('metadata', {}).get('raw_file_hashes', {}))} SHA-256"

    doc = SimpleDocTemplate(
        str(output_path),
        pagesize=(page_w, page_h),
        leftMargin=margin_x,
        rightMargin=margin_x,
        topMargin=margin_top,
        bottomMargin=margin_bot,
    )

    # ------------------------------------------------------------------
    # PAGE / SLIDE 1: COVER HERO + KPI STRIP + 3-COL ARCHITECTURE + RECEIPT
    # ------------------------------------------------------------------
    story = [
        Spacer(1, 14 if is_widescreen else 18),
        Paragraph("STARTER LAYOUT PROOF  //  ZERO-MOCK ARCHITECTURE", styles["kicker"]),
        Paragraph("Institutional Verifiable Presentation &amp; Editorial Layout Starter", styles["title"]),
        Paragraph(
            "This runnable template validates full-bleed background painting, safe Inter font loading, "
            "hairline KPI ribbons, asymmetric grids, and Tufte minimal ledgers across Dark 16:9 and Light Letter modes. "
            "Pass --metrics data/summary_metrics.json to bind audited upstream datasets.",
            styles["deck"],
        ),
    ]

    kpis = [
        ("CANVAS MODE", f"{mode.upper()} / {fmt.upper()}", f"Full-bleed {pal['bg']} painted via onPage"),
        ("PROVENANCE LEDGER", metric_count_label, "Rule 4 atomic tuple coverage"),
        ("RAW MANIFEST", raw_file_count_label, "Rule 1 immutable data/raw/ seal"),
    ]
    kpi_row = [
        [Paragraph(lbl, styles["kpi_lbl"]), Paragraph(val, styles["kpi_val"]), Paragraph(sub, styles["kpi_sub"])]
        for lbl, val, sub in kpis
    ]
    kpi_tbl = Table([kpi_row], colWidths=[live_w / 3.0] * 3)
    kpi_tbl.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor(pal["band"])),
                ("LINEABOVE", (0, 0), (-1, 0), 1.2, colors.HexColor(pal["accent"])),
                ("LINEBELOW", (0, -1), (-1, -1), 0.6, colors.HexColor(pal["rule"])),
                ("TOPPADDING", (0, 0), (-1, -1), 14 if is_widescreen else 11),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 14 if is_widescreen else 11),
                ("LEFTPADDING", (0, 0), (-1, -1), 11),
                ("RIGHTPADDING", (0, 0), (-1, -1), 11),
            ]
        )
    )
    story.extend([kpi_tbl, Spacer(1, 30 if is_widescreen else 26)])

    # 3-Column Core Invariants Strip
    col_w = (live_w - 28) / 3.0
    pillars = [
        (
            "01  Zero-Mock Air-Gap",
            "No manual numeric dictionaries or hand-typed CSVs. Every value enters via deterministic ingestion into data/raw/ and is sealed with SHA-256 checksums.",
            pal["accent"],
        ),
        (
            "02  Hairline & Whitespace Gravity",
            "Replaces heavy bordered web-dashboard cards with open tonal ribbons, booktabs Tufte ledgers, generous column gutters, and direct chart labeling.",
            pal["emerald"],
        ),
        (
            "03  Fail-Closed Visual & Data QA",
            "Compilation latches behind verify_integrity.py (AST Rule 3 literal-assertion ban) and audit_pdf.py (PyMuPDF vertical fill and overflow gate).",
            pal["amber"],
        ),
    ]
    pillar_cells = [
        [
            Paragraph(f"<font color='{c}'>■</font>  {h}", styles["col_h"]),
            Paragraph(b, styles["col_b"]),
        ]
        for h, b, c in pillars
    ]
    pillar_tbl = Table([[pillar_cells[0], "", pillar_cells[1], "", pillar_cells[2]]], colWidths=[col_w, 14, col_w, 14, col_w])
    pillar_tbl.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LINEABOVE", (0, 0), (0, 0), 0.9, colors.HexColor(pal["rule"])),
                ("LINEABOVE", (2, 0), (2, 0), 0.9, colors.HexColor(pal["rule"])),
                ("LINEABOVE", (4, 0), (4, 0), 0.9, colors.HexColor(pal["rule"])),
                ("TOPPADDING", (0, 0), (-1, -1), 9),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 0),
            ]
        )
    )
    story.append(pillar_tbl)

    if not is_widescreen:
        story.extend(
            [
                Spacer(1, 24),
                Paragraph(
                    f"<font color='{pal['accent']}'><b>SUBSTANCE PRECEDES AESTHETICS</b></font> across every institutional "
                    "deliverable produced by this skill stack. A visually compelling layout containing a single unverified or "
                    "silently extrapolated number is rejected by the Phase 4 verification latch before typesetting begins.",
                    styles["body"],
                ),
                Paragraph(
                    "In Letter portrait mode (612 × 792 pt, 54 pt margins), pair lead narrative copy in a 310 pt primary "
                    "column with a 180 pt marginalia sidebar separated by a 14 pt gutter, targeting 85%–92% vertical fill.",
                    styles["body"],
                ),
                Spacer(1, 18),
                Paragraph(
                    "“Every displayed metric maps to a cryptographic hash, an exact raw-file locator, and an independent raw recomputation.”",
                    styles["quote"],
                ),
            ]
        )

    story.append(Spacer(1, 34 if is_widescreen else 28))
    receipt_rows = [
        [
            Paragraph("TEMPLATE TARGET", styles["th"]),
            Paragraph("TYPOGRAPHY", styles["th"]),
            Paragraph("VERTICAL FILL TARGET", styles["th"]),
            Paragraph("PROVENANCE STATUS", styles["th"]),
        ],
        [
            Paragraph(f"{fmt.upper()} ({page_w:.0f} × {page_h:.0f} pt)", styles["td"]),
            Paragraph(f"{fonts['regular']} / {fonts['bold']}", styles["td"]),
            Paragraph("72%–88% (16:9)" if is_widescreen else "85%–92% (Letter)", styles["td"]),
            Paragraph("Bound to JSON" if (metrics_json and metrics_json.exists()) else "Schema Proof Only", styles["td"]),
        ],
    ]
    rec_tbl = Table(receipt_rows, colWidths=[live_w * 0.25] * 4)
    rec_tbl.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LINEABOVE", (0, 0), (-1, 0), 0.75, colors.HexColor(pal["rule"])),
                ("LINEBELOW", (0, 0), (-1, 0), 0.4, colors.HexColor(pal["rule"])),
                ("LINEBELOW", (0, 1), (-1, 1), 0.75, colors.HexColor(pal["rule"])),
                ("TOPPADDING", (0, 0), (-1, -1), 6),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
                ("LEFTPADDING", (0, 0), (-1, -1), 3),
                ("RIGHTPADDING", (0, 0), (-1, -1), 3),
            ]
        )
    )
    story.extend([rec_tbl, PageBreak()])

    # ------------------------------------------------------------------
    # PAGE / SLIDE 2: TUFTE LEDGER + IMPLEMENTATION CHECKLIST
    # ------------------------------------------------------------------
    story.append(Paragraph("01 // TUFTE MINIMAL LEDGER & RULE 5 TRANSPARENCY PATTERN", styles["kicker"]))
    story.append(
        Paragraph(
            "Booktabs Hairlines Replace Heavy Dashboard Grids While Preserving Explicit [N/A] Upstream Gaps.",
            styles["action"],
        )
    )
    story.append(
        Paragraph(
            "Replace the schema rows below with records read directly from data/summary_metrics.json inside your "
            "Phase 4 latched compiler. See demos/global-carbon-telemetry/ for a full live-data implementation.",
            styles["body"],
        )
    )

    ledger_rows = [
        [
            Paragraph("PIPELINE PHASE", styles["th"]),
            Paragraph("ENFORCED INVARIANT", styles["th"]),
            Paragraph("SCRIPT MODULE", styles["th_r"]),
            Paragraph("MISSING DATA", styles["th_r"]),
        ],
        [
            Paragraph("Phase 1 — Ingestion", styles["td"]),
            Paragraph("Immutable data/raw/ + deduplicated sorted SHA-256 manifest", styles["td"]),
            Paragraph("fetch_data.py", styles["td_r"]),
            Paragraph("[N/A — Upstream Null]", styles["na"]),
        ],
        [
            Paragraph("Phase 2 — Reality Bounds", styles["td"]),
            Paragraph("Pydantic physical bounds + cross-field accounting identities", styles["td"]),
            Paragraph("validate_reality.py", styles["td_r"]),
            Paragraph("[N/A — Preserved]", styles["na"]),
        ],
        [
            Paragraph("Phase 3 — Provenance", styles["td"]),
            Paragraph("1:1 metric registration in data/provenance_ledger.json", styles["td"]),
            Paragraph("process_data.py", styles["td_r"]),
            Paragraph("Null Recorded", styles["td_r"]),
        ],
        [
            Paragraph("Phase 4 — Veto Gate", styles["td"]),
            Paragraph("Independent raw re-parse + Python AST Rule 3 linter", styles["td"]),
            Paragraph("verify_integrity.py", styles["td_r"]),
            Paragraph("Fail-Closed (Exit 1)", styles["td_r"]),
        ],
        [
            Paragraph("Phase 5 — Visual QA", styles["td"]),
            Paragraph("PyMuPDF text + image + vector bounding-box fill audit", styles["td"]),
            Paragraph("audit_pdf.py", styles["td_r"]),
            Paragraph("180-DPI PNG Review", styles["td_r"]),
        ],
    ]
    cw = [live_w * 0.23, live_w * 0.43, live_w * 0.16, live_w * 0.18]
    tbl = Table(ledger_rows, colWidths=cw)
    tbl.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("LINEABOVE", (0, 0), (-1, 0), 1.0, colors.HexColor(pal["accent"])),
                ("LINEBELOW", (0, 0), (-1, 0), 0.75, colors.HexColor(pal["accent"])),
                ("LINEBELOW", (0, 1), (-1, -2), 0.35, colors.HexColor(pal["rule"])),
                ("LINEBELOW", (0, -1), (-1, -1), 1.0, colors.HexColor(pal["accent"])),
                ("TOPPADDING", (0, 0), (-1, -1), 10.5 if is_widescreen else 9.0),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 10.5 if is_widescreen else 9.0),
                ("LEFTPADDING", (0, 0), (-1, -1), 4),
                ("RIGHTPADDING", (0, 0), (-1, -1), 4),
            ]
        )
    )
    story.append(tbl)
    story.append(Spacer(1, 8))
    story.append(
        Paragraph(
            "Table 1. Structural contract enforced by verifiable-pdf-pipeline before ReportLab typesetting unlocks.",
            styles["cap"],
        )
    )
    story.append(Spacer(1, 28 if is_widescreen else 36))

    # Bottom 2-column checklist anchoring vertical fill cleanly
    left_w = live_w * 0.60
    right_w = live_w - left_w - 16
    left_col = [
        Paragraph(f"<font color='{pal['accent']}'>■</font>  DEPLOYMENT INTEGRATION CHECKLIST", styles["col_h"]),
        Paragraph(
            "1. Copy scripts from verifiable-pdf-pipeline/templates/ into your project scripts/ directory.<br/>"
            "2. Configure upstream open-data URLs in fetch_data.py and Pydantic domain bounds in validate_reality.py.<br/>"
            "3. Emit 300-DPI transparent Matplotlib exhibits in dark or light palette to report/assets/.<br/>"
            "4. Latch compile_*.py behind verify_integrity.py and inspect all audit_pdf.py PNG previews.",
            styles["col_b"],
        ),
    ]
    right_col = [
        Paragraph(f"<font color='{pal['emerald']}'>■</font>  DESIGN TOKEN SUMMARY", styles["col_h"]),
        Paragraph(
            f"<b>Canvas:</b> {pal['bg']}<br/>"
            f"<b>Tonal Band:</b> {pal['band']}<br/>"
            f"<b>Hairline Rule:</b> {pal['rule']}<br/>"
            f"<b>Signal Accent:</b> {pal['accent']} / {pal['amber']}",
            styles["col_b"],
        ),
    ]
    bottom_tbl = Table([[left_col, "", right_col]], colWidths=[left_w, 16, right_w])
    bottom_tbl.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("BACKGROUND", (2, 0), (2, 0), colors.HexColor(pal["band"])),
                ("LINEABOVE", (0, 0), (0, 0), 0.9, colors.HexColor(pal["rule"])),
                ("LINEABOVE", (2, 0), (2, 0), 1.2, colors.HexColor(pal["accent"])),
                ("TOPPADDING", (0, 0), (-1, -1), 9),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 9),
                ("LEFTPADDING", (0, 0), (1, -1), 0),
                ("RIGHTPADDING", (0, 0), (1, -1), 0),
                ("LEFTPADDING", (2, 0), (2, 0), 10),
                ("RIGHTPADDING", (2, 0), (2, 0), 10),
            ]
        )
    )
    story.append(bottom_tbl)

    if not is_widescreen:
        story.extend(
            [
                Spacer(1, 32),
                Paragraph(
                    "“Clean editorial structure never competes with evidence; it strips away chrome so decision-makers see the verified signal immediately.”",
                    styles["quote"],
                ),
                Spacer(1, 18),
                Paragraph(
                    "<b>Next Step:</b> Wire your upstream fetch script in scripts/fetch_data.py, define physical &amp; accounting bounds "
                    "in scripts/validate_reality.py, and run scripts/verify_integrity.py as a hard subprocess gate inside your compiler.",
                    styles["body"],
                ),
            ]
        )

    canvas_cls = make_canvas_class(fonts, pal, page_w, page_h, margin_x, is_widescreen)
    doc.build(story, onFirstPage=paint_bg, onLaterPages=paint_bg, canvasmaker=canvas_cls)
    print(f"[OK] Built {mode}/{fmt} template proof at {output_path}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Build a dual-mode/dual-format editorial PDF starter proof.")
    parser.add_argument("--mode", choices=("dark", "light"), default="dark")
    parser.add_argument("--format", choices=("16x9", "letter"), default="16x9")
    parser.add_argument("--metrics", type=Path, default=None)
    parser.add_argument("--out", type=Path, default=Path("/tmp/premium_template_proof.pdf"))
    args = parser.parse_args()
    build_template_pdf(args.out, mode=args.mode, fmt=args.format, metrics_json=args.metrics)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
