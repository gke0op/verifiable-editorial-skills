# FELIS MUNDI — Cats Around the World (Full-Bleed Editorial Magazine Demo)

An 8-page Letter-portrait (`612 × 792 pt`) preserved archival photojournalism showcase demonstrating **cohesive Nano Banana stock photography generation** + **edge-to-edge full-bleed print typography** (originally typeset in `Didot` / `Charter` / `Inter`; audited via zero-Python Zig `vedit`).

## Architectural & Audit Highlights
- **11 Cohesive Nano Banana Plates:** Generated under a single locked **Master Photographic Film Identity Core** (`Leica M11 · 50mm f/1.4 Summilux · Kodak Portra 400 analog grade · natural light · zero text/watermarks/borders`) with intentional negative-space framing for overlaid headlines and colophons.
- **Exact Clip-Aware Photo Coverage Gate (`vedit coverage`, via `run_pipeline.sh`):** Replaces embedded PDF image XObjects with two distinct solid key colors in-memory and diffs rasterizations—proving exact visible photo area after all clip paths and white gutters. Every single page exceeds `>= 50%` visible full-bleed photography (`61.1%` min, `78.7%`–`80.6%` avg, touching `>= 2` trim edges per page):
  - Page 1 (Istanbul Cover): `99.3%` (`BLRT`)
  - Page 2 (Istanbul Cihangir): `61.1%` (`LRT`)
  - Page 3 (Kyoto Bobtail Split): `64.7%` (`BRT`)
  - Page 4 (Chefchaouen Blue Alleys): `99.6%` (`BLRT`)
  - Page 5 (Santorini Diptych): `75.6%` (`BLRT`)
  - Page 6 (Reykjavík Winter Coats): `67.7%` (`BLR`)
  - Page 7 (Rome · Tokyo · Lima Triptych): `76.8%` (`LRT`)
  - Page 8 (Closing Dusk Plate & SHA-256 Colophon): `99.9%` (`BLRT`)

## Verify Locally (Zero Python)

```bash
# Preserved archival photojournalism showcase — audit clip-aware photo coverage & structural telemetry via Zig vedit:
bash demos/felis-mundi-magazine/run_pipeline.sh
```
