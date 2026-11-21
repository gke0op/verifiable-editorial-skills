#!/usr/bin/env python3
"""
Shared utilities for verifiable PDF compilation:
  - Phase 4 Independent Verification Latch (fail-closed)
  - Inter TTF font discovery & registration with clean Helvetica fallback
  - In-memory headless Tufte sparklines for ReportLab table cells
"""
from __future__ import annotations

import io
import os
import subprocess
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import Image

BASE_DIR = Path(__file__).resolve().parent.parent
VERIFY_SCRIPT = BASE_DIR / "scripts" / "verify_integrity.py"


def engage_verification_latch() -> None:
    """Rule 6: Mechanically latch PDF compilation behind Phase 4 independent verification."""
    print("[*] Engaging Pre-Compilation Verification Latch (Phase 4 Veto Gate)...")
    res = subprocess.run(
        [sys.executable, str(VERIFY_SCRIPT)],
        capture_output=True,
        text=True,
        check=False,
    )
    if res.returncode != 0:
        print("[!] COMPILATION ABORTED: Independent integrity verification FAILED!", file=sys.stderr)
        print(res.stdout, file=sys.stderr)
        print(res.stderr, file=sys.stderr)
        sys.exit(1)
    print("[OK] Verification latch passed. Proceeding to PDF typesetting.")


def register_editorial_fonts() -> dict[str, str]:
    """
    Discover and register Inter TTF weights if available on disk or via INTER_FONT_DIR.
    Returns a clean role -> fontName mapping, falling back gracefully to Helvetica.
    """
    search_dirs: list[Path] = []
    env_dir = os.environ.get("INTER_FONT_DIR")
    if env_dir:
        search_dirs.append(Path(env_dir))
    search_dirs.extend(
        [
            BASE_DIR / "fonts",
            Path.home() / "Library" / "Fonts",
            Path("/Library/Fonts"),
            Path("/usr/share/fonts/truetype/inter"),
        ]
    )

    weight_files = {
        "regular": "Inter-Regular.ttf",
        "semibold": "Inter-SemiBold.ttf",
        "bold": "Inter-Bold.ttf",
        "italic": "Inter-Italic.ttf",
        "bold_italic": "Inter-BoldItalic.ttf",
    }

    found: dict[str, Path] = {}
    for directory in search_dirs:
        if not directory.is_dir():
            continue
        for role, fname in weight_files.items():
            if role not in found and (directory / fname).is_file():
                found[role] = directory / fname

    if {"regular", "bold", "italic", "bold_italic"}.issubset(found.keys()):
        pdfmetrics.registerFont(TTFont("Inter-Regular", str(found["regular"])))
        pdfmetrics.registerFont(TTFont("Inter-Bold", str(found["bold"])))
        pdfmetrics.registerFont(TTFont("Inter-Italic", str(found["italic"])))
        pdfmetrics.registerFont(TTFont("Inter-BoldItalic", str(found["bold_italic"])))
        semi_name = "Inter-Bold"
        if "semibold" in found:
            pdfmetrics.registerFont(TTFont("Inter-SemiBold", str(found["semibold"])))
            semi_name = "Inter-SemiBold"
        pdfmetrics.registerFontFamily(
            "Inter-Regular",
            normal="Inter-Regular",
            bold="Inter-Bold",
            italic="Inter-Italic",
            boldItalic="Inter-BoldItalic",
        )
        return {
            "regular": "Inter-Regular",
            "semibold": semi_name,
            "bold": "Inter-Bold",
            "italic": "Inter-Italic",
            "bold_italic": "Inter-BoldItalic",
            "mono": "Courier",
        }

    return {
        "regular": "Helvetica",
        "semibold": "Helvetica-Bold",
        "bold": "Helvetica-Bold",
        "italic": "Helvetica-Oblique",
        "bold_italic": "Helvetica-BoldOblique",
        "mono": "Courier",
    }


def make_tufte_sparkline(
    values: list[float],
    width_pt: float = 64.0,
    height_pt: float = 15.0,
    line_color: str = "#64748b",
    up_color: str = "#dc2626",
    down_color: str = "#059669",
) -> Image:
    """Render an in-memory 300-DPI transparent Tufte sparkline for ReportLab table cells."""
    fig, ax = plt.subplots(figsize=(width_pt / 72.0, height_pt / 72.0), dpi=300)
    fig.patch.set_alpha(0.0)
    ax.set_facecolor("none")

    x = list(range(len(values)))
    ax.plot(x, values, color=line_color, linewidth=1.05)

    end_col = down_color if values[-1] < values[0] else up_color
    ax.scatter([x[0]], [values[0]], color=line_color, s=4.5, zorder=4)
    ax.scatter([x[-1]], [values[-1]], color=end_col, s=8.0, zorder=5)

    ymin, ymax = min(values), max(values)
    pad = max((ymax - ymin) * 0.22, 1e-6)
    ax.set_ylim(ymin - pad, ymax + pad)
    ax.set_xlim(-0.8, len(values) - 0.2)
    ax.axis("off")
    plt.subplots_adjust(left=0.02, right=0.96, top=0.92, bottom=0.08)

    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=300, transparent=True)
    plt.close(fig)
    buf.seek(0)
    return Image(buf, width=width_pt, height=height_pt)
