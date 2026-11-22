"""Facing-spread contact-sheet renderer for magazines and print monographs (PyMuPDF + Pillow)."""

from __future__ import annotations

from pathlib import Path
from PIL import Image, ImageDraw
import fitz  # PyMuPDF


def _render_page(page: fitz.Page, dpi: int) -> Image.Image:
    pix = page.get_pixmap(dpi=dpi, alpha=False)
    return Image.frombytes("RGB", [pix.width, pix.height], pix.samples)


def stitch_spread(im_l: Image.Image, im_r: Image.Image, target_width: int = 1600) -> Image.Image:
    pw, ph = im_l.size
    pad = max(24, int(round(pw * 0.04)))
    canvas = Image.new("RGB", (pw * 2 + pad * 2, ph + pad * 2), (229, 224, 214))

    draw = ImageDraw.Draw(canvas)
    draw.rectangle([pad - 2, pad - 2, pad + pw * 2 + 1, pad + ph + 1], outline=(188, 181, 170), width=2)
    canvas.paste(im_l, (pad, pad))
    canvas.paste(im_r, (pad + pw, pad))

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


def render_spreads(pdf_path: Path | str, out_dir: Path | str, dpi: int = 150, width: int = 1600) -> list[Path]:
    pdf_path = Path(pdf_path)
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    doc = fitz.open(pdf_path)
    n = len(doc)
    written: list[Path] = []
    for left_1based in range(2, n, 2):
        right_1based = left_1based + 1
        if right_1based > n:
            break
        im_l = _render_page(doc[left_1based - 1], dpi)
        im_r = _render_page(doc[right_1based - 1], dpi)
        spread = stitch_spread(im_l, im_r, width)
        out_path = out_dir / f"spread_{left_1based:02d}_{right_1based:02d}.png"
        spread.save(out_path, optimize=True)
        written.append(out_path)
    doc.close()
    return written
