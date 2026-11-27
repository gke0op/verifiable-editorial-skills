---
name: editorial-page-layout-guidelines
description: >-
  Operational layout formulas, typographic hierarchy, and modular grid archetypes for high-density,
  publication-grade institutional reports (Letter portrait) and executive slide decks (16:9 widescreen).
  Enforces vertical fill budgeting (85-92% Letter, 72-88% 16:9), asymmetric grids, hairline scaffolding,
  and zero empty-page voids.
---

# Editorial Page Layout & Modular Grid Guidelines

This skill codifies the grid mathematics, vertical fill budgets, and typographic architecture used by institutional publications (World Economic Forum, IPCC, McKinsey Global Institute, Stripe Press, and *The Economist*) across both **Letter portrait reports (`612×792 pt`)** and **16:9 widescreen executive decks (`960×540 pt`)**.

---

## 1. The 4 Fundamental Layout Laws

### Law 1: The Vertical Fill Budget
- **Letter Portrait Report (`612 × 792 pt`, `54 pt` margins):**
  - Live canvas: `504 pt` wide × `684 pt` tall.
  - **Target Fill:** **`85%–92%` (`580–630 pt`)** on every page (minimum QA gate `82%`).
  - Pages terminating in the upper 30–50% read like accidental page spills or unfinished drafts. Never issue a hard `PageBreak()` after short copy without pairing secondary structural anchors (asymmetric marginalia, Tufte tables, or 3-column KPI ribbons).
- **16:9 Widescreen Slide Deck (`960 × 540 pt`, `42 pt` L/R, `38 pt` top, `34 pt` bottom):**
  - Live canvas: `876 pt` wide × `468 pt` tall.
  - **Target Fill:** **`72%–88%` (`337–412 pt`)** per slide (minimum QA gate `72%`).
  - Slides require more breathing room than print pages while still anchoring top-to-bottom rhythm with an action title, primary exhibit, and structured synthesis rail.

### Law 2: Asymmetric Grid Discipline (Letter Reports)
Single-column prose spanning the full `504 pt` width produces 85–100+ character lines, inducing reading fatigue.
- **The Golden Split (`310 + 14 + 180 = 504 pt`):**
  - **Primary Narrative Column:** `310 pt` (~61.5%) → optimal 55–65 characters per line.
  - **Gutter:** `14 pt` pure whitespace.
  - **Companion Marginalia / Sidebar:** `180 pt` (~35.7%) → methodological notes, pull quotes, accounting audits, or key metric spreads, anchored with a `1.2 pt` top accent hairline and subtle tonal tint (`#f1f5f9` light / `#111827` dark).

### Law 3: Hairline Scaffolding (No Boxed Dashboard Cards)
- Never trap KPIs, narrative paragraphs, or tables inside heavy rectangular `BOX` strokes, rounded web cards, or drop shadows.
- Structure groupings through **typographic proximity**, **generous column gutters (`12–16 pt`)**, **hairline rules (`0.25–1.2 pt`)**, and subtle borderless tonal bands.
- **Tufte Ledgers:** `1.0 pt` top/bottom booktabs rules, `0.75 pt` header underline, `0.25–0.35 pt` horizontal row hairlines, zero vertical grid lines, zero outer frame.

### Law 4: Bold Tracked Small-Caps Lead-ins (No Drop-Cap Tables)
Two-cell table drop caps frequently duplicate letters, misalign baselines, or collide in programmatic PDF compilers. Lead every major narrative section with inline bold uppercase small-caps:

```typst
#text(fill: rgb("#035E9E"), weight: "bold")[#upper[Atmospheric accumulation has accelerated threefold]] since systematic instrumental measurements began...
```

---

## 2. Five Letter Portrait Page Archetypes (`612 × 792 pt`)

| Archetype | Structure | Target Fill |
| :--- | :--- | :--- |
| **A. Hero Cover & Executive Opener** | Kicker (`8 pt`) + Action Headline (`19.5–22 pt`) + Italic Deck + 3-col floating KPI ribbon + Lead visual + Asymmetric `310/180` opening brief | `88%–96%` |
| **B. Asymmetric Narrative & Marginalia** | Section opener + `310 pt` investigative copy with small-caps lead-in / `180 pt` tinted sidebar (methodology, glossary, pull quote) + Bottom 3-col stat ribbon | `86%–92%` |
| **C. Data & Analysis Exhibit Spread** | Section opener + Full-width `504 pt` 300-DPI chart (`190–225 pt` tall) + Source/N caption + Asymmetric `310/180` forensic synthesis | `88%–95%` |
| **D. Analytical Tufte Ledger Spread** | Section opener + Framing copy + Full-width Tufte table (with optional inline sparklines & explicit `[N/A]` cells) + Lower synthesis | `85%–92%` |
| **E. Sovereign Provenance Colophon** | Pull quote + Cryptographic SHA-256 raw-source manifest table + 2-column audit certification & open-data attribution | `88%–92%` |

---

## 3. Four 16:9 Widescreen Slide Archetypes (`960 × 540 pt`)

Keep slide headlines to **one single crisp assertive line** (avoid 1–2 word widow wraps):

1. **Slide Archetype 1 — Cover Hero:** Top `4 pt` accent bar + Kicker + `27 pt` Title + `12 pt` Deck + 4-column tonal KPI strip (`1.2 pt` top accent rule) + 3-column Executive Thesis strip + bottom Provenance Receipt ledger (`~80–85%` fill).
2. **Slide Archetype 2 — Dual-Panel Visual + 3-Column Synthesis:** Kicker + single-line `15 pt` Action Title + full-width (`876 × 315 pt`) side-by-side chart exhibit + 3-column structured synthesis rail below hairline (`~85–91%` fill).
3. **Slide Archetype 3 — Executive Tufte Ledger Slide:** Kicker + Action Title + full-width Tufte table (`10` columns with inline sparklines and explicit amber `[N/A]` cells) + Rule 5 methodological caption + 3-column bottom insight strip (`~85–90%` fill).
4. **Slide Archetype 4 — Visual + Cryptographic Audit Close:** Kicker + Action Title + compact full-width exhibit (`876 × 238 pt`, e.g. Stephen Few bullet graphs) + bottom 2-column split: SHA-256 raw file manifest (left) and 5-Phase Audit Receipt (right) (`~84–89%` fill).
5. **Slide Archetype 5 — Consulting Flagship Polarity Sequence (Typst + SVG):** Alternate `#051C2C` Dark Midnight Cover & Executive Summary → `48%/52%` Split Chapter Divider (`120 pt` white serif numeral) → Pure `#FFFFFF` Exhibit Slides featuring a `19.5 pt` bold serif action title above a `1.1 pt` navy rule, optional `#EFEFEF` right-hand implications sidebar with a straddling circular `#051C2C` `»` badge, and a bottom-right `#9AE6FF` section progress pill.

---

## 3B. Six Full-Bleed Photo Magazine Archetypes (`612 × 792 pt`, `>= 50%` Photography)

For photography-first editorial magazines (*Kinfolk* × *Cereal* × *Condé Nast Traveler* × *National Geographic*), never repeat the same bleed geometry on two consecutive pages. Every page must touch `>= 2` trim edges and pass an exact clip-aware visible photo coverage gate of **`>= 50%`** (typically `60%–100%`):

| Archetype | Structure & Bleed Edges | Visible Photo % |
| :--- | :--- | :--- |
| **M1. Full-Bleed Iconic Cover** | `BLRT` bleed (`3:4` hero) + wide-tracked centered `Didot` masthead (`62 pt`) in quiet upper sky + bottom-left coverline + bottom-right hairline miniature TOC | `~99%` |
| **M2. Top Bleed Feature + 2-Col Essay** | `LRT` top full-bleed (`484 pt`) with rotated marginal credit + warm `#FAF8F5` lower editorial bed (`308 pt`) with 3-line drop cap, 2-col reportage, italic pull quote, oversized serif folio | `~61%` |
| **M3. Asymmetric 65/35 Right Vertical Bleed** | `BRT` right bleed (`396×792 pt`) + narrow left `#FAF8F5` anchor column (`216 pt`, `display: block` for clean drop cap) with stacked display title, italic deck, tight `34–38` char measure, bottom caption | `~65%` |
| **M4. Full-Bleed Photo Essay Plate** | `BLRT` full-bleed vertical plate + display serif headline set directly into matte shadow negative space (zero box) + lower-edge translucent dark editorial band | `~99%` |
| **M5. Panorama + Inset Diptych** | `LRT` panoramic top (`364 pt`) + `4 pt` white print gutter + bottom-left essay (`268 pt`) + `BR` full-bleed inset (`340×424 pt`) | `~76%` |
| **M6. Inverted Calm Top / Contact-Sheet Triptych / Closing Dusk Colophon** | Alternate top-header + `BLR` bottom bleed (`~68%`), `LRT` 3-photo asymmetric triptych with `4 pt` white gutters + 3-col numbered micro-caption strip (`~77%`), and `BLRT` closing plate with SHA-256 colophon ledger in the shadowed lower 38% (`~99%`) | `68%–99%` |

---

## 3C. Scientific Monograph × Learning Magazine Crossover Archetypes (`612 × 792 pt`)

Choreographed across true facing spreads (`[2|3]`, `[4|5]`, `[6|7]`, `[8|9]`, verified via `vedit spreads` and `vedit contrast`), pairing full-bleed botanical/scientific photography with live audited vector exhibits and learning scaffolding (`demos/botanica-veridica/`):

- **S1. Evolutionary & Telemetry Facing Opener (`[2|3]`):** Left page pairs a live phylogenetic cladogram (parsed from OpenTree Newick) + *DK*-style 6-column comparative morphology silhouette strip + *NatGeo*-style logarithmic scale lineup; right page pairs a live equirectangular GBIF world dot-map + herbarium-vs-citizen-science ratio bars + 12-month flowering phenology matrix. Keep both facing page display headlines on matching single lines.
- **S2. Studio Specimen + 90° SVG Anatomy Spread (`[4]`, `[8]`):** Top `~56%` edge-to-edge studio specimen plate on `#F7F3E8` archival ground overlaid with pure-vector SVG 90° elbow callouts and a metric scale bar; lower `~44%` `#FBF9F4` monograph bed containing italic binomial + Roman authority, IUCN status badge, clickable registry link, drop-cap essay or numbered 1-2-3 mechanism steps, live monthly sparkline chart, and a tinted `#F1ECE1` **"Field Check"** learning box.
- **S3. Habitat Bleed + Circular Magnifying-Lens Medallion (`[5]`, `[6]`, `[7]`, `[9]`):** Alternate right-column (`61%` bleed), top-bleed with a `134 pt` circular macro zoom medallion (`border: 2.5pt solid #FBF9F4`), overhead structural truss anatomy pills, and inverted calm-top / bottom-bleed spreads so opposing pages always contrast visually.
- **S4. Dichotomous Field Key & Rule 9 Verification Close (`[10]`):** Top half houses an interactive pure-vector branching dichotomous identification key (binary observable traits linking directly to species plates); bottom half holds the Rule 9 live taxonomy reconciliation Tufte ledger and SHA-256 cryptographic & photographic colophon.

---

## 3D. Rust-Native Typst Scientific Monograph Archetype (`612 × 792 pt`, `PDF/UA-1`)

Demonstrated in `demos/typst-carbon-monograph/` (sub-second `~415 ms` compilation, `87%–89%` vertical fill across all 4 pages, `veraPDF 106/106` ISO 14289-1 compliant):
- **Page 1 — Swiss Ivory Cover & Vector Lead Exhibit:** `2.4 pt` navy top rule + Cormorant Garamond lining title + uniform-height 4-column KPI ribbon (`par(justify: false)` so paired metrics never stretch-wrap) + full-width pure-vector SVG dual-panel chart + `1.55fr / 1fr` narrative & callout + 3-column hairline summary strip.
- **Page 2 — Structural Divergence & Tufte Economic Ledger:** Opening framing paragraph + pure-vector dual-panel exhibit + 9-column booktabs Tufte ledger (`[N/A]` amber Rule 5 column) + narrative synthesis + cobalt-accented bottom policy takeaway box.
- **Page 3 — Optical Display Math & Verification Court:** Asymmetric `1.55fr / 1fr` split pairing accessible `#math.equation(alt: ...)` Kaya & OLS identities on the left with a 3-card verification/Rule-5/SIL-OFL sidebar on the right, anchored across the bottom by a full-width 7-column decadal velocity table.
- **Page 4 — Cryptographic Seal, Live Provenance Extract & IEEE Bibliography:** Dynamic `raw_file_hashes` SHA-256 table + live 6-row extract from `provenance_ledger.json` + native `#bibliography("references.bib", style: "ieee")` + bottom-anchored Production & Standards Certification Colophon (`#v(1fr)`).

---

## 3E. Mobile-Native Subject-Understanding Primer (`360 × 640 pt`, `9:16` WhatsApp PDF/UA-1)

Designed natively for phone screens so a single `< 1 MB` (`~234–613 KB`) PDF opens instantaneously inside WhatsApp, iOS Quick Look, Android Drive, or any mobile PDF viewer with **zero pinch-zoom, zero horizontal panning, ZERO filled boxes, and open architectural corner brackets (`┌ ... ┘`)** (demonstrated in `demos/cosmos-mobile-primer/` and registered as `archetypes/mobile-primer/`):

- **Zero-Box Minimalist Philosophy (Strict):**
  - **ZERO filled rectangular boxes, zero rounded SaaS card fills, zero button pill borders.** Every headline, stat, equation, SVG chart, and note floats directly on one continuous, calm canvas (`#07090F` OLED Void Dark OR `#FAF8F4` Warm Paper Daylight).
  - **Open Opposite-Corner Brackets (`┌` top-left + `┘` bottom-right ONLY):** When framing a key equation, intuition check, active-recall block, or SHA-256 manifest, draw only two whisper-thin (`0.55–0.60 pt`) L-brackets at opposite corners (`~36–44 pt` horizontal × `~22–28 pt` vertical) leaving the other two corners completely open — creating an invisible box held by pure negative space.
  - **Naked Typographic KPIs:** Set 2–3 large `IBM Plex Mono` figures directly on the canvas bounded only by a `0.45 pt` top/bottom hairline and ultra-thin `0.4 pt` vertical dividers (no tiles or borders).
  - **Box-Free Tufte SVGs (`304 pt` wide, `∞ DPI`):** Seamless canvas background (no outer `<rect stroke=...>` card frame), open L-axes (top/right spines stripped), and precision hairline lollipop stems instead of chunky progress bars.
- **Zero Bare Text-Only Cards & Fixed-Slot Panoramic Plates (`Nano Banana`, `>= 300 DPI`, Zero Visible Seam):**
  - Every card carries either a **code-generated pure-vector exhibit** (e.g., cover reticle, log-log phase map, compactness ladder, scaling plot) OR a **seamless fixed-slot panoramic plate** — leaving zero bare text-only pages.
  - Generative image models (`generate_image` / Nano Banana) output discrete native aspect ratios up to **`16:9` (`1376 × 768 px`)** — not arbitrary custom pixel dimensions or ultra-wide `2.3:1–4.0:1` ribbons natively.
  - To populate any fixed horizontal card slot (`304 × 76–132 pt`) cleanly without breaking zero-box minimalism, print DPI (`>= 300`), or `< 1 MB` WhatsApp delivery:
    1. **Center-Band `16:9` Prompting:** Generate at `16:9` (`1376 × 768`) under one locked photographic/observatory visual identity, explicitly composing the entire subject inside the **central horizontal band** (`~42%–65%` vertical span) surrounded by pure canvas void (`#07090F` or `#FAF8F4`) on all four edges — zero embedded text, zero frames, zero borders.
    2. **Deterministic Slot Crop (`>= 300 DPI`):** Center-crop full `1376 px` width to exact target slot height (`round(1376 * h_pt / 304)` → **`325.5–325.9 DPI`** across every height `h_pt <= 169 pt`, passing `vedit prepress --min-dpi 300` with headroom).
    3. **Black-Point Alignment + Raised-Cosine Edge Feather:** Never drop a raw `#000000` image onto a `#07090F` OLED canvas (it creates a visible dark box seam). Map the 10th-percentile dark floor to exact canvas RGB (`RGB(7, 9, 15)`) and apply a raised-cosine edge feather (`14–16%` Y, `7–8%` X) into exact canvas RGB so every border melts invisibly into the void.
    4. **Zero-Python Pure-Zig Execution (`vedit plate`):** Run `vedit plate raw_16x9.jpg out_plate.jpg --width-pt 304 --height-pt 118 --bg "#07090F"` to execute steps 2–3 in one zero-Python command (emitting pure-Zig Baseline 4:4:4 JPEG `quality=88`, `~15–77 KB/plate`; `~371 KB` across 8 cosmic plates → `611 KB` total 12-card PDF), embed via `image(path, width: 304pt, height: h, fit: "cover", alt: "...")`, and state AI-illustrative attribution transparently on the closing colophon card.
- **Phone Canvas & Safe Area (`360 × 640 pt`, `28 pt` L/R, `28 pt` top, `30 pt` bottom):**
  - Live content width = **`304 pt`** (`~40–45 ch` single-column measure — NEVER two-column body prose!).
  - Top `1.5 pt` whisper-thin reading progress hairline (`page / total`) + compact **2-line bottom bar** (Line 1: inline `SOURCES` + bare underlined tappable links; Line 2: running title + folio `08 / 12` — never 3 stacked bottom lines).
- **Thumb-Scale Typography & OLED Optical-Glare Compensation:**
  - **Body prose:** `10.6–11.2 pt` (`Inter`, leading `1.50×`, ragged-right `justify: false`, `hyphenate: false`). Never drop body prose below `10 pt`.
  - **Subtle Darker-Grey Bold Ink on OLED (`#B6C0CE` vs `#D6DCE6` body):** On `#07090F` OLED dark mode, bold/semibold strokes emit more light per character and halate if set at the same brightness as thin regular prose. Set `#show strong: set text(weight: "semibold", fill: rgb("#B6C0CE"))` (`10.7:1` WCAG AAA) one subtle grey step deeper than `#D6DCE6` regular prose (`13.7:1`), and soften headlines from glaring white to `#E2E7EF` (`15.1:1`) so extended phone reading stays calm and fatigue-free.
  - **Card headline:** `19–20 pt` semibold (`Source Serif 4` lining figures), balanced across at most 2 lines (never a 1-word hanging wrap).
  - **Tables:** Max **3 columns** (`0.35 pt` row hairlines, zero vertical rules); right-aligned `IBM Plex Mono` figures.
  - **Restrained Observatory Palette (Zero Neon Rainbow):** Continuous `#07090F` OLED void, `#E2E7EF` titles, `#D6DCE6` body, `#B6C0CE` matte bold, `#9AA8BC` muted metadata (`>= 7.5:1` WCAG AAA!), `#2B384E` whisper-thin reticles, and muted editorial accents (`#E8C078` warm gold, `#8CC8F0` ice blue, `#E58A8A` rose, `#7AD1B8` sage).
- **Dynamic, Non-Repeating Card Choreography (Creative Freedom — NO Cookie-Cutter Order):**
  - **NEVER force every card into the exact same top-to-bottom section sequence.** Treat each card's elements as **interchangeable modular atoms** — `[H]` Header (`Kicker + Headline`), `[P]` Visual Plate or Pure-Vector SVG, `[K]` Naked KPI Strip, `[T]` Narrative Prose, and `[N]` Open `┌ ... ┘` Corner-Bracket Note — floating freely above the anchored `[F]` 2-Line Source/Folio Bar.
  - **Rule of Non-Repetition:** No two adjacent cards should share the exact same vertical block sequence. Act as an editorial art director and mix-and-match compositions to match the emotional and physical rhythm of each topic:
    - **Cold-Open Visual (`P -> H -> T -> K -> N`):** Open silently with the photograph/plate emerging right out of the top void *above* the kicker and headline for dramatic reveals.
    - **Hero-Under-Headline (`H -> P -> K -> T -> N`):** Drop the visual immediately beneath the title to anchor an unfamiliar subject before unpacking numbers.
    - **Aligned KPI-Over-Visual (`H -> K -> P -> T -> N`):** Pair a 2- or 3-column metric strip directly above a comparative image so left/right stats align straight over their corresponding subjects.
    - **Corner-Note Hook Lead (`H -> N -> T -> K -> P`):** Open with the sharpest paradox or tension inside `┌ ... ┘` brackets, unpack the mechanism and numbers, and close on a bottom-anchored horizon plate.
    - **Metric Shock / Mid-Card Centerpiece (`H -> K -> T -> P -> N`):** Lead straight with jaw-dropping numbers, place the plate mid-card to break prose flow, and close on a `┌ ... ┘` verification receipt.
    - **Chart-First Inversion (`H -> P(SVG) -> K -> T`):** Open immediately with a pure-vector plot when the curve itself carries the "aha!" twist.
  - **Fixed Invariants vs. Creative Canvas:** Only the continuous void/paper canvas, zero filled boxes, `28 pt` margins, matte OLED bold ink (`#B6C0CE`), `1.5 pt` top progress bar, and 2-line bottom bar stay locked across the deck — everything inside the live canvas is dynamically interchangeable per card.
- **Pedagogical Arc (Understanding First, Layout Free):**
  1. **Poster Cover (Card 1):** WhatsApp thumbnail hero — title + deck + box-free vector exhibit + naked stat strip + subtle swipe cue.
  2. **The Unifying Mental Model (Card 2):** Intuition-first governing law + accessible `#math.equation(alt: ...)` inside subtle `┌ ... ┘` corners + numbered floors + seamless visual anchor.
  3. **Grand Visual Map (Card 3):** Full-width `304 pt` open-axis pure-vector map + `┌ ... ┘` reading guide.
  4. **Dynamic Concept Deep Dives (Cards 4–10):** Mix-and-match `[H]`, `[P]`, `[K]`, `[T]`, `[N]` dynamically across every card — zero adjacent repeats — blending code-generated pure-vector exhibits and seamless `326 DPI` panoramic plates.
  5. **Complete Field Ledger + Active Recall (Card 11):** Compact 3-column Tufte table + `┌ ... ┘` rapid intuition Q&A + panoramic climax plate.
  6. **Cryptographic Seal & Source Library (Card 12):** Live SHA-256 raw manifest inside `┌ ... ┘` corners + 6-Gate seal + visual attribution + serene deep-field closing plate + 2-line source bar.
- **Box-Free 2-Line Mobile Touch Bar (Rule 11 Extension):** Place `SOURCES` inline on the same row as the bare underlined `IBM Plex Mono` links (`NASA JPL SBDB ↗`, transparent `y: 4.5pt` touch padding) directly above the quiet folio line — keeping the entire footer strictly **2 lines** while every link is verified live via `vedit links`.
- **WhatsApp Delivery Budget:** Pure-vector SVGs (`∞ DPI`) + feathered panoramic plates (`~15–77 KB` each, `>= 300 DPI`) + subset SIL-OFL fonts keep total file size **`< 1 MB` (`~234–613 KB`)**, strictly certified `PDF/UA-1` (`veraPDF 106/106`) and passing all 6 VES gates.

---

## 4. Typographic Hierarchy Scale (`Inter` with `Helvetica` Fallback)

| Token | Size / Leading | Weight | Light Mode | Dark Mode | Role |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `Kicker` | `8.0 / 10.5 pt` | Bold | `#035E9E` | `#38bdf8` | Section / slide classification |
| `CoverTitle` | `27.0 / 33.0 pt` | Bold | `#0f172a` | `#f8fafc` | 16:9 cover display headline |
| `Headline` | `19.5 / 23.5 pt` | Bold | `#0f172a` | `#f8fafc` | Letter cover / primary claim |
| `ActionTitle` | `14.5–15.0 / 19.0 pt` | Bold | `#0f172a` | `#f8fafc` | Minto Pyramid slide/section claim |
| `Deck` | `9.8–12.0 / 14–17 pt` | Italic / Reg | `#334155` | `#cbd5e1` | Executive subtitle |
| `Body` | `8.5–9.0 / 13.0 pt` | Regular | `#334155` | `#cbd5e1` | Narrative prose (ragged right) |
| `PullQuote` | `10.8–13.0 / 15–18 pt` | Bold Italic | `#0f2b48` | `#f8fafc` | Floating synthesis anchor |
| `KpiNumber` | `21.0–23.0 / 24–26 pt` | Bold | `#0f2b48` | `#f8fafc` | Primary audited metric |
| `KpiLabel` | `7.2–7.5 / 9.5 pt` | Bold | `#035E9E` | `#38bdf8` | Uppercase KPI header |
| `TableHeader` | `7.0–7.5 / 9.5 pt` | Bold | `#0f2b48` | `#38bdf8` | Tufte ledger header |
| `TableCell` | `7.5–8.0 / 10.5 pt` | Regular | `#0f172a` | `#f8fafc` | Tabular data (right-aligned nums) |
| `Caption` | `7.3 / 10.0 pt` | Italic | `#64748b` | `#94a3b8` | Source, sample size (`N`), & Rule 5 notes |

### Micro-Typography Guardrails
- Always use non-breaking spaces (`&nbsp;`) before compact units (`6.94&nbsp;t`, `429.98&nbsp;ppm`) inside narrow sidebars so units never orphan onto a new line.
- Keep `>= 4–5 pt` breathing room between a ledger's bottom rule and its footnote caption.
