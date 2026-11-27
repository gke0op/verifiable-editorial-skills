# BOTANICA VERIDICA — Architecture of Extreme Plants (Scientific Report × Learning Magazine Crossover)

A 10-page (`612 × 792 pt`, 4 true facing spreads + cover + dichotomous key colophon) **natural-history scientific monograph and full-bleed learning magazine crossover** (*Kew* × *DK The Science of Plants* × *National Geographic* × *Scientific American*).

## Live Open-Science Data & Anti-Cheat Guarantees
- **100% Live Biodiversity Registries (Zero Mocks, Zero Auth):**
  - **GBIF API v1 (`api.gbif.org/v1`)**: Authoritative binomials & botanical authorities, Phylum→Family taxonomy, live IUCN Red List codes (with unlinked `NOT_EVALUATED` statuses preserved transparently as `[N/A]` under Rule 5), `113,962` global occurrences, `11,050` museum preserved herbarium sheets, country facets, and `720` live georeferenced coordinates plotted directly onto a pure-vector SVG world map.
  - **iNaturalist API v1 (`api.inaturalist.org/v1`)**: `112,408` research-grade observations + live 12-month **flowering phenology histograms** (`term_id=12&term_value_id=13` — empirically showing `0` flowers across the 3 gymnosperms vs `662` seasonal bloom records across the 3 angiosperms).
  - **Open Tree of Life API v3 (`api.opentreeoflife.org/v3`)**: Live TNRS resolution + induced Newick phylogenetic subtree parsed deterministically into a pure-vector inline SVG cladogram.
- **Hybrid Zero-Text Nano Banana Plates × Pure-Vector SVG Anatomy Overlays:** 8 cohesive botanical studio/field plates generated with zero embedded text, overlaid with deterministic 90° elbow anatomy leader lines, anchor dots, circular zoom medallions, and metric scale bars.
- **6-Gate Sovereign Zig Audit (`vedit`, via `run_pipeline.sh`):**
  1. **Rule 4/6 SHA-256 Integrity Latch (`vedit latch`):** Verifies `52/52` SHA-256 sealed raw files and `83` 1:1 provenance tuples.
  2. **Composited 144/360-DPI WCAG 2.1 Contrast Gate (`vedit contrast`):** Strips PDF text streams in-memory to sample real rendered background pixels behind all `677` spans (`0` violations; worst ratio `4.98:1`).
  3. **Geometry & Bezier Clip-Path Gate (`vedit geometry`):** Confirms `0` collisions, `0` clipped glyphs, `0` trim overflows, and `0` orphans.
  4. **Exact Clip-Aware Visible Plate Coverage Gate (`vedit coverage`):** Dual-key pixel-diff confirms `>= 50%` visible photography across the cover and all 6 species plates (pages `1,4-9`).
  5. **Rule 10 Prose Grounding (`vedit prose`) & Rule 11 Clickable Links (`vedit links --offline`):** Verifies `219/219` numerals and `18` clickable link annotations (`0` failures), alongside preserved `BOTANICA_VERIDICA_PREPRESS.pdf` (3mm bleed + crop marks) and facing-spread contact sheets (`previews/spread_02_03.png` … `spread_08_09.png`).

## Verify Locally (Zero Python)

```bash
# Preserved archival visual showcase — re-verify all 52 SHA-256 raw files & all 6 sovereign Zig vedit gates:
bash demos/botanica-veridica/run_pipeline.sh
```
