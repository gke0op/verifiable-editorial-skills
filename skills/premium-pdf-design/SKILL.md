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

Every presentation or report built with this skill must obey the **11 Anti-Cheat Hard Rules** defined in `verifiable-pdf-pipeline/SKILL.md`:
1. **Zero-Handwritten-Data Air-Gap** — parse all numbers from immutable raw files in `data/raw/`.
2. **Reality & Invariant Compiler** — enforce Pydantic/Zig domain bounds and accounting identities.
3. **Anti-Circular Verification** — independent raw-file re-computation + AST check banning hardcoded literal assertions.
4. **Atomic Provenance Ledger** — every published scalar mapped 1:1 in `data/provenance_ledger.json`.
5. **Negative Capability & The Sacred "N/A"** — genuine upstream nulls render explicitly as `[N/A]` rather than fabricated proxies.
6. **Compilation Latch** — PDF compilers invoke `vedit latch` / `verify_integrity.py` and abort on non-zero exit.
7. **Category & Unit Guard** — never blend incommensurable scopes or test methods.
8. **Statutory Proof** — official gazette IDs required for any regulatory/tariff claim.
9. **Scientific Taxonomy & Registry Verification** — reconcile binomials, authorities, phylogeny, and IUCN status verbatim against live GBIF/OpenTree/iNaturalist registries.
10. **Post-Render Prose Grounding (`vedit prose`)** — every rendered numeral and scientific exponent in the final PDF traces back to `provenance_ledger.json`, `summary_metrics.json`, or a DOI-backed entry in `background_citations.json` at half-ULP `f64` precision.
11. **Clickable Resource Links & Live Anti-Hallucination (`vedit links`)** — every external resource/URL/DOI has a real clickable PDF `/URI` annotation verified live before finalization (DOI Handle Registry, open-science APIs, and HTTP `GET` Soft-404 / bot-challenge rejection).

---

## 2. The 4 Golden Design Laws

### Law 1: The 60-30-10 Color Hierarchy (Light & Dark Modes)
- **Light Swiss Editorial Mode (Letter Reports):**
  - `60%` Canvas: Swiss Warm Ivory (`#fcfbf9`) — painted explicitly via `onPage`.
  - `30%` Scaffolding: Deep Navy (`#0f2b48`), Slate (`#334155`), Steel (`#64748b`), Hairlines (`#cbd5e1`), Subtle Tint (`#f1f5f9`).
  - `10%` Signal Accent: Cobalt (`#0284c7`), Amber (`#d97706`), Emerald (`#059669`), Signal Crimson (`#dc2626` — risk/surge only).
- **Dark Executive Mode (16:9 Slide Decks):**
  - `60%` Canvas: Deep Obsidian (`#0b0f19`) or Midnight Navy (`#051c2c`) — **MUST be painted full-bleed in `onFirstPage`/`onLaterPages` BEFORE flowables render**, never relying on default white PDF paper!
  - `30%` Scaffolding & High-Contrast Text: Subtle Tonal Band (`#111827` / `#0a253a`), Hairlines (`#243247`), Pure White Titles (`#ffffff`), Crisp Light Body (`>= #e2e8f0` at `>= 9.5–10 pt`), Secondary Captions (`>= #cbd5e1`, never dim `#64748b`–`#94a3b8` prose on dark). Always place a subtle horizontal dark scrim behind cover typography when parametric wireframe waves or bright artwork sit near text.
  - `10%` Signal Accent: Electric Cobalt (`#38bdf8`), Bright Amber (`#fbbf24`), Emerald (`#34d399`), Signal Crimson (`#f87171`).

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

## 5. 2023 Consulting Flagship Mode (WeasyPrint + Pure Vector Inline SVG)

For keynote-grade decks modeled on flagship 2023 institutional publications (*Quantum Technology Monitor*, *The Economic Potential of Generative AI*, *Global Economics Intelligence*, *The State of Organizations*), pair **WeasyPrint (`@page { size: 960pt 540pt; margin: 0; }`)** with **100% pure-vector inline `<svg>` exhibits**:

1. **Dark-Hero / Pure-White-Data Polarity Cadence (Never Monotone):**
   - **Cover Hero:** Deep Midnight Navy (`#051C2C`) transitioning to Cobalt (`#0A2E8A`), overlaid with a **42-strand parametric hyperbolic Bezier wireframe wave** (`#2251FF` / `#00A9F4`) and clean editorial hero art on the right.
   - **Executive Summary:** Full-bleed `#051C2C`, crisp `28 pt` white serif headline over a `1.2 pt` white horizontal rule, 3 airy sans columns, and 3 giant cyan/blue serif KPIs.
   - **Split Chapter Dividers:** Top `48%` full-bleed luminous artwork anchored by a `120 pt` bold white serif numeral (`1`, `2`), bottom `52%` pure white with `220 pt` left-indented serif chapter headline and 2-column framing copy.
   - **Data Exhibit Slides:** Pure `#FFFFFF` canvas, `19.5–22 pt` bold serif action title above a `1.1 pt` `#051C2C` rule, subtle bottom footnote separator, and a **bottom-right `#9AE6FF` ice-cyan section progress pill**.
2. **High-Contrast Editorial Serif + Geometric Sans Pairing:**
   - **Display Serif (`Charter` / `Georgia` / `Baskerville` Bold):** Cover titles, section numerals, slide action titles, giant `54 pt` `#2251FF` KPI callouts, and center donut totals.
   - **Data Sans (`Inter` / `Helvetica Neue`):** Chart annotations, subtitles, ledger cells, footnotes, and implications copy.
3. **The 4-Tier Cobalt Blue Chromatic Ramp (Zero Rainbow Clutter):**
   - `#051C2C` Midnight Navy (anchor totals, baselines, deep contractions) → `#06319C` Deep Royal → `#2251FF` Electric Blue (focal deltas, giant KPIs, expansion surges) → `#00A9F4` Vivid Cyan → `#9AE6FF` Ice Cyan (secondary shares & section pills).
4. **Signature Vector SVG Exhibit Archetypes:**
   - **Mass-Balance Waterfall / Bridge Chart:** Anchor bars (`#051C2C`), floating additions (`#2251FF`) and reductions (`#00A9F4`), dashed step connectors, top square-bracket span callouts, and floating serif net delta.
   - **Small-Multiples Wall + Grey `»` Implications Sidebar:** Grouped `5 + 3` indexed trajectory cards paired with a right-hand `#EFEFEF` sidebar bridged by a circular `#051C2C` `»` chevron badge (`3 pt` white ring).
   - **10×10 Rounded-Square Waffle Unit Matrix:** Bottom-up filled `10×10` grids (`#E5E7EB` track, 4-tier blue fill) with centered bold numerals inside the gray negative space.
   - **Donut Ring + 100% Stacked Share Shift:** 5-step blue donut (`2 px` white slice dividers, serif center total) paired with `2000` vs `2024` columns linked by translucent flow ribbons.
   - **WeasyPrint SVG Guardrails:** Inside flex containers, always give inline `<svg>` explicit `width`/`height` in `pt` (and set `.slide { height: 539.5pt; break-after: page; break-inside: avoid; }`) to prevent sub-pixel blank spill pages or `300 px` SVG collapse. Never use SVG 2 `paint-order="stroke"` on `<text>` in WeasyPrint (it strokes *over* the text fill); use clean label offsets or an explicit backdrop `<rect>` instead.
3. **Full-Bleed Editorial Photo Magazine Mode (`612 × 792 pt` Letter Portrait, WeasyPrint):** When producing photography-first editorial magazines (*Kinfolk* × *Cereal* × *Condé Nast Traveler* × *National Geographic* style, as demonstrated in `demos/felis-mundi-magazine/`):
   - **Typography & Paper Stock:** Pair warm uncoated archival paper (`#FAF8F5`) and deep carbon charcoal ink (`#161616`) with high-contrast Didone display serifs (`Didot` / `Bodoni 72`), warm book serif body copy (`Charter` / `Baskerville` at `9 pt`, `1.5×` leading), and wide-tracked uppercase sans metadata (`Inter`, `6.5–7 pt`, `+0.18em` tracking). Flip running folios and credits seamlessly to pure `#FFFFFF` over full-bleed photography.
   - **Cohesive Photography (`>= 50%` Edge-to-Edge Bleed):** Generate every plate under one locked **Master Photographic Film Identity Core** (see `references/image_generation_recipes.md` §5), vary spread architecture across adjacent pages (100% cover → 61% top bleed → 65% right vertical column → 100% photo essay → 76% diptych with `4 pt` white print gutters → 68% bottom bleed → 77% contact-sheet triptych → 100% closing dusk colophon), and credit AI photography transparently alongside a SHA-256 plate manifest.
   - **WeasyPrint Magazine Guardrails (Empirically Verified):**
     - **Drop Caps (`float: left`):** Never place a `float: left` drop cap inside a CSS Grid or Flexbox item in WeasyPrint 67.0 (it shrinks the text column or mis-offsets/collides the drop cap). Use `position: absolute` block columns (`display: block`) for split magazine pages so drop caps sit 100% flush-left with clean multi-line wrap.
     - **Seamless Gradient Scrims:** Never place a partial-height `linear-gradient` overlay box over bright sky or snow in WeasyPrint (Cairo paints a faint 1 px hairline seam along the box edge). Always size every scrim overlay to `100%` of its photo container and fade to `rgba(..., 0)` inside the transparent stops.
     - **Rotated Marginal Credits:** Anchor vertical right-edge credits with `top: 18pt; right: 16pt; transform-origin: 100% 0%; transform: rotate(-90deg);` (never `bottom right`, which swings the rotated text below the container clip).
     - **Clip-Aware Photo-Area Audit:** Never trust raw `page.get_image_rects(xref)` when using CSS `object-fit: cover` (it returns the unclipped draw matrix and inflates coverage). Verify true visible photo coverage using an in-memory dual-key raster diff (`demos/felis-mundi-magazine/scripts/audit_magazine.py`) that replaces embedded images with two distinct solid key colors and counts exact changed pixels at 72 DPI—asserting `>= 50.0%` visible photography and `>= 2` full-bleed trim edges on every page.
4. **Scientific Monograph × Learning Magazine Crossover Mode (`612 × 792 pt`, *Kew* × *DK* × *NatGeo* × *SciAm*, WeasyPrint):** Demonstrated in `demos/botanica-veridica/`:
   - **Hybrid Zero-Text Plate + Pure-Vector SVG Anatomy Overlay:** Generate clean museum studio/field plates with **zero embedded text**, then overlay deterministic pure-vector SVG 90° elbow anatomy leader lines, circular anchor dots, circular magnifying-lens zoom medallions (`border-radius: 50%`), and metric scale bars. Over dark/textured field photos, place labels inside high-contrast `#FBF9F4` archival pills (`fill-opacity: 0.95`) and attach each leader to the **nearest pill edge** so leaders never cross behind labels.
   - **Specimen-Derived Mineral Palette (WCAG AA Engineered):** Use warm eggshell paper (`#FBF9F4`), archival stone callout boxes (`#F1ECE1`), deep charcoal ink (`#181A18`), and muted mineral spot colors (`#005F5A` botanical teal, `#8A530B` ochre, `#964123` terracotta, `#185D3B` emerald, `#9C1F32` carmine, `#2C4966` slate—all engineered `>= 5.0:1` on `#FBF9F4`). Always verify with the background-sampled WCAG 2.1 contrast gate (`audit_contrast.py`).
   - **Interactive PDF/UA-1 + Print Pre-Press Dual Output:** Compile digital monographs with `pdf_variant="pdf/ua-1"`, nested CSS `bookmark-level: 1|2` PDF outlines, clickable internal TOC/key jump links, and external registry links (`GBIF`/`OpenTree`); offer an optional `--prepress` flag emitting `@page { bleed: 3mm; marks: crop cross; }` for print houses.
   - **Facing-Spread QA:** Always run `render_spreads.py` to visually verify opposing spreads (`[2|3]`, `[4|5]`, `[6|7]`, `[8|9]`) side by side for headline-baseline symmetry and cross-gutter visual weight.
   - **Dual-Target Living Web Publication (`compile_living_web.py`):** From the exact same Rule-6-latched `summary_metrics.json`, `provenance_ledger.json`, `background_citations.json`, and pure-vector `svg_exhibits.py`, also emit a zero-CDN-dependency interactive HTML/SVG Living Edition where clicking any number pops open its live SHA-256 cryptographic receipt & raw API excerpt (`[X-Ray Provenance]` mode), botanical pins highlight anatomy interactively, and dichotomous keys run live in the browser.
   - **Deterministic Geometry Gate (`vedit geometry`):** Always run `vedit geometry` before visual review to catch cross-line/same-line text collisions, `flags=0` vs `TEXT_ACCURATE_BBOXES` PDF clip-path character slicing, trim overflow, and wide-headline orphan wraps mechanically.
5. **Rust-Native Typst `0.15.1` Academic Monograph Mode (`--pdf-standard ua-1`, `demos/typst-carbon-monograph/`):**
   - **Native JSON Ingestion (Zero String Templating):** Load `summary_metrics.json` and `provenance_ledger.json` directly inside `.typ` via `#let data = json(...)` and `#let ledger = json(...)` (`--root "$REPO"`), achieving sub-second (`~415 ms`) incremental compilation with Knuth-Plass optical justification and native IEEE BibTeX (`#bibliography("references.bib")`).
   - **Cross-Platform Bundled SIL-OFL Typography (`vedit fetch-fonts`):** Pass `--font-path ~/.cache/verifiable-editorial/fonts` to pin 8 SHA-256 verified open-source fonts (*Cormorant Garamond*, *Source Serif 4*, *Inter*, *IBM Plex Mono*) across macOS and Ubuntu Linux CI with `0` unembedded fonts. Enable `number-type: "lining"` on *Cormorant Garamond* titles, KPIs, and folios so numerals align crisply.
   - **Certified ISO 14289-1 (`PDF/UA-1`) Math & Vector Exhibits:** Compile with `typst compile --pdf-standard ua-1`, attach descriptive screen-reader `alt` text to every `image(...)` **and** every inline/block equation (`#math.equation(alt: "...", $ ... $)`), embed pure-vector SVG exhibits (`∞ DPI`), and certify via `vedit prepress --min-dpi 300 --require-ua` (live `veraPDF` `106/106` passed rules, `0` failures).
6. **PDF Sample Injection & Design DNA Cloning (Sovereign Zig 0.17.0 Harness):**
   - To adopt the visual identity of *any* external reference PDF (consulting report, botanical book, magazine, slide deck, or mobile primer), run `vedit-zig inject <sample.pdf> --name <slug>` (from `zig/zig-out/bin/vedit`). The harness dissects trim dimensions (including `mobile_portrait_9x16`), live margins, 60-30-10 pixel-measured WCAG palette, font hierarchy mapped to bundled SIL-OFL substitutes, and page-by-page column/photo/archetype cadence into `archetypes/<slug>/{blueprint.json, skeleton.typ, AGENT_CARD.md}`.
   - Scaffold an immediately buildable, SHA-256-sealed, `PDF/UA-1`-certified publication cloned from that archetype via `vedit-zig init ./target --archetype <slug>` (zero Python required).
7. **Mobile-Native Subject-Understanding Mode (`360 × 640 pt`, `9:16` WhatsApp PDF/UA-1, `demos/cosmos-mobile-primer/` & `archetypes/mobile-primer/`):**
   - Built natively for instant zero-hiccup phone reading over WhatsApp, iOS Quick Look, and Android Drive with **ZERO filled boxes**: continuous deep-void `#07090F` OLED canvas (or `#FAF8F4` warm daylight paper), `28 pt` airy margins (`304 pt` measure), `10.6 pt` ragged-right `Inter` prose (`#D6DCE6`) paired with **optically glare-compensated matte grey bold (`#B6C0CE`, `10.7:1` AAA)** so bold strokes never bloom on OLED screens, `1.5 pt` top progress hairline, naked hairline-separated typographic KPIs, subtle **opposite-corner brackets (`┌ ... ┘`)** framing equations/notes/manifests in open negative space, `304 pt` box-free Tufte open-axis & precision-lollipop SVGs (`∞ DPI`), `>= 7.5:1` WCAG AAA contrast, and a compact **2-line bottom bar** (inline `SOURCES` + bare underlined Rule 11 tappable links directly over the quiet folio).
   - **Dynamic Non-Repeating Card Choreography (Creative Freedom):** Never stamp consecutive mobile cards in one fixed template order. Treat `[H]` Header, `[P]` Plate/SVG, `[K]` Naked KPI Strip, `[T]` Prose, and `[N]` `┌ ... ┘` Corner Note as **interchangeable modular atoms** above the fixed 2-line footer, and mix-and-match their vertical order per card to match the subject's mood (e.g., Cold-Open `P -> H -> T -> K -> N`, Hero-Under-Headline `H -> P -> K -> T -> N`, Aligned KPI-Over-Horizon `H -> K -> P -> T -> N`, Corner-Note Hook Lead `H -> N -> T -> K -> P`, Mid-Card Visual `H -> K -> T -> P -> N`, or Chart-First Inversion `H -> P(SVG) -> K -> T`).
   - **Zero Bare Text-Only Cards (`8` Panoramic Nano Banana Plates + `4` Code-Generated Vector SVGs, `325.5 DPI`, Zero Seam):** Because `generate_image` (Nano Banana) caps native ratios at `16:9` (`1376 × 768 px`) rather than arbitrary custom sizes, fill every non-SVG card's panoramic slot (`304 × 76–132 pt`) by prompting centered horizontal-band compositions on pure `#07090F` (or `#FAF8F4`) void margins, cropping deterministically to exact slot aspect (`1376 × 344–597 px` → `325.5–325.9 DPI >= 300 DPI`), lifting the 10th-percentile dark floor to exact canvas RGB (`#07090F`), and applying a raised-cosine edge feather (`14–16%` Y, `7–8%` X) so zero dark box border ever appears on OLED screens while keeping 8 plates + 4 vector exhibits across 12 cards at `613 KB` (`< 1 MB` WhatsApp budget, `veraPDF 106/106`).

---

## 6. Supporting References & Runnable Examples
- `references/design_laws_and_lexicon.md` — Extended design grammar, Gestalt spacing, and institutional style lexicon.
- `references/image_generation_recipes.md` — Fixed-spec visual continuity prompts for multi-asset cover/architecture illustrations.
- `examples/reportlab_premium_template.py` — Clean, runnable dual-mode (`--mode dark|light`) & dual-format (`--format 16x9|letter`) starter template with full-bleed background painting, safe Inter registration, hairline KPI strips, and Tufte ledgers.
