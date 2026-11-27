# Multi-Asset Coherent AI Image Generation Recipes

This guide provides tested prompt formulas for generating visually unified editorial illustrations (Cover Hero, Architecture Blueprint, Benchmark HUD, and Deployment Roadmap) across a publication without aesthetic drift.

*(Note: Never use AI image generation to fabricate quantitative charts or data plots—all numeric exhibits must be rendered deterministically via code from audited `data/summary_metrics.json`.)*

---

## 1. The Core Continuity Problem
Generating multiple illustrations independently causes visual drift across pages:
- Clashing palettes (pastel tones on page 1, saturated neon on page 4).
- Mixed rendering paradigms (3D clay mixed with flat vector schematics and photography).
- Inconsistent line weights and lighting models.

Apply the **Fixed Spec Strategy**: lock global visual tokens inside the **Master Identity Core** and vary only the **Shot Directive**.

---

## 2. Master Identity Core (Static Anchor)

Prepend this block verbatim to every editorial illustration prompt in the same publication:

```text
[AESTHETIC]: High-end institutional technical editorial illustration, dark-mode precision vector schematic, Swiss graphic design influence, clean technical minimalism.
[COLOR PALETTE]: Deep obsidian navy background (#0b0f19), slate structural scaffolding (#1e293b), electric cobalt data lines (#38bdf8), amber verification highlights (#f59e0b), crisp white typography accents (#f8fafc).
[LIGHTING]: Cinematic chiaroscuro edge lighting, subtle directional conduit glow, sharp contrast, zero ambient haze.
[COMPOSITION]: Orthographic or 30-degree isometric projection, razor-sharp vector geometry, expansive negative space, zero photorealistic noise, zero garbled text.
```

---

## 3. Four Standard Conceptual Illustration Prompts

### Asset 1: Cover Hero Artwork (`16:9`)
```text
[SHOT DIRECTIVE]: Panoramic abstract topology of interconnected institutional telemetry nodes and directional cobalt data conduits over deep obsidian negative space. Minimalist, authoritative, editorial cover composition with quiet upper-left breathing room for typography.
```

### Asset 2: 3-Tier System Architecture Schematic (`16:9` or `4:3`)
```text
[SHOT DIRECTIVE]: Isometric 30-degree exploded schematic of a 3-tier verification pipeline: Tier 1 Ingestion Stream, Tier 2 Validation & Audit Core, Tier 3 Publication Compiler. Connected by crisp directional bus lines and amber checkpoint gates. Zero embedded text labels.
```

### Asset 3: Risk & Telemetry Control Plane (`16:9` or `4:3`)
```text
[SHOT DIRECTIVE]: Abstract orthographic schematic of concentric calibration rings, structural grid planes, and clean geometric balance vectors on deep obsidian navy. Precision scientific diagram aesthetic, zero fake numbers or text.
```

### Asset 4: Phased Deployment Horizon (`16:9`)
```text
[SHOT DIRECTIVE]: Horizontal orthographic progression of four sequential geometric milestone nodes connected by a luminous cobalt rail and amber verification gates across clean dark negative space. Zero text labels.
```

---

## 4. Reference Image Chaining Protocol
When your image generation tool supports reference-image conditioning:
1. Generate the **Cover Hero** first and inspect it visually.
2. Pass the approved Cover Hero image as the style/palette reference when generating subsequent conceptual illustrations.
3. Keep all quantitative labels and titles inside Typst/SVG typography—never ask an image generator to render data labels or numbers.

---

## 5. Cohesive Editorial Stock Photography Suite (Full-Bleed Magazine Mode)

When generating a multi-page photojournalism magazine or lifestyle feature (instead of technical vector schematics), replace the vector Identity Core with a locked **Master Photographic Film Identity Core** so every location across the issue looks shot on the same camera body, lens, and film stock.

### Master Photographic Film Identity Core (Static Anchor)
Prepend verbatim to every photographic prompt in the same issue:

```text
[PHOTOGRAPHIC IDENTITY]: Authentic editorial travel photojournalism, shot on Leica M11 with 50mm f/1.4 Summilux lens, Kodak Portra 400 analog color grade, natural directional sunlight and soft ambient bounce, organic 35mm film grain, shallow editorial depth of field, tactile stonework/wood/fabric textures, unposed candid realism.
[STRICT NEGATIVE GUARD]: Zero text, zero letters, zero signage typography, zero watermarks, zero white borders, zero frames, zero HDR oversaturation, zero CGI gloss.
```

### Negative-Space Framing Rules for Overlaid Typography
Design every full-bleed plate with intentional **quiet negative-space pockets** *inside the photograph itself* so headlines and colophons never require opaque boxes:
- **Cover Plate (`3:4` portrait for `612×792 pt` trim — only ~3% crop):** Keep the upper `32%` serene hazy sky or calm backdrop for the centered wide-tracked serif masthead (`FELIS MUNDI` / `KINFOLK` style), place the hero subject in the lower-middle center, and leave shadowed texture in the bottom-left and bottom-right corners for the coverline and miniature TOC.
- **Full-Bleed Essay Plate (`3:4`):** Frame a matte shadowed wall, deep foliage, or calm water across one upper corner (`~35–40%` width) to hold flush-left white display serif typography with zero scrim box.
- **Top Panoramic Diptych Opener (`16:9`):** Anchor the subject firmly on the right third (`object-position: 78% 45%`), leaving open sky/horizon on the upper-left for clean white display typography.
- **Closing Plate & Colophon (`3:4`):** Compose the subject in the middle horizontal band (e.g., on a sunlit window sill or table) with a deep, uncluttered shadowed lower `38%` that acts as a natural editorial colophon bed for white serif credits and a SHA-256 plate ledger.

### Aspect-Ratio-to-Spread Matching (Minimal Crop Discipline)
| Spread Slot (`612×792 pt` Letter Trim) | Recommended Generation Ratio | Typical Crop Loss |
| :--- | :--- | :--- |
| Full-bleed page (`612×792 pt`) | `3:4` (`896×1200`) | `~3%` |
| Top or bottom `60%–68%` full-bleed (`612×484–535 pt`) | `4:3` (`1200×896`) | `~2–7%` |
| Asymmetric `65%` vertical bleed (`396×792 pt`) or `55%` bottom inset | `3:4` (`896×1200`) | `~5–20%` (pin focal subject via `object-position`) |
| Panoramic diptych top band (`612×364 pt`) | `16:9` (`1376×768`) | `~6%` |

### Transparency & SHA-256 Asset Sealing
Always credit AI-generated stock photography openly in both the page credits and colophon (`Photograph by Nano Banana Studio · AI Editorial Photography`), and seal every plate in `data/manifest.sha256` and `data/photo_credits.json` with exact pixel dimensions, aspect ratio, and SHA-256 digest (via Zig 0.17 `std.crypto.hash.sha2.Sha256` and `vedit latch`).
