---
name: verifiable-pdf-pipeline
description: >-
  Turnkey open-data verification pipeline for publication-grade PDF presentations, institutional reports, and
  scientific monographs. Enforces 10 machine-checked anti-cheat rules: zero hardcoded data, SHA-256 raw manifests,
  Pydantic domain bounds, atomic provenance ledgers, AST anti-circular verification, explicit N/A handling,
  compilation latching, scientific taxonomy verification, post-render Rule 10 PDF prose grounding (signed &
  superscript-safe), geometric collision/clipping linting, background-sampled WCAG contrast, print pre-press
  preflight (effective DPI, embedded fonts, bleed/trim boxes, CMYK TAC, live veraPDF ISO 14289-1 PDF/UA-1),
  and cross-platform SIL-OFL font provisioning via the `vedit` CLI.
---

# Verifiable Factual PDF & Data Presentation Pipeline

This skill defines a domain-agnostic, fail-closed engineering pipeline for producing high-stakes data presentations, institutional whitepapers, scientific natural-history monographs, and dual-target interactive web essays. It enforces an absolute **Zero-Mock Data Invariant** backed by automated verification gates (`verifiable-editorial` / `vedit` CLI) and an adversarial sabotage `pytest` suite.

Every published number must be streamed from genuine upstream sources into immutable raw files, validated against physical and accounting invariants, registered in an atomic provenance ledger, independently re-parsed from raw inputs without circular assertions, grounded post-render inside final PDF prose (Rule 10), and audited for geometric collisions, clip-path slicing, and background-sampled WCAG 2.1 contrast.

---

## The 10 Inviolable Anti-Cheat Rules

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
│         Strict Pydantic bounds (physics, accounting, time).            │
│         Out-of-bounds values fail closed immediately (exit 1).         │
├────────────────────────────────────────────────────────────────────────┤
│ Rule 3: Anti-Circular Verification Law                                 │
│         AST linter bans asserting variables against numeric literals.  │
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
│         PDF compilers invoke verify_integrity.py and abort on failure. │
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
│         Every quantitative number extracted from the FINAL compiled    │
│         PDF bytes must trace back to `provenance_ledger.json`,         │
│         `summary_metrics.json`, or an explicit DOI-backed entry in     │
│         `data/background_citations.json` — closing narrative drift.    │
└────────────────────────────────────────────────────────────────────────┘
```

---

## The 5-Phase Fail-Closed Workflow

```
[ Primary Open Sources / REST APIs / Official Datasets ]
                        │
                        ▼  (scripts/fetch_data.py)
┌────────────────────────────────────────────────────────┐
│ PHASE 1: Raw Ingestion & Deduplicated SHA-256 Sealing  │
│ - Stream verbatim upstream bytes into data/raw/        │
│ - Write sorted, deduplicated data/manifest.sha256      │
│ - Zero manual numeric dictionaries or hand-edited CSVs │
└────────────────────────────────────────────────────────┘
                        │
                        ▼  (scripts/validate_reality.py)
┌────────────────────────────────────────────────────────┐
│ PHASE 2: Reality & Invariant Compiler                  │
│ - Pydantic v2 models enforcing domain physics bounds   │
│ - Accounting identities (e.g. total / pop == per_cap)  │
│ - Explicit sentinel-to-null mapping (e.g. -9.99 -> NA) │
└────────────────────────────────────────────────────────┘
                        │
                        ▼  (scripts/process_data.py)
┌────────────────────────────────────────────────────────┐
│ PHASE 3: Synthesis & Atomic Provenance Registration    │
│ - Compute aggregates strictly from validated raw rows  │
│ - Register 100% of metrics in provenance_ledger.json   │
│ - Emit sealed data/summary_metrics.json                │
└────────────────────────────────────────────────────────┘
                        │
                        ▼  (scripts/verify_integrity.py)
┌────────────────────────────────────────────────────────┐
│ PHASE 4: Independent External Verification (Veto Gate) │
│ - Re-hash every file in data/raw/ vs manifest.sha256   │
│ - Python AST check banning hardcoded literal asserts   │
│ - Confirm 100% provenance coverage + independent parse │
│ - Must exit 0 before Phase 5 compilation unlocks       │
└────────────────────────────────────────────────────────┘
                        │
                        ▼  (report/compile_*.py + audit_pdf.py)
┌────────────────────────────────────────────────────────┐
│ PHASE 5: Vector Visualization, Typesetting & Visual QA │
│ - Compilation script mechanically latched to Phase 4   │
│ - Render 300-DPI transparent vector charts             │
│ - PyMuPDF bounding-box fill & overflow audit + PNGs    │
└────────────────────────────────────────────────────────┘
```

---

## Standard Project Scaffold

```
<project_root>/
├── data/
│   ├── raw/                       # Immutable upstream files (.json, .csv, .pdf, .parquet)
│   ├── manifest.sha256            # Sorted, deduplicated SHA-256 manifest of data/raw/
│   ├── provenance_ledger.json     # Atomic provenance records for every published metric
│   ├── processed_panel.csv        # Cleaned, parser-extracted analytical table
│   └── summary_metrics.json       # Audited aggregates backed 1:1 by provenance_ledger.json
├── scripts/
│   ├── fetch_data.py              # Phase 1: stream upstream -> data/raw/ + manifest.sha256
│   ├── validate_reality.py        # Phase 2: Pydantic domain bounds + accounting identities
│   ├── process_data.py            # Phase 3: compute metrics + register provenance tuples
│   ├── verify_integrity.py        # Phase 4: independent raw re-parse + AST Rule 3 linter
│   ├── generate_charts.py         # Phase 5a: 300-DPI charts strictly from summary_metrics.json
│   └── audit_pdf.py               # Phase 5b: PyMuPDF visual fill, overflow & PNG exporter
└── report/
    ├── assets/                    # Rendered 300-DPI chart PNGs
    ├── compile_deck_16x9.py       # 16:9 presentation compiler latched to verify_integrity.py
    └── compile_report_letter.py   # Letter report compiler latched to verify_integrity.py
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

## Runnable Drop-In Templates (`templates/`)

Copy and adapt the tested, production-hardened scripts in `templates/`:

- **`templates/fetch_data.py`**: Atomic HTTP downloader writing a **deduplicated, sorted** `data/manifest.sha256` (safe to re-run without duplicating manifest lines).
- **`templates/validate_reality.py`**: Pydantic v2 domain validator with sentinel-to-null handling and cross-field physics/accounting checks.
- **`templates/verify_integrity.py`**: Full Phase 4 Veto Gate implementing SHA-256 manifest verification, a Python `ast` Rule 3 literal-assertion linter, 100% provenance ledger coverage verification, and raw-source cross-checking.
- **`templates/audit_pdf.py`**: Post-render PyMuPDF (`fitz`) layout auditor measuring combined text blocks, embedded images, and non-background vector drawings across both **Letter portrait (`612×792 pt`)** and **16:9 widescreen (`960×540 pt`)** layouts, plus automatic PNG preview export.
- **`templates/audit_contrast.py`**: Background-sampled **WCAG 2.1 contrast auditor** that strips `BT...ET` text streams in an in-memory PDF clone, renders a text-free background raster at 72 DPI, and samples actual pixels behind every text span's bounding box (accurately auditing dark modes, gradients, and photo overlays).
- **`templates/render_spreads.py`**: Facing-spread contact-sheet assembler that stitches interior facing pages (`[2|3]`, `[4|5]`, …) onto an archival desk mat with a realistic central spine-gutter shadow for true spread-level visual QA.
- **Unified Installable CLI (`pip install -e .` → `vedit`):** Exposes all automated verification & production gates directly from the terminal:
  - `vedit contrast` — background-sampled WCAG 2.1 AA contrast across light, dark, SVG, and PDF/UA-1 tagged streams (`BT/Span` delimiter-safe recursive Form XObject stripping).
  - `vedit geometry` — text collisions, `W n` PDF clip-path slicing, trim overflow, headline orphan wraps, and photo-overlay texture energy.
  - `vedit coverage` — clip-aware dual-key visible photography coverage (`>= 50%`).
  - `vedit prose` — Rule 10 post-render PDF prose-to-ledger grounding (sign-aware so `-45.0%` vs `+45.0%` sign flips fail, superscript-aware so `10^6` never fuses into `106`, DOI/URL/hash-aware).
  - `vedit prepress` — print pre-press & ISO accessibility certification: effective placed DPI (`native_px / placed_inches`, skipping synthetic `xref == 0` CSS soft-masks), embedded font subsetting, `/MediaBox`/`/TrimBox`/`/BleedBox`, simulated CMYK GCR Total Area Coverage (`TAC <= 300%`), pure-PyMuPDF PDF/UA-1 tag-tree inspection, and live **`veraPDF`** (`verapdf --flavour ua1 --format json`) ISO 14289-1 certification.
  - `vedit fetch-fonts` — provisions and SHA-256-verifies 8 cross-platform SIL-OFL open-source fonts (*Cormorant Garamond*, *Source Serif 4*, *Inter*, *IBM Plex Mono*) for bit-exact macOS and Ubuntu Linux builds.
  - `vedit spreads` & `vedit audit-all` — facing-spread contact sheet renderer and one-command multi-gate CI runner, hardened by a **20-test adversarial sabotage, `p2zig` kernel parity, and closed-loop synthesis `pytest` suite (`tests/test_adversarial_gates.py`)**.
- **Sovereign Bare-Metal Zig 0.17.0 Agent Harness (`zig/zig-out/bin/vedit`, `v0.5.0-zig`):** Zero-Python native CLI with **100% 5-Gate Court parity**, compiling all **12** core math/audit/dissection/coverage kernels via `p2zig --strict` (`verifiable_editorial/kernels_p2zig_src.py` → `zig/src/kernels_p2zig.zig`) + pure-C `mutool` + live `veraPDF`. Exposes `vedit latch` (pure-Zig SHA-256 + Rule 4 verification), `vedit contrast`, `vedit geometry` (incl. pure-Zig `W`/`W*` clip-path character slicing), `vedit coverage` (pure-Zig dual-key image XObject rewriting), `vedit prose` (Rule 10 signed+superscript), `vedit prepress` (live `veraPDF`), `vedit audit-all` (`--plate-pages`, `--json`), **PDF Sample Dissection & Archetype Injection** (`vedit inject <sample.pdf> --name <slug>`), and zero-Python project scaffolding (`vedit init <dir> --archetype <slug>`).

## Compilation Latch Pattern (Rule 6)

Every PDF builder must gate execution behind `verify_integrity.py`:

```python
import subprocess
import sys
from pathlib import Path

def engage_verification_latch(verify_script: Path) -> None:
    res = subprocess.run([sys.executable, str(verify_script)], capture_output=True, text=True, check=False)
    if res.returncode != 0:
        print("[!] COMPILATION ABORTED: Phase 4 integrity verification failed.", file=sys.stderr)
        print(res.stdout, file=sys.stderr)
        print(res.stderr, file=sys.stderr)
        sys.exit(1)
```
