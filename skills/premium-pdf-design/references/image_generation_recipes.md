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
3. Keep all quantitative labels and titles inside ReportLab/SVG typography—never ask an image generator to render data labels or numbers.
