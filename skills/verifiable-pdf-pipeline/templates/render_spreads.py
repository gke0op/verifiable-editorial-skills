#!/usr/bin/env python3
"""Drop-in Facing-Spread Contact-Sheet Renderer for print magazines & monographs (PyMuPDF + Pillow).

Renders interior facing pages ([2|3], [4|5], ...) side by side on an archival desk mat with a
subtle spine-gutter shadow so spread pacing and cross-gutter rhythm can be visually QA'd cleanly.

Usage:
  python3 render_spreads.py path/to/magazine.pdf --out-dir previews/ [--dpi 150] [--width 1600]
"""

from __future__ import annotations

import argparse
from pathlib import Path
from PIL import Image, ImageDraw
import fitz  # PyMuPDF


def render_page_image(page: fitz.Page, dpi: int) -> Image.Image:
    pix = page.get_pixmap(dpi=dpi, alpha=False)
    return Image.frombytes("RGB", [pix.width, pix.height], pix.samples)


def stitch_spread(im_l: Image.Image, im_r: Image.Image, target_width: int) -> Image.Image:
    pw, ph = im_l.size
    pad = max(24, int(round(pw * 0.04)))
    canvas = Image.new("RGB", (pw * 2 + pad * 2, ph + pad * 2), (229, 224, 214))

    draw = ImageDraw.Draw(canvas)
    draw.rectangle([pad - 2, pad - 2, pad + pw * 2 + 1, pad + ph + 1], outline=(188, 181, 170), width=2)
    canvas.paste(im_l, (pad, pad))
    canvas.paste(im_r, (pad + pw, pad))

    # Realistic soft spine gutter shadow
    spine_x = pad + pw
    overlay = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    half_span = max(12, int(round(pw * 0.016)))
    for dx in range(-half_span, half_span + 1):
        alpha = int(56 * ((1.0 - abs(dx) / (half_span + 1)) ** 2.2))
        if alpha > 0:
            od.line([(spine_x + dx, pad), (spine_x + dx, pad + ph - 1)], fill=(20, 18, 16, alpha))
    od.line([(spine_x, pad), (spine_x, pad + ph - 1)], fill=(15, 14, 12, 85))

    final = Image.alpha_composite(canvas.convert("RGBA"), overlay).convert("RGB")
    if target_width > 0 and final.width > target_width:
        scale = target_width / final.width
        final = final.resize((target_width, int(round(final.height * scale))), Image.Resampling.LANCZOS)
    return final


def main() -> int:
    ap = argparse.ArgumentParser(description="Render facing-spread contact sheets from a print PDF.")
    ap.add_argument("pdf", type=Path, help="Input PDF path.")
    ap.add_argument("--out-dir", type=Path, required=True, help="Output directory for spread_*.png.")
    ap.add_argument("--dpi", type=int, default=150, help="Rasterization DPI before downscaling.")
    ap.add_argument("--width", type=int, default=1600, help="Final spread image width in pixels.")
    args = ap.parse_args()

    args.out_dir.mkdir(parents=True, exist_ok=True)
    doc = fitz.open(args.pdf)
    n = len(doc)

    # Interior facing spreads start at page 2 (index 1) in standard print pagination (Page 1 = Cover)
    count = 0
    for left_1based in range(2, n, 2):
        right_1based = left_1based + 1
        if right_1based > n:
            break
        im_l = render_page_image(doc[left_1based - 1], args.dpi)
        im_r = render_page_image(doc[right_1based - 1], args.dpi)
        spread = stitch_spread(im_l, im_r, args.width)
        out_path = args.out_dir / f"spread_{left_1based:02d}_{right_1based:02d}.png"
        spread.save(out_path, optimize=True)
        print(f"[render_spreads] Wrote {out_path.name} ({spread.width}x{spread.height})")
        count += 1

    doc.close()
    print(f"[render_spreads] Rendered {count} facing spread(s) from {args.pdf.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
