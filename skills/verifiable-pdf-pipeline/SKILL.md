---
name: verifiable-pdf-pipeline
description: >-
  Turnkey open-data verification pipeline for publication-grade PDF presentations, institutional reports, and
  scientific monographs (100% Zero-Python Zig 0.17 + Rust-native Typst PDF/UA-1). Enforces 11 machine-checked
  anti-cheat rules: zero hardcoded data, SHA-256 raw manifests, Zig domain bounds, cryptographic provenance
  ledgers, independent raw re-parsing, explicit N/A handling, fail-closed compilation latching (`vedit latch`),
  scientific taxonomy verification, post-render Rule 10 PDF prose grounding (half-ULP precision, signed,
  exponent-aware, and ToUnicode-anomaly checked), Rule 11 clickable PDF resource links & live anti-hallucination
  URL/DOI verification (`vedit links`), geometric OBB/AABB collision & Bezier clip-path linting, composited
  144-DPI WCAG contrast, print pre-press preflight (effective DPI, embedded fonts, bleed/trim boxes, real CMYK
  PAM TAC, live veraPDF ISO 14289-1 PDF/UA-1), and SHA-256-pinned SIL-OFL font provisioning via `vedit`.
---

# Verifiable Factual PDF & Data Presentation Pipeline (100% Zero-Python Zig 0.17 + Typst)

This skill defines a domain-agnostic, fail-closed engineering pipeline for producing high-stakes mobile primers, peer-reviewed journals, institutional whitepapers, and scientific monographs in **pure Zig 0.17.0 + Rust-native Typst `PDF/UA-1`** (`0` Python dependencies). It enforces an absolute **Zero-Mock Data Invariant** backed by the sovereign bare-metal **`vedit` (`v0.7.0-zig`)** 6-gate court and a **51-test pure-Zig adversarial sabotage suite (`zig build test-court`)**.

Every published number must be streamed from genuine upstream sources into immutable raw files, validated against physical and accounting invariants, registered in an atomic provenance ledger, independently re-parsed from raw inputs without circular assertions, grounded post-render inside final PDF prose (Rule 10), and audited for geometric collisions, clip-path slicing, and background-sampled WCAG 2.1 contrast.

---

## The 11 Inviolable Anti-Cheat Rules

These rules apply unconditionally across domains—macroeconomics, climate telemetry, botany/biodiversity, energy grids, logistics, finance, semiconductors, or healthcare:

```
┌────────────────────────────────────────────────────────────────────────┐
│                   THE ANTI-CHEAT CONSTITUTION                          │
├────────────────────────────────────────────────────────────────────────┤
│ Rule 1: Zero-Handwritten-Data Air-Gap                                  │
│         No manual numeric dictionaries, JSONs, or CSVs.               │
│         Every number must be parsed by code from data/raw/.            │
├────────────────────────────────────────────────────────────────────────┤
│ Rule 2: Reality & Invariant Compiler (Domain Bounds)                   │
│         Strict Zig 0.17 bounds (physics, accounting, time).            │
│         Out-of-bounds values fail closed immediately (exit 1).         │
├────────────────────────────────────────────────────────────────────────┤
│ Rule 3: Anti-Circular Verification Law                                 │
│         Ban asserting domain variables against hardcoded literals.     │
│         Verifiers must independently re-parse data/raw/.               │
├────────────────────────────────────────────────────────────────────────┤
│ Rule 4: Atomic Provenance Tuple per Data Point                         │
│         Every scalar metric in summary_metrics.json must exist in      │
│         data/provenance_ledger.json with file SHA-256 + exact locator. │
├────────────────────────────────────────────────────────────────────────┤
│ Rule 5: Negative Capability & The Sacred "N/A"                         │
│         Upstream nulls must remain explicit null / [N/A].              │
│         Fabricating proxies or extrapolating silently is forbidden.    │
├────────────────────────────────────────────────────────────────────────┤
│ Rule 6: Substance Precedence (Compilation Latch)                       │
│         Layout aesthetics are subordinate to data veracity.            │
│         Build scripts invoke `vedit latch` and abort on failure.       │
├────────────────────────────────────────────────────────────────────────┤
│ Rule 7: Category & Unit Incommensurability Guard                       │
│         Never fuse distinct product grades, scopes, or test standards  │
│         without explicit mathematical conversion and labeling.         │
├────────────────────────────────────────────────────────────────────────┤
│ Rule 8: Primary Regulatory & Statutory Proof                           │
│         No statute, tax, or mandate cited without official gazette ID  │
│         and explicit scope (active law vs. proposed legislation).      │
├────────────────────────────────────────────────────────────────────────┤
│ Rule 9: Scientific Taxonomy & Registry Verification                    │
│         In biological/natural-history publications, every binomial,    │
│         botanical/zoological authority, Family, Order, phylogenetic    │
│         node, and IUCN code must be reconciled verbatim from live      │
│         authoritative registries (GBIF Backbone, Open Tree of Life,    │
│         iNaturalist) — unlinked statuses stay explicit [N/A].          │
├────────────────────────────────────────────────────────────────────────┤
│ Rule 10: Post-Render Prose-to-Ledger Grounding (`vedit prose`)         │
│         Every quantitative number & scientific exponent (`10^7`,       │
│         `9.7×10⁹`) extracted from FINAL PDF bytes must trace back at   │
│         exact half-ULP displayed precision to `provenance_ledger.json`,│
│         `summary_metrics.json`, or `data/background_citations.json`.   │
├────────────────────────────────────────────────────────────────────────┤
│ Rule 11: Clickable Resource Links & Live Anti-Hallucination Gate       │
│         (`vedit links`) — MANDATORY BEFORE FINALIZING ANY REPORT:      │
│         (a) Every cited resource, dataset, agency, paper, URL, or DOI  │
│             MUST be a real clickable PDF `/URI` link (`>= 2×2 pt` rect)│
│             — zero dead plain-text URLs/DOIs, zero placeholders.       │
│         (b) Every resource declared in `background_citations.json` /   │
│             `provenance_ledger.json` MUST be clickable in the PDF.     │
│         (c) BEFORE finalizing, the agent MUST visit & verify EVERY     │
│             link live (`vedit links <pdf>`): DOIs via CNRI/IDF Handle  │
│             Registry (`doi.org/api/handles/<doi>`), open-science       │
│             portals via public APIs, and web pages via live HTTP GET   │
│             inspecting status, `<title>`, and `<h1>` to reject 404/    │
│             410/403/5xx, DNS errors, Soft-404s, HTTP-200 bot walls     │
│             (`Client Challenge`, `Just a moment`), and semantic        │
│             mismatches. Never finalize a report with unverified links! │
└────────────────────────────────────────────────────────────────────────┘
```

---

## The 5-Phase Fail-Closed Workflow (100% Zero-Python Zig 0.17 + Typst)

```
[ Primary Open Sources / REST APIs / Official Datasets ]
                        │
                        ▼  (curl / scripts/pipeline.zig)
┌────────────────────────────────────────────────────────┐
│ PHASE 1: Raw Ingestion & Deduplicated SHA-256 Sealing  │
│ - Stream verbatim upstream bytes into data/raw/        │
│ - Write sorted, deduplicated data/manifest.sha256      │
│ - Zero manual numeric dictionaries or hand-edited CSVs │
└────────────────────────────────────────────────────────┘
                        │
                        ▼  (scripts/pipeline.zig — Zig 0.17)
┌────────────────────────────────────────────────────────┐
│ PHASE 2–3: Invariants, Synthesis & Provenance Sealing  │
│ - Typed Zig structs enforcing domain physics bounds    │
│ - Register 100% of metrics in provenance_ledger.json   │
│ - Emit sealed summary_metrics.json + pure-vector SVGs  │
└────────────────────────────────────────────────────────┘
                        │
                        ▼  (vedit latch — Pure-Zig Gate 1)
┌────────────────────────────────────────────────────────┐
│ PHASE 4: Cryptographic Compilation Latch (Veto Gate)   │
│ - Re-hash every file in data/raw/ vs manifest.sha256   │
│ - Confirm 100% Rule 4 provenance ledger coverage       │
│ - Must exit 0 before Phase 5 Typst compilation unlocks │
└────────────────────────────────────────────────────────┘
                        │
                        ▼  (typst compile --pdf-standard ua-1 + vedit audit-all)
┌────────────────────────────────────────────────────────┐
│ PHASE 5: Typst PDF/UA-1 Typesetting & 6-Gate Court     │
│ - Load JSON natively via `#json(...)` + `vedit plate`  │
│ - Pass WCAG, Geometry, Rule 10, Prepress/veraPDF,      │
│   and Rule 11 Live Links + inspect `mutool` PNGs       │
└────────────────────────────────────────────────────────┘
```

---

## Standard Project Scaffold

```
<project_root>/
├── data/
│   ├── raw/                       # Immutable upstream files (.json, .csv, .xml, .txt)
│   ├── manifest.sha256            # Sorted, deduplicated SHA-256 manifest of data/raw/
│   ├── provenance_ledger.json     # Atomic provenance records for every published metric
│   ├── background_citations.json  # DOI/URL-backed contextual constants for Rule 10 & Rule 11
│   └── summary_metrics.json       # Audited aggregates backed 1:1 by provenance_ledger.json
├── scripts/
│   └── pipeline.zig               # Pure-Zig 0.17 ingestion, bounds, sealing & pure-vector SVGs
├── report/
│   ├── figures/                   # Pure-vector SVG exhibits (∞ DPI)
│   ├── plates/                    # Optional >=300-DPI feathered plates via `vedit plate`
│   ├── main.typ                   # Rust-native Typst 0.15.1 PDF/UA-1 master
│   └── OUTPUT_UA1.pdf             # 6-gate certified ISO 14289-1 publication
└── run_pipeline.sh                # Zero-Python build script latched to `vedit latch` & `vedit audit-all`
```

---

## Atomic Provenance Tuple Schema (Rule 4)

Every scalar published in `data/summary_metrics.json["metrics"]` must map to a matching record in `data/provenance_ledger.json`:

```json
{
  "metric_id": "noaa_latest_deseasonalized_ppm",
  "value": 429.98,
  "unit": "ppm",
  "source_document": "data/raw/noaa_co2_mm_mlo.csv",
  "source_locator": "row 2026-10 (deseasonalized)",
  "exact_extracted_quote": "2026,10,2026.7917,426.69,429.98",
  "raw_file_sha256": "163cadae3baa6dec7d3ae066108b50d1018a...",
  "parser_script": "scripts/process_data.py"
}
```

Any metric in `summary_metrics.json` lacking a verified ledger tuple—or whose `raw_file_sha256` diverges from live disk bytes—aborts compilation.

---

## Runnable Zero-Python Templates (`templates/`) & Sovereign Zig CLI (`vedit v0.6.0-zig`)

Adapt the pure Zig 0.17.0 + Typst starter files in `templates/`:

- **`templates/pipeline_template.zig`**: Zero-Python Zig 0.17.0 starter reading immutable `data/raw/` files, enforcing Rule 2 physical/accounting invariants, sealing `data/manifest.sha256`, and emitting 1:1 `data/provenance_ledger.json` + `data/summary_metrics.json`.
- **`templates/build.sh`**: Fail-closed build script executing `zig run scripts/pipeline.zig` → `vedit latch` (Rule 4/6) → `vedit fetch-fonts` → `typst compile --pdf-standard ua-1` → `vedit audit-all --require-ua --verify-links` → `mutool draw` PNG previews.
- **Sovereign Bare-Metal Zig 0.17.0 CLI (`zig/zig-out/bin/vedit`, `v0.6.0-zig`, Zero Python):**
  - `vedit latch <dir>` — pure-Zig SHA-256 manifest + Rule 4 provenance ledger compilation latch.
  - `vedit contrast <pdf>` — background-sampled WCAG 2.1 AA contrast (strips `BT..ET` streams recursively, samples real rendered pixels).
  - `vedit geometry <pdf>` — AABB text collisions, 4-corner glyph ink-core `W`/`W*` clip-path slicing, trim overflow, headline orphan wraps, and photo-overlay texture energy.
  - `vedit coverage <pdf>` — clip-aware dual-key Image XObject visible photography coverage (`>= 50%`).
  - `vedit prose <pdf>` — Rule 10 post-render half-ULP `f64` prose grounding (sign-aware `-45%` vs `+45%`, scientific exponents `10^7`/`10⁷`/`9.7×10⁹`, fullwidth digit normalization).
  - `vedit links <pdf>` — Rule 11 clickable PDF `/URI` coverage + live anti-hallucination verification (DOI Handle Registry `doi.org/api/handles/<doi>`, open-science APIs, live HTTP `GET` rejecting 404/410/403/5xx, Soft-404s, and HTTP-200 bot challenges).
  - `vedit prepress <pdf>` — effective placed DPI (`>= 300`), font embedding, Trim/BleedBox, CMYK GCR TAC (`<= 300%`), PDF/UA-1 tag-tree inspection, and live `veraPDF` ISO 14289-1 certification.
  - `vedit fetch-fonts` — provisions & SHA-256-verifies all 8 SIL-OFL open-source editorial fonts (*Cormorant Garamond*, *Source Serif 4*, *Inter*, *IBM Plex Mono*).
  - `vedit plate <in> <out>` — pure-Zig panoramic center-crop, 10th-percentile black-point alignment to exact canvas RGB (`#07090F`), and raised-cosine edge feathering into Baseline 4:4:4 JPEG or compressed PNG at `>= 300 DPI`.
  - `vedit spreads <pdf> <out_dir>` — pure-Zig facing-spread contact-sheet composer (`[2|3]`, `[4|5]`) with central spine shadow.
  - `vedit inject` / `vedit init` / `vedit audit-all` — dissect any reference PDF into `archetypes/<slug>/`, scaffold a zero-Python Typst PDF/UA-1 project, and execute the full 6-gate court in one call (verified by `zig build test && zig build test-court` in `Debug` and `--release=safe`).

## Rule 11 Pre-Finalization Agent Protocol (Zero Hallucinated Links)

Before delivering ANY compiled PDF report to the user, the authoring agent MUST execute this closed loop:

1. **Every resource must be a clickable link:**
   - **Typst:** `#link("https://doi.org/10.1038/nature02417")[Koch et al. (2004)]` (and use a bibliography style that renders clickable DOIs/URLs, e.g. `style: "ieee"`, or explicit `#link(...)` references).
   - **HTML / WeasyPrint:** `<a href="https://doi.org/...">Source Label</a>`.
   - **ReportLab:** `canvas.linkURL("https://...", (x0, y0, x1, y1), relative=0)` on every citation/source label.
2. **Visit and verify EVERY link live before finalizing:**
   ```bash
   vedit links report/OUTPUT.pdf --citations data/background_citations.json --ledger data/provenance_ledger.json
   ```
3. **Inspect the resolved `<title>` / DOI target of every single `[OK]` entry** to confirm the real destination matches the cited claim (not an unrelated homepage or wrong paper).
4. **Fix or remove any failing link (`[!]`)** — if a URL returns `404`, `Soft-404`, `HALLUCINATED_DOI`, `BOT_CHALLENGE_UNVERIFIED`, or `UNLINKED_TEXT_RESOURCE`, **never ignore or fabricate**; find the true canonical URL/DOI from the primary registry or remove the unverified claim before re-compiling.

## Compilation Latch Pattern (Rule 6 — Zero Python)

Every PDF build script MUST gate Typst compilation behind `vedit latch`:

```bash
set -euo pipefail
vedit latch "$PROJECT_DIR"
typst compile --pdf-standard ua-1 --root "$PROJECT_DIR" --font-path "$FONT_DIR" "$PROJECT_DIR/report/main.typ" "$OUT_PDF"
vedit audit-all "$OUT_PDF" --ledger "$PROJECT_DIR/data/provenance_ledger.json" --summary "$PROJECT_DIR/data/summary_metrics.json" --citations "$PROJECT_DIR/data/background_citations.json" --manifest "$PROJECT_DIR/data/manifest.sha256" --require-ua --verify-links
```
