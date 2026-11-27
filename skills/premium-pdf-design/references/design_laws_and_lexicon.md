# Design Laws, Lexicon & Style Tokens for Institutional Publications

This reference details the aesthetic grammar, Gestalt visual hierarchy, and curated prompt lexicon behind `premium-pdf-design`. All laws here align strictly with the **Hairline & Whitespace Gravity** invariant (no heavy boxed web-dashboard cards).

---

## 1. The Four Foundational Design Laws

### Law 1: The 60-30-10 Color Balance
Derived from Swiss editorial print design and modern data systems, 60-30-10 prevents visual fatigue across multi-page decks and whitepapers:
- **60% Dominant Canvas:**
  - *Dark Executive Mode (16:9 Slides):* Deep Obsidian (`#0b0f19`), painted full-bleed before flowables.
  - *Swiss Editorial Light Mode (Letter Reports):* Warm Swiss Ivory (`#fcfbf9`), painted full-bleed before flowables.
- **30% Structural Scaffolding:**
  - Subtle borderless tonal bands (`#111827` dark / `#f1f5f9` light), hairline rules (`#1e293b` dark / `#cbd5e1` light), and disciplined slate typography (`#cbd5e1` dark / `#334155` light).
- **10% Functional Signal Accent (WCAG 2.1 AA Engineered):**
  - Cobalt (`#38bdf8` dark / `#035e9e` light) for primary data flow and kickers; Emerald (`#34d399` dark / `#146346` light) for positive reductions or target zones; Amber/Ochre (`#fbbf24` dark / `#8a530b` light) for bottlenecks, baselines, and `[N/A]` transparency flags; Crimson (`#f87171` dark / `#b91c1c` light) strictly reserved for risks, breaches, or adverse surges.

### Law 2: Gestalt Law of Proximity & Hairline Grouping
Human vision groups related items by spatial proximity and shared alignment—without needing thick rectangular boxes around every metric:
- **Open KPI Strips:** Group label, big numeral, and contextual subtext inside a clean borderless tonal band crowned with a `1.0–1.2 pt` top accent hairline and separated by `12–16 pt` whitespace gutters.
- **Caption Binding:** Place figure and ledger captions `4–6 pt` below their exhibit and `12–18 pt` above the next narrative block so caption ownership is unambiguous.

### Law 3: Gestalt Law of Similarity & Multi-Page Cadence
Readers infer functional equivalence from visual consistency:
- **Kicker & Badge Uniformity:** Keep all section kickers (`01 // ATMOSPHERIC BASELINE`) identical in size (`8 pt`), uppercase weight, and accent color across the entire document.
- **Visual Rhythm:** Alternate density and visual grammar across pages/slides:
  `Cover Hero -> Macro Time Series -> Structural Split -> Decoupling / Efficiency Matrix -> Audited Tufte Ledger -> Provenance Colophon`

### Law 4: Hick's Law & The 60-Second Executive Scan
Decision-makers scan headlines and exhibits first:
- **Minto Pyramid Principle:** Lead with the quantitative conclusion. Every slide and report section begins with one complete, falsifiable claim supported by the exhibit directly underneath.
- **Direct Chart Labeling:** Label series directly at their terminal data edge (`x_max`) whenever feasible instead of forcing eye-ping-pong between a detached legend box and the plotted curves.

---

## 2. Master Lexicon of Editorial Keywords

### Structural & Spatial
- **Swiss International Typographic Style:** Asymmetric grid harmony (`310 pt / 180 pt`), optical alignment, disciplined leading, and functional whitespace.
- **Booktabs / Tufte Ledger:** `1.0 pt` top/bottom outer rules, `0.75 pt` header separator, `0.25–0.35 pt` row hairlines, zero vertical lines, right-aligned numerals.
- **Negative Space as Authority:** Generous `42–54 pt` margins that frame high-density charts without claustrophobia.

### Visual & Typographic
- **Monospaced Cryptographic Telemetry:** SHA-256 digests, dataset identifiers, and build receipts rendered in bundled SIL-OFL `IBM Plex Mono` at `6.8–7.2 pt`.
- **Small-Caps Narrative Lead-in:** Colored bold uppercase opening phrase snapping cleanly to the body baseline without drop-cap table glitches.
- **Sacred `[N/A]` Honesty:** Distinct amber italic styling for genuinely unreported upstream observations so data gaps are immediately transparent to auditors.
