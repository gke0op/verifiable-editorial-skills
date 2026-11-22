# FELIS MUNDI — Cats Around the World (Full-Bleed Editorial Magazine Demo)

An 8-page Letter-portrait (`612 × 792 pt`) editorial photojournalism magazine demonstrating **cohesive Nano Banana stock photography generation** + **edge-to-edge full-bleed print typography** (`Didot` / `Charter` / `Inter` via WeasyPrint 67.0).

## Architectural & Audit Highlights
- **11 Cohesive Nano Banana Plates:** Generated under a single locked **Master Photographic Film Identity Core** (`Leica M11 · 50mm f/1.4 Summilux · Kodak Portra 400 analog grade · natural light · zero text/watermarks/borders`) with intentional negative-space framing for overlaid headlines and colophons.
- **Exact Clip-Aware Photo Coverage Gate (`scripts/audit_magazine.py`):** Replaces embedded PDF image XObjects with two distinct solid key colors in-memory and diffs 72-DPI rasterizations—proving exact visible photo area after all CSS `object-fit: cover` clip paths and white gutters. Every single page exceeds `>= 50%` visible full-bleed photography (`61.1%` min, `80.6%` avg, touching `>= 2` trim edges per page):
  - Page 1 (Istanbul Cover): `99.3%` (`BLRT`)
  - Page 2 (Istanbul Cihangir): `61.1%` (`LRT`)
  - Page 3 (Kyoto Bobtail Split): `64.7%` (`BRT`)
  - Page 4 (Chefchaouen Blue Alleys): `99.6%` (`BLRT`)
  - Page 5 (Santorini Diptych): `75.6%` (`BLRT`)
  - Page 6 (Reykjavík Winter Coats): `67.7%` (`BLR`)
  - Page 7 (Rome · Tokyo · Lima Triptych): `76.8%` (`LRT`)
  - Page 8 (Closing Dusk Plate & SHA-256 Colophon): `99.9%` (`BLRT`)

## Reproduce Locally

```bash
# On macOS with Homebrew Pango/GObject, run_pipeline.sh sets DYLD_FALLBACK_LIBRARY_PATH automatically
# Optional: export INTER_FONT_DIR=/path/to/inter/ttf
bash demos/felis-mundi-magazine/run_pipeline.sh
```
