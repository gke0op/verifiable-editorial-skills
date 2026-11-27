---
name: premium-pdf-design
description: >-
  Institutional-grade PDF presentation (16:9 dark executive decks), report (Letter/A4 Swiss ivory monographs),
  and mobile-native 9:16 WhatsApp primer design system in 100% Zero-Python Zig 0.17 + Rust-native Typst PDF/UA-1.
  Enforces verifiable open-data pipelines, 60-30-10 color balance, hairline Tufte ledgers, Minto Pyramid action
  titles, pure-vector SVG exhibits, SHA-256-pinned SIL-OFL fonts, seamless `vedit plate` feathering, and
  automated 6-gate `vedit v0.7.0-zig` post-render QA auditing.
---

# Verifiable Institutional PDF Presentation & Data Visualization System (100% Zero-Python Zig 0.17 + Typst)

This skill pairs with `verifiable-pdf-pipeline` (data integrity) and `editorial-page-layout-guidelines` (grid geometry) to produce publication-grade **16:9 dark executive slide decks**, **Letter/A4 Swiss-ivory institutional monographs**, **academic two-column journals**, and **9:16 mobile WhatsApp field primers** in **pure Zig 0.17.0 + Rust-native Typst `PDF/UA-1`** (`0` Python dependencies).

---

## 1. Core Invariant: Substance Precedes Aesthetics

Every publication built with this skill must obey the **11 Anti-Cheat Hard Rules** defined in `verifiable-pdf-pipeline/SKILL.md`:
1. **Zero-Handwritten-Data Air-Gap** — parse all numbers from immutable raw files in `data/raw/`.
2. **Reality & Invariant Compiler** — enforce Zig 0.17 domain bounds and physical/accounting identities.
3. **Anti-Circular Verification** — independent raw-file re-computation banning hardcoded literal assertions.
4. **Atomic Provenance Ledger** — every published scalar mapped 1:1 in `data/provenance_ledger.json` with verified file SHA-256 and exact locator.
5. **Negative Capability & The Sacred "N/A"** — genuine upstream nulls render explicitly as `[N/A]` rather than fabricated proxies.
6. **Compilation Latch** — build scripts invoke `vedit latch` and abort immediately on non-zero exit.
7. **Category & Unit Guard** — never blend incommensurable scopes or test standards.
8. **Statutory Proof** — official gazette/statute IDs required for any regulatory/tariff claim.
9. **Scientific Taxonomy & Registry Verification** — reconcile binomials, authorities, phylogeny, and IUCN status verbatim against live GBIF/OpenTree/iNaturalist registries.
10. **Post-Render Prose Grounding (`vedit prose`)** — every rendered numeral, unit-suffixed metric, scientific exponent, and `/ToUnicode` glyph mapping traces back to `provenance_ledger.json`, `summary_metrics.json`, or a DOI-backed entry in `background_citations.json` at half-ULP `f64` precision.
11. **Clickable Resource Links & Live Anti-Hallucination (`vedit links`)** — every external resource/URL/DOI has a real visible clickable PDF `/URI` annotation verified live before finalization (DOI Handle Registry, open-science APIs, and live HTTP `GET` Soft-404 / bot-challenge rejection).

---

## 2. The 4 Golden Design Laws

### Law 1: The 60-30-10 Color Hierarchy (WCAG AA/AAA Verified)
- **Light Swiss Editorial Mode (Letter/A4 Monographs):**
  - `60%` Canvas: Swiss Warm Ivory (`#FAF9F6`) — set via `#set page(fill: rgb("#FAF9F6"))`.
  - `30%` Scaffolding: Deep Navy (`#0F2B48`), Slate (`#2C3A47`), Muted Slate (`#4C5B6B`, `>= 6.8:1` on ivory), Hairlines (`#CBD5E1`), Subtle Tint (`#F1F5F9`).
  - `10%` Signal Accent (all `>= 4.5:1` on `#FAF9F6`): Deep Cobalt (`#035E9E`, `6.4:1`), Ochre (`#8A530B`, `6.1:1`), Botanical Emerald (`#146346`, `7.1:1`), Signal Crimson (`#B91C1C`, `6.3:1` — risk/surge only). *(Never use pale `#0284c7` sky blue or `#d97706` amber for small text on ivory — they drop below `4.5:1` and fail `vedit contrast`!)*
- **Dark Executive & OLED Void Mode (16:9 Decks & 9:16 Mobile Primers):**
  - `60%` Canvas: Deep OLED Void (`#07090F`) or Deep Obsidian (`#0B0F19`) — set full-bleed via `#set page(fill: ...)`.
  - `30%` Scaffolding & Glare-Compensated Text: Crisp Light Titles (`#E2E7EF`), Regular Body (`#D6DCE6`), **Subtle Darker-Grey Bold (`#B6C0CE`, `10.7:1` AAA)** so bold strokes never bloom on OLED screens, Muted Metadata (`#9AA8BC`, `>= 7.5:1` AAA), Whisper-Thin Reticles (`#2B384E`), Hairlines (`#1C2638`).
  - `10%` Signal Accent: Ice Blue (`#8CC8F0`), Warm Gold (`#E8C078`), Sage (`#7AD1B8`), Rose (`#E58A8A`).

### Law 2: Hairline & Whitespace Gravity (Zero Boxed Cards)
- Never trap metrics or prose inside heavy rectangular strokes, rounded SaaS cards, or drop shadows.
- Structure groupings via **open opposite-corner architectural brackets (`┌ ... ┘`)** in open negative space, naked hairline-separated typographic KPIs, generous `12–16 pt` gutters, and booktabs-style Tufte ledgers (zero vertical grid lines).

### Law 3: Minto Pyramid Action Titles
Every slide or section opens with **one complete, assertive claim**, not a passive topic label:
- *Prohibited:* `"Global Emissions Trends"`
- *Required:* `"OECD-5 Cut Emissions -25.0%, Yet Emerging-3 Surged +235.8% to Lift Panel Totals to 23.52 Gt CO2e."`

### Law 4: Calibrated Vertical Fill Budgets + Visual & Automated Court Inspection
- **Letter/A4 Reports (`612×792 pt` / `595×842 pt`):** `85%–92%` target vertical fill (`min >= 82%`).
- **16:9 Decks (`960×540 pt`):** `72%–88%` target vertical fill (`min >= 72%`).
- **9:16 Mobile Primers (`360×640 pt`):** Calm, scannable single-column cards (`304 pt` measure) with zero empty middle voids and a fixed 2-line source/folio footer.
- Run `vedit audit-all --require-ua --verify-links` AND export 180-DPI PNG previews via `mutool draw -F png -r 180` (or `vedit spreads` for facing pages) to visually inspect every rendered page before shipping.

---

## 3. Pure-Vector Zig SVG Visualization Recipes (`∞ DPI`, Transparent)

Emit charts directly from your Zig 0.17 `scripts/pipeline.zig` as clean standalone `<svg>` files (`∞ DPI`, zero Matplotlib/Python, transparent canvas, top/right spines stripped, theme-matched ink):

1. **Dual-Panel Time Series + Rate Acceleration:** Historical trajectory with event shading and direct start/peak annotations paired with decadal rate bars.
2. **Stacked Mass-Balance Area + Indexed Trajectory:** Stacked flow volumes with **direct right-edge terminal labels** (zero floating legend boxes) paired with `Base = 100` structural divergence lines.
3. **Log–Log Phase Maps & Decoupling Quadrants:** Precision scientific scatter/contour exhibits (e.g., Fulton Radius Valley, Compactness $\Xi$ phase map) with clean leader offsets and zero overlapping labels.
4. **Stephen Few Horizontal Bullet Graphs & Precision Lollipops:** Whisper-thin hairline stems with direct right-aligned terminal numerals instead of chunky bar-chart boxes.
5. **Tufte Booktabs Ledgers with Inline Sparklines:** Compact vector sparkline SVGs embedded directly inside Typst `table(...)` cells with explicit amber/slate `[N/A]` cells (Rule 5).
6. **Gantt Schedules, Bifurcation Curves & Phylogenetic Cladograms:** Pure-Zig algorithmic plots computed straight from raw solver/telemetry data with zero intermediate CSV copying.

---

## 4. Production Zero-Python Typst 0.15.1 Implementation Patterns

### 4.1 Native JSON Ingestion, Full-Bleed Canvas & Glare-Compensated OLED Typography
Load `summary_metrics.json` and `provenance_ledger.json` natively inside `.typ` (zero string templating), paint the full-bleed canvas cleanly, and dynamically compute running folios with `context`:

```typst
#let data = json("../data/summary_metrics.json")
#let ledger = json("../data/provenance_ledger.json")

#let bg-void    = rgb("#07090F")
#let ink-bright = rgb("#E2E7EF")
#let ink-body   = rgb("#D6DCE6")
#let ink-bold   = rgb("#B6C0CE")
#let ink-muted  = rgb("#9AA8BC")
#let acc-gold   = rgb("#E8C078")
#let reticle    = rgb("#2B384E")

#set document(title: data.metadata.title, author: data.metadata.author)
#set text(font: "Inter", size: 10.6pt, fill: ink-body, lang: "en", hyphenate: false)
#show strong: set text(weight: "semibold", fill: ink-bold)
#set par(leading: 0.68em, spacing: 0.85em, justify: false)

#set page(
  width: 360pt, height: 640pt, fill: bg-void,
  margin: (top: 28pt, bottom: 30pt, left: 28pt, right: 28pt),
  background: context {
    let frac = counter(page).get().first() / counter(page).final().first()
    place(top + left, rect(width: 360pt, height: 1.5pt, fill: rgb("#1C2638")))
    place(top + left, rect(width: 360pt * frac, height: 1.5pt, fill: acc-gold))
  },
  footer: context {
    let p = counter(page).get().first()
    let tot = counter(page).final().first()
    grid(
      columns: (1fr, auto), align: (left + bottom, right + bottom),
      text(font: "IBM Plex Mono", size: 7.1pt, fill: ink-muted)[#upper(data.metadata.kicker)],
      text(font: "IBM Plex Mono", size: 7.1pt, fill: ink-muted)[#p / #tot],
    )
  },
)
```

### 4.2 SHA-256-Pinned Cross-Platform SIL-OFL Typography (`vedit fetch-fonts`)
Never rely on OS-specific commercial fonts. Provision the 8 cryptographically SHA-256-pinned SIL-OFL open-source fonts once via `vedit fetch-fonts` (*Cormorant Garamond*, *Source Serif 4*, *Inter*, *IBM Plex Mono*) and pass `--font-path ~/.cache/verifiable-editorial/fonts` to `typst compile --pdf-standard ua-1`. Enable `number-type: "lining"` on serif headlines, KPIs, and folios.

### 4.3 Open Opposite-Corner Architectural Brackets (`┌ ... ┘`, Zero Filled Boxes)
Frame equations, notes, active-recall blocks, or SHA-256 manifests without heavy rectangles by placing two whisper-thin `0.58 pt` L-brackets at top-left and bottom-right (`examples/typst_premium_template.typ` and `archetypes/mobile-primer/skeleton.typ`).

---

## 5. Publication Format Modes & Sovereign `vedit` Workflows

1. **Rust-Native Typst `0.15.1` Academic Monograph & Two-Column Journal Mode (`demos/typst-carbon-monograph/`, `exomundus-nasa-telemetry/`, `caie-flowshop-journal/`, `prl-yang-mills-chaos/`):**
   - Sub-second compilation with Knuth-Plass optical justification, native BibTeX (`#bibliography("references.bib", style: "ieee")`), accessible `#math.equation(alt: "...", $ ... $)`, stepped REVTeX `widetext` brackets, pure-vector SVGs (`∞ DPI`), and live `veraPDF 106/106` ISO 14289-1 certification via `vedit audit-all --require-ua`.
2. **Mobile-Native Subject-Understanding Mode (`360 × 640 pt`, `9:16` WhatsApp PDF/UA-1, `demos/cosmos-mobile-primer/` & `archetypes/mobile-primer/`):**
   - Zero filled boxes, continuous `#07090F` OLED void (or `#FAF8F4` daylight paper), `28 pt` margins (`304 pt` measure), glare-compensated `#B6C0CE` matte bold ink, subtle `┌ ... ┘` opposite-corner brackets, `1.5 pt` top progress bar, compact 2-line Rule 11 tappable source/folio bar, and **dynamic non-repeating per-card choreography** mixing `[H]` Header, `[P]` Plate/SVG, `[K]` Naked KPI Strip, `[T]` Prose, and `[N]` Corner Note across every card.
   - Fill every non-SVG panoramic slot (`304 × 76–132 pt`) via `vedit plate raw_16x9.jpg out.jpg --width-pt 304 --height-pt 118 --bg "#07090F"` (pure-Zig exact-aspect crop at `326 DPI`, 10th-percentile black-point lift, raised-cosine void feather, Baseline 4:4:4 JPEG keeping 12-card decks `< 1 MB`).
3. **Full-Bleed Editorial Photo Magazine & Scientific Crossover Modes (`demos/felis-mundi-magazine/`, `demos/botanica-veridica/`):**
   - Enforce `>= 50%` true visible photography and `>= 2` physical 1-px bleed edges via `vedit coverage --min-pct 50` (dual-key Image XObject diff + tonal-variance blank-plate rejection), verify opposing spreads with `vedit spreads`, and attach clean vector SVG 90° elbow anatomy callouts and zoom medallions over zero-text studio plates.
4. **PDF Sample Injection & Design DNA Cloning (`vedit inject` → `vedit init`):**
   - Dissect any external reference PDF into `archetypes/<slug>/{blueprint.json, skeleton.typ, AGENT_CARD.md}` (measuring trim, margins, 60-30-10 WCAG palette, SIL-OFL font ladder, band-union vertical fill %, and deduplicated photo coverage %) via `vedit inject <sample.pdf> --name <slug>`, then scaffold an immediately buildable, SHA-256-sealed, `PDF/UA-1` project via `vedit init ./target --archetype <slug>`.

---

## 6. Supporting References & Zero-Python Starter
- `references/design_laws_and_lexicon.md` — Extended design grammar, Gestalt spacing, and institutional style lexicon.
- `references/image_generation_recipes.md` — Fixed-spec visual continuity prompts for multi-asset cover/architecture illustrations (pair with `vedit plate` in pure Zig for exact-slot `>= 300 DPI` cropping, black-point lifting, and raised-cosine void feathering).
- `examples/typst_premium_template.typ` — Clean, runnable dual-polarity (`--input mode=dark|light`) zero-box Typst 0.15.1 `PDF/UA-1` starter template with subtle opposite-corner brackets (`┌ ... ┘`), matte OLED bold grey (`#B6C0CE`), and a 2-line Rule 11 source/folio bar.
