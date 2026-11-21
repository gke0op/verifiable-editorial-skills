---
name: premium-pdf-design
description: >-
  Institutional-grade PDF presentation (16:9 dark executive decks) and report (Letter light Swiss ivory)
  design system. Enforces verifiable open-data pipelines, 60-30-10 color balance, hairline Tufte ledgers,
  Minto Pyramid action titles, 300-DPI vector data visualization, safe Inter font registration,
  full-bleed canvas painting, and automated PyMuPDF visual QA auditing.
---

# Verifiable Institutional PDF Presentation & Data Visualization System

This skill pairs with `verifiable-pdf-pipeline` (data integrity) and `editorial-page-layout-guidelines` (grid geometry) to produce publication-grade **16:9 dark executive slide decks** and **Letter light Swiss-ivory institutional reports** inspired by McKinsey, Stripe Press, WEF, and *The Economist*.

---

## 1. Core Invariant: Substance Precedes Aesthetics

Every presentation or report built with this skill must obey the **8 Anti-Cheat Hard Rules** defined in `verifiable-pdf-pipeline/SKILL.md`:
1. **Zero-Handwritten-Data Air-Gap** — parse all numbers from immutable raw files in `data/raw/`.
2. **Reality & Invariant Compiler** — enforce Pydantic domain bounds and accounting identities.
3. **Anti-Circular Verification** — independent raw-file re-computation + Python AST check banning hardcoded literal assertions.
4. **Atomic Provenance Ledger** — every published scalar mapped 1:1 in `data/provenance_ledger.json`.
5. **Negative Capability & The Sacred "N/A"** — genuine upstream nulls render explicitly as `[N/A — Pending]` rather than fabricated proxies.
6. **Compilation Latch** — PDF compilers invoke `verify_integrity.py` and abort on non-zero exit.
7. **Category & Unit Guard** — never blend incommensurable scopes or test methods.
8. **Statutory Proof** — official gazette IDs required for any regulatory/tariff claim.

---

## 2. The 4 Golden Design Laws

### Law 1: The 60-30-10 Color Hierarchy (Light & Dark Modes)
- **Light Swiss Editorial Mode (Letter Reports):**
  - `60%` Canvas: Swiss Warm Ivory (`#fcfbf9`) — painted explicitly via `onPage`.
  - `30%` Scaffolding: Deep Navy (`#0f2b48`), Slate (`#334155`), Steel (`#64748b`), Hairlines (`#cbd5e1`), Subtle Tint (`#f1f5f9`).
  - `10%` Signal Accent: Cobalt (`#0284c7`), Amber (`#d97706`), Emerald (`#059669`), Signal Crimson (`#dc2626` — risk/surge only).
- **Dark Executive Mode (16:9 Slide Decks):**
  - `60%` Canvas: Deep Obsidian (`#0b0f19`) — **MUST be painted full-bleed in `onFirstPage`/`onLaterPages` BEFORE flowables render**, never relying on default white PDF paper!
  - `30%` Scaffolding: Subtle Tonal Band (`#111827`), Hairlines (`#1e293b`), Crisp White (`#f8fafc`), Silver Body (`#cbd5e1`), Muted Slate (`#94a3b8`).
  - `10%` Signal Accent: Electric Cobalt (`#38bdf8`), Amber (`#f59e0b`), Emerald (`#34d399`), Signal Crimson (`#f87171`).

### Law 2: Hairline & Whitespace Gravity (Zero Boxed Cards)
- Never trap metrics or prose inside heavy rectangular `BOX` strokes or `INNERGRID` web dashboard boxes.
- Group KPIs and callouts via **borderless tonal bands** (`#111827` dark / `#f1f5f9` light) crowned with a crisp **`1.2 pt` top accent hairline**, generous `12–16 pt` column gutters, and booktabs-style Tufte ledgers (zero vertical lines).

### Law 3: Minto Pyramid Action Titles
Every slide or report section opens with **one complete, assertive claim**, not a passive topic label:
- *Prohibited:* `"Global Emissions Trends"`
- *Required:* `"OECD-5 Cut Emissions -25.0%, Yet Emerging-3 Surged +235.8% to Lift Panel Totals to 23.52 Gt CO2e."`

### Law 4: Calibrated Vertical Fill Budgets + Visual Inspection
- **Letter Reports (`612×792 pt`):** `85%–92%` target vertical fill (`min >= 82%`).
- **16:9 Decks (`960×540 pt`):** `72%–88%` target vertical fill (`min >= 72%`).
- Never treat an automated pass as the final word: export 180-DPI PNG previews via `audit_pdf.py` and visually inspect every rendered page for label overlaps, widow headline wraps, and optical balance.

---

## 3. Institutional Data Visualization Recipes (300 DPI, Transparent)

Render all charts with `dpi=300`, `transparent=True`, top/right spines stripped, and theme-matched palettes (`dark` vs `light`):

1. **Dual-Panel Time Series + Rate Acceleration:** Historical monthly/daily trajectory with event shading and direct start/peak annotations paired with decadal/period rate bars.
2. **Stacked Mass-Balance Area + Indexed Trajectory:** Stacked flow volumes with **direct right-edge terminal labels** (zero separate floating legend boxes!) paired with `Base = 100` structural divergence lines.
3. **Decoupling Quadrant Scatter + Dumbbell Compression:** 2D growth-vs-outcome scatter with shaded target quadrant + leader arrows for tight clusters, paired with baseline-to-current horizontal dumbbells.
4. **Stephen Few Horizontal Bullet Graphs:** 3 qualitative background bands + primary performance bar + vertical amber baseline/target tick + right-aligned delta text (trimmed x-axis spine using `ax.spines["bottom"].set_bounds(...)`).
5. **In-Memory Headless Tufte Sparklines:** `46–66 pt × 13–16 pt` micro-lines rendered into `io.BytesIO()` buffers and embedded directly inside ReportLab table cells with semantic emerald/crimson terminal dots.
6. **Origin-Destination Matrix Heatmap & Ridgeline KDEs:** Sequential palette with contrast-switched dual typography or overlapping distribution ridges marking $P_{50}$ and $P_{90}$.

---

## 4. Production ReportLab Implementation Patterns

### 4.1 Full-Bleed Canvas Painting (Critical for Dark & Ivory Themes)
Always register an `onPage` callback so the canvas background paints **underneath** every flowable on every page:

```python
from reportlab.lib import colors

def paint_background(canv, _doc, bg_hex="#0b0f19", accent_hex="#38bdf8", page_w=960.0, page_h=540.0):
    canv.saveState()
    canv.setFillColor(colors.HexColor(bg_hex))
    canv.rect(0, 0, page_w, page_h, fill=1, stroke=0)
    if canv.getPageNumber() == 1:
        canv.setFillColor(colors.HexColor(accent_hex))
        canv.rect(0, page_h - 4, page_w, 4, fill=1, stroke=0)
    canv.restoreState()
```

### 4.2 Safe `Inter` TTF Discovery with Clean Fallback
Never hardcode `"Inter-SemiBold"` without registering the TTF first—use a helper that checks `INTER_FONT_DIR` and standard OS font paths and falls back cleanly to `Helvetica`:

```python
import os
from pathlib import Path
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

def register_editorial_fonts() -> dict[str, str]:
    search = [Path(os.environ["INTER_FONT_DIR"])] if os.environ.get("INTER_FONT_DIR") else []
    search += [Path.home() / "Library/Fonts", Path("/Library/Fonts"), Path("/usr/share/fonts/truetype/inter")]
    files = {"regular": "Inter-Regular.ttf", "semibold": "Inter-SemiBold.ttf",
             "bold": "Inter-Bold.ttf", "italic": "Inter-Italic.ttf", "bold_italic": "Inter-BoldItalic.ttf"}
    found = {r: d / f for d in search if d.is_dir() for r, f in files.items() if (d / f).is_file()}
    if {"regular", "bold", "italic", "bold_italic"}.issubset(found):
        for role, name in [("regular", "Inter-Regular"), ("bold", "Inter-Bold"),
                           ("italic", "Inter-Italic"), ("bold_italic", "Inter-BoldItalic")]:
            pdfmetrics.registerFont(TTFont(name, str(found[role])))
        semi = "Inter-Bold"
        if "semibold" in found:
            pdfmetrics.registerFont(TTFont("Inter-SemiBold", str(found["semibold"])))
            semi = "Inter-SemiBold"
        pdfmetrics.registerFontFamily("Inter-Regular", normal="Inter-Regular", bold="Inter-Bold",
                                      italic="Inter-Italic", boldItalic="Inter-BoldItalic")
        return {"regular": "Inter-Regular", "semibold": semi, "bold": "Inter-Bold",
                "italic": "Inter-Italic", "bold_italic": "Inter-BoldItalic", "mono": "Courier"}
    return {"regular": "Helvetica", "semibold": "Helvetica-Bold", "bold": "Helvetica-Bold",
            "italic": "Helvetica-Oblique", "bold_italic": "Helvetica-BoldOblique", "mono": "Courier"}
```

### 4.3 Two-Pass Running Headers & Dynamic Foliation
Use a subclass of `reportlab.pdfgen.canvas.Canvas` saving page state dicts in `showPage()` and stamping `"Page X of Y"` or `"Slide X / Y"` in `save()` (see `examples/reportlab_premium_template.py`).

---

## 5. Supporting References & Runnable Examples
- `references/design_laws_and_lexicon.md` — Extended design grammar, Gestalt spacing, and institutional style lexicon.
- `references/image_generation_recipes.md` — Fixed-spec visual continuity prompts for multi-asset cover/architecture illustrations.
- `examples/reportlab_premium_template.py` — Clean, runnable dual-mode (`--mode dark|light`) & dual-format (`--format 16x9|letter`) starter template with full-bleed background painting, safe Inter registration, hairline KPI strips, and Tufte ledgers.
