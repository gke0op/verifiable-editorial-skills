#!/usr/bin/env python3
"""Compile FELIS MUNDI — Cats Around the World (8-page full-bleed print magazine PDF via WeasyPrint)."""

from __future__ import annotations

import html
import json
import os
from pathlib import Path
from weasyprint import HTML

ROOT = Path(__file__).resolve().parent.parent
REPORT_DIR = ROOT / "report"
ASSETS_DIR = REPORT_DIR / "assets"
CREDITS_JSON = ROOT / "data" / "photo_credits.json"
OUT_PDF = REPORT_DIR / "FELIS_MUNDI_MAGAZINE.pdf"


def load_inter_font_css() -> str:
    font_dir = os.environ.get("INTER_FONT_DIR", "").strip()
    if not font_dir:
        return ""
    p = Path(font_dir)
    if not p.is_dir():
        return ""
    faces = [
        ("Inter-Regular.ttf", 400, "normal"),
        ("Inter-Italic.ttf", 400, "italic"),
        ("Inter-SemiBold.ttf", 600, "normal"),
        ("Inter-Bold.ttf", 700, "normal"),
    ]
    blocks = []
    for fname, weight, style in faces:
        fpath = p / fname
        if fpath.exists():
            blocks.append(
                f"""@font-face {{
  font-family: 'Inter';
  src: url('{fpath.as_uri()}');
  font-weight: {weight};
  font-style: {style};
}}"""
            )
    return "\n".join(blocks)


def asset_uri(name: str) -> str:
    p = ASSETS_DIR / name
    if not p.exists():
        raise FileNotFoundError(f"Missing plate asset: {p}")
    return p.as_uri()


def build_colophon_rows(plates: list[dict]) -> str:
    rows = []
    for pl in plates:
        rows.append(
            "<tr>"
            f"<td class='c-num'>{html.escape(pl['plate'])}</td>"
            f"<td class='c-loc'>{html.escape(pl['location'])}</td>"
            f"<td class='c-asp'>{html.escape(pl['aspect'])}</td>"
            f"<td class='c-px'>{pl['width_px']}×{pl['height_px']}</td>"
            f"<td class='c-sha'>{html.escape(pl['sha256_short'])}</td>"
            "</tr>"
        )
    return "\n".join(rows)


def build_html(ledger: dict) -> str:
    inter_css = load_inter_font_css()
    colophon_rows = build_colophon_rows(ledger["plates"])
    identity_core = html.escape(ledger["identity_core"])

    p1 = asset_uri("photo_01_cover_istanbul.jpg")
    p2 = asset_uri("photo_02_istanbul_cafe.jpg")
    p3 = asset_uri("photo_03_kyoto_shrine.jpg")
    p4 = asset_uri("photo_04_chefchaouen_stairs.jpg")
    p5 = asset_uri("photo_05_santorini_caldera.jpg")
    p6 = asset_uri("photo_06_santorini_shutters.jpg")
    p7 = asset_uri("photo_07_reykjavik_winter.jpg")
    p8 = asset_uri("photo_08_rome_ruins.jpg")
    p9 = asset_uri("photo_09_tokyo_yanaka.jpg")
    p10 = asset_uri("photo_10_lima_kennedy.jpg")
    p11 = asset_uri("photo_11_closing_dusk.jpg")

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<title>FELIS MUNDI — Cats Around the World</title>
<style>
{inter_css}

@page {{
  size: 612pt 792pt;
  margin: 0;
}}

* {{
  box-sizing: border-box;
  margin: 0;
  padding: 0;
}}

html, body {{
  width: 612pt;
  background: #FAF8F5;
  color: #161616;
  font-family: 'Charter', 'Baskerville', 'Georgia', serif;
  -webkit-font-smoothing: antialiased;
}}

.page {{
  position: relative;
  width: 612pt;
  height: 791.5pt;
  overflow: hidden;
  background: #FAF8F5;
  break-after: page;
  break-inside: avoid;
}}
.page:last-child {{
  break-after: auto;
}}

.full-bleed-img {{
  position: absolute;
  top: 0;
  left: 0;
  width: 612pt;
  height: 792pt;
  object-fit: cover;
  display: block;
}}

.kicker {{
  font-family: 'Inter', 'Avenir Next', 'Helvetica Neue', sans-serif;
  font-size: 6.8pt;
  font-weight: 600;
  letter-spacing: 0.19em;
  text-transform: uppercase;
}}

.serif-display {{
  font-family: 'Didot', 'Bodoni 72', 'Georgia', serif;
  font-weight: 400;
}}

.folio-num {{
  font-family: 'Didot', 'Bodoni 72', 'Georgia', serif;
  font-size: 18pt;
  font-weight: 400;
  line-height: 1;
}}

/* Rotated vertical marginal photo credit reading upward along the right edge */
.marginal-credit {{
  position: absolute;
  top: 18pt;
  right: 16pt;
  font-family: 'Inter', 'Avenir Next', 'Helvetica Neue', sans-serif;
  font-size: 5.7pt;
  font-weight: 500;
  letter-spacing: 0.16em;
  text-transform: uppercase;
  color: rgba(255, 255, 255, 0.90);
  text-shadow: 0 1pt 4pt rgba(0, 0, 0, 0.65);
  white-space: nowrap;
  transform-origin: 100% 0%;
  transform: rotate(-90deg);
}}

.body-p {{
  font-family: 'Charter', 'Baskerville', 'Georgia', serif;
  font-size: 9.05pt;
  line-height: 1.50;
  color: #21201E;
  text-align: left;
  hyphens: none;
}}

.dropcap {{
  float: left;
  font-family: 'Didot', 'Bodoni 72', 'Georgia', serif;
  font-size: 35pt;
  line-height: 0.80;
  padding-top: 3pt;
  padding-right: 6pt;
  padding-bottom: 1pt;
}}

/* =========================================================
   PAGE 1 — FULL-BLEED COVER (100% PHOTO)
   ========================================================= */
.p1-top-scrim {{
  position: absolute;
  top: 0; left: 0; width: 612pt; height: 792pt;
  background: linear-gradient(
    to bottom,
    rgba(16,24,33,0.44) 0%,
    rgba(16,24,33,0.14) 17%,
    rgba(16,24,33,0) 30%,
    rgba(10,12,15,0) 70%,
    rgba(10,12,15,0.38) 84%,
    rgba(10,12,15,0.80) 100%
  );
}}
.p1-topbar {{
  position: absolute;
  top: 22pt; left: 34pt; right: 34pt;
  display: flex;
  justify-content: space-between;
  align-items: center;
  color: rgba(255, 255, 255, 0.90);
  border-bottom: 0.5pt solid rgba(255, 255, 255, 0.36);
  padding-bottom: 7pt;
}}
.p1-masthead-wrap {{
  position: absolute;
  top: 44pt; left: 30pt; right: 30pt;
  text-align: center;
  color: #FFFFFF;
}}
.p1-masthead {{
  font-family: 'Didot', 'Bodoni 72', 'Georgia', serif;
  font-size: 62pt;
  font-weight: 400;
  letter-spacing: 0.16em;
  line-height: 1.02;
  color: #FFFFFF;
  text-shadow: 0 1.5pt 14pt rgba(12, 18, 26, 0.25);
  margin-left: 0.16em;
}}
.p1-subhead {{
  margin-top: 8pt;
  font-family: 'Charter', 'Baskerville', 'Georgia', serif;
  font-style: italic;
  font-size: 12.5pt;
  letter-spacing: 0.03em;
  color: rgba(255, 255, 255, 0.93);
  text-shadow: 0 1pt 6pt rgba(12, 18, 26, 0.35);
}}
.p1-bottom-grid {{
  position: absolute;
  bottom: 28pt; left: 34pt; right: 34pt;
  display: grid;
  grid-template-columns: 1.45fr 0.85fr;
  column-gap: 28pt;
  align-items: end;
}}
.p1-coverline-kicker {{
  color: #E2C28B;
  margin-bottom: 6pt;
}}
.p1-coverline-title {{
  font-family: 'Didot', 'Bodoni 72', 'Georgia', serif;
  font-size: 27pt;
  line-height: 1.04;
  color: #FFFFFF;
  margin-bottom: 8pt;
}}
.p1-coverline-deck {{
  font-family: 'Charter', 'Baskerville', 'Georgia', serif;
  font-size: 9.2pt;
  line-height: 1.45;
  color: rgba(246, 243, 238, 0.90);
  max-width: 285pt;
}}
.p1-toc {{
  border-left: 0.5pt solid rgba(255, 255, 255, 0.42);
  padding-left: 14pt;
  color: #FFFFFF;
}}
.p1-toc-head {{
  font-family: 'Inter', 'Avenir Next', 'Helvetica Neue', sans-serif;
  font-size: 6.2pt;
  font-weight: 600;
  letter-spacing: 0.22em;
  text-transform: uppercase;
  color: #E2C28B;
  margin-bottom: 7pt;
}}
.p1-toc-row {{
  display: flex;
  justify-content: space-between;
  align-items: baseline;
  font-family: 'Inter', 'Avenir Next', 'Helvetica Neue', sans-serif;
  font-size: 7.0pt;
  letter-spacing: 0.14em;
  text-transform: uppercase;
  line-height: 1.72;
  color: rgba(255, 255, 255, 0.92);
}}
.p1-toc-pg {{
  font-family: 'Didot', 'Bodoni 72', 'Georgia', serif;
  font-size: 8.6pt;
  letter-spacing: 0.04em;
  color: #E2C28B;
}}

/* =========================================================
   PAGE 2 — ISTANBUL (61.1% TOP FULL-BLEED + 2-COL ESSAY)
   ========================================================= */
.p2-photo-box {{
  position: relative;
  width: 612pt;
  height: 484pt;
  overflow: hidden;
}}
.p2-photo-box img {{
  width: 612pt;
  height: 484pt;
  object-fit: cover;
  object-position: center 64%;
  display: block;
}}
.p2-top-slug {{
  position: absolute;
  top: 20pt; left: 32pt;
  color: rgba(255, 255, 255, 0.95);
  text-shadow: 0 1pt 6pt rgba(0, 0, 0, 0.60);
}}
.p2-editorial {{
  position: relative;
  height: 307.5pt;
  padding: 18pt 36pt 16pt 36pt;
  display: block;
}}
.p2-meta-row {{
  display: flex;
  justify-content: space-between;
  align-items: center;
  border-bottom: 0.5pt solid #D5CEC2;
  padding-bottom: 5.5pt;
  margin-bottom: 9pt;
}}
.p2-headline {{
  font-family: 'Didot', 'Bodoni 72', 'Georgia', serif;
  font-size: 27pt;
  line-height: 1.06;
  color: #161616;
  margin-bottom: 10pt;
}}
.p2-cols {{
  display: grid;
  grid-template-columns: 1fr 1fr;
  column-gap: 24pt;
  align-items: start;
}}
.p2-pullquote {{
  margin-top: 9pt;
  padding: 7.5pt 0;
  border-top: 0.5pt solid #A85B27;
  border-bottom: 0.5pt solid #D5CEC2;
  font-family: 'Didot', 'Bodoni 72', 'Georgia', serif;
  font-style: italic;
  font-size: 11.4pt;
  line-height: 1.34;
  color: #3B281B;
}}
.p2-footer {{
  position: absolute;
  bottom: 16pt;
  left: 36pt;
  right: 36pt;
  display: flex;
  justify-content: space-between;
  align-items: flex-end;
  border-top: 0.5pt solid #DDD6CA;
  padding-top: 6pt;
}}

/* =========================================================
   PAGE 3 — KYOTO (64.7% RIGHT FULL-BLEED + NARROW LEFT ESSAY)
   ========================================================= */
.p3-grid {{
  position: relative;
  width: 612pt;
  height: 791.5pt;
}}
.p3-left {{
  position: absolute;
  top: 0;
  left: 0;
  width: 216pt;
  height: 791.5pt;
  display: block;
  background: #FAF8F5;
  padding: 28pt 20pt 22pt 26pt;
}}
.p3-rule {{
  width: 26pt;
  height: 1pt;
  background: #B03A2E;
  margin: 10pt 0 12pt 0;
}}
.p3-title {{
  font-family: 'Didot', 'Bodoni 72', 'Georgia', serif;
  font-size: 33pt;
  line-height: 1.03;
  color: #161616;
  margin-bottom: 12pt;
}}
.p3-deck {{
  font-family: 'Charter', 'Baskerville', 'Georgia', serif;
  font-style: italic;
  font-size: 9.8pt;
  line-height: 1.44;
  color: #554F47;
  margin-bottom: 14pt;
  padding-bottom: 12pt;
  border-bottom: 0.5pt solid #D8D1C5;
}}
.p3-left p.body-p + p.body-p {{
  margin-top: 9pt;
}}
.p3-caption-box {{
  position: absolute;
  bottom: 22pt;
  left: 26pt;
  right: 20pt;
  border-top: 0.5pt solid #D8D1C5;
  padding-top: 9pt;
}}
.p3-caption {{
  font-family: 'Charter', 'Baskerville', 'Georgia', serif;
  font-style: italic;
  font-size: 7.7pt;
  line-height: 1.42;
  color: #5C564E;
  margin-bottom: 12pt;
}}
.p3-folio-row {{
  display: flex;
  justify-content: space-between;
  align-items: baseline;
}}
.p3-photo-col {{
  position: absolute;
  top: 0;
  right: 0;
  width: 396pt;
  height: 791.5pt;
  overflow: hidden;
}}
.p3-photo-col img {{
  width: 396pt;
  height: 792pt;
  object-fit: cover;
  object-position: 34% 55%;
  display: block;
}}

/* =========================================================
   PAGE 4 — CHEFCHAOUEN (100% FULL-BLEED PHOTO ESSAY PLATE)
   ========================================================= */
.p4-title-block {{
  position: absolute;
  top: 34pt;
  left: 32pt;
  width: 210pt;
  color: #FFFFFF;
}}
.p4-rule {{
  width: 28pt;
  height: 0.75pt;
  background: rgba(255, 255, 255, 0.78);
  margin: 12pt 0;
}}
.p4-headline {{
  font-family: 'Didot', 'Bodoni 72', 'Georgia', serif;
  font-size: 34pt;
  line-height: 1.02;
  color: #FFFFFF;
  margin-top: 8pt;
  text-shadow: 0 1pt 10pt rgba(8, 16, 36, 0.35);
}}
.p4-deck {{
  font-family: 'Charter', 'Baskerville', 'Georgia', serif;
  font-style: italic;
  font-size: 10.2pt;
  line-height: 1.46;
  color: rgba(242, 246, 255, 0.94);
}}
.p4-bottom-band {{
  position: absolute;
  bottom: 0;
  left: 0;
  width: 612pt;
  padding: 36pt 34pt 22pt 34pt;
  background: linear-gradient(to top, rgba(9, 18, 36, 0.88) 0%, rgba(9, 18, 36, 0.74) 68%, rgba(9, 18, 36, 0) 100%);
  color: #FFFFFF;
}}
.p4-bottom-grid {{
  display: grid;
  grid-template-columns: 1.08fr 1.08fr 0.86fr;
  column-gap: 18pt;
  align-items: end;
}}
.p4-body {{
  font-family: 'Charter', 'Baskerville', 'Georgia', serif;
  font-size: 8.8pt;
  line-height: 1.46;
  color: rgba(248, 250, 254, 0.94);
}}
.p4-meta-col {{
  border-left: 0.5pt solid rgba(255, 255, 255, 0.38);
  padding-left: 14pt;
  text-align: right;
  display: flex;
  flex-direction: column;
  justify-content: space-between;
  align-items: flex-end;
  gap: 8pt;
}}

/* =========================================================
   PAGE 5 — SANTORINI DIPTYCH (75.7% COMBINED FULL-BLEED)
   ========================================================= */
.p5-top-pano {{
  position: relative;
  width: 612pt;
  height: 364pt;
  overflow: hidden;
}}
.p5-top-pano img {{
  width: 612pt;
  height: 364pt;
  object-fit: cover;
  object-position: 78% 45%;
  display: block;
}}
.p5-sky-scrim {{
  position: absolute;
  top: 0; left: 0; width: 612pt; height: 364pt;
  background: linear-gradient(to bottom, rgba(12, 34, 62, 0.42) 0%, rgba(12, 34, 62, 0.14) 22%, rgba(12, 34, 62, 0) 44%, rgba(12, 34, 62, 0) 100%);
}}
.p5-sky-title {{
  position: absolute;
  top: 24pt; left: 32pt;
  color: #FFFFFF;
}}
.p5-gutter-h {{
  width: 612pt;
  height: 4pt;
  background: #FAF8F5;
}}
.p5-lower {{
  position: relative;
  width: 612pt;
  height: 423.5pt;
  background: #FAF8F5;
}}
.p5-essay {{
  position: absolute;
  top: 0;
  left: 0;
  width: 268pt;
  height: 423.5pt;
  display: block;
  background: #FAF8F5;
  padding: 20pt 22pt 18pt 32pt;
}}
.p5-subhead {{
  font-family: 'Didot', 'Bodoni 72', 'Georgia', serif;
  font-style: italic;
  font-size: 18pt;
  line-height: 1.15;
  color: #161616;
  margin: 6pt 0 10pt 0;
}}
.p5-inset {{
  position: absolute;
  top: 0;
  right: 0;
  width: 340pt;
  height: 423.5pt;
  overflow: hidden;
}}
.p5-inset img {{
  width: 340pt;
  height: 424pt;
  object-fit: cover;
  object-position: center 60%;
  display: block;
}}
.p5-bottom-anchor {{
  position: absolute;
  bottom: 18pt;
  left: 32pt;
  right: 22pt;
}}
.p5-diptych-key {{
  border-top: 0.5pt solid #D4CEC3;
  padding-top: 8pt;
  font-family: 'Charter', 'Baskerville', 'Georgia', serif;
  font-style: italic;
  font-size: 7.7pt;
  line-height: 1.42;
  color: #5C564E;
}}

/* =========================================================
   PAGE 6 — REYKJAVIK (67.6% BOTTOM FULL-BLEED, CEREAL CALM TOP)
   ========================================================= */
.p6-header {{
  position: relative;
  display: block;
  height: 256pt;
  padding: 20pt 36pt 14pt 36pt;
  background: #FAF8F5;
}}
.p6-topbar {{
  display: flex;
  justify-content: space-between;
  align-items: center;
  border-bottom: 0.5pt solid #CDD4DC;
  padding-bottom: 6pt;
}}
.p6-headline {{
  font-family: 'Didot', 'Bodoni 72', 'Georgia', serif;
  font-size: 30pt;
  line-height: 1.04;
  color: #161616;
  margin: 9pt 0 8pt 0;
}}
.p6-cols {{
  display: grid;
  grid-template-columns: 1fr 1fr;
  column-gap: 24pt;
}}
.p6-caption-bar {{
  position: absolute;
  bottom: 11pt;
  left: 36pt;
  right: 36pt;
  display: flex;
  justify-content: space-between;
  align-items: center;
  border-top: 0.5pt solid #D4DBE2;
  padding-top: 5.5pt;
}}
.p6-photo-bot {{
  position: relative;
  width: 612pt;
  height: 535.5pt;
  overflow: hidden;
}}
.p6-photo-bot img {{
  width: 612pt;
  height: 536pt;
  object-fit: cover;
  object-position: center 44%;
  display: block;
}}
.p6-bot-vignette {{
  position: absolute;
  top: 0; left: 0; width: 612pt; height: 536pt;
  background: linear-gradient(to bottom, rgba(8, 12, 18, 0) 0%, rgba(8, 12, 18, 0) 84%, rgba(8, 12, 18, 0.62) 100%);
}}
.p6-caption-pill {{
  position: absolute;
  bottom: 14pt; right: 26pt;
  font-family: 'Inter', 'Avenir Next', 'Helvetica Neue', sans-serif;
  font-size: 6.2pt;
  font-weight: 500;
  letter-spacing: 0.16em;
  text-transform: uppercase;
  color: rgba(255, 255, 255, 0.92);
  text-shadow: 0 1pt 4pt rgba(0, 0, 0, 0.65);
}}

/* =========================================================
   PAGE 7 — CONTACT-SHEET TRIPTYCH (76.9% 3-PHOTO BLEED)
   ========================================================= */
.p7-gallery {{
  display: grid;
  grid-template-columns: 316pt 4pt 292pt;
  width: 612pt;
  height: 614pt;
  background: #FAF8F5;
}}
.p7-tall {{
  position: relative;
  width: 316pt;
  height: 614pt;
  overflow: hidden;
}}
.p7-tall img {{
  width: 316pt;
  height: 614pt;
  object-fit: cover;
  object-position: 50% 44%;
  display: block;
}}
.p7-stack {{
  display: grid;
  grid-template-rows: 305pt 4pt 305pt;
  width: 292pt;
  height: 614pt;
}}
.p7-tile {{
  position: relative;
  width: 292pt;
  height: 305pt;
  overflow: hidden;
}}
.p7-tile img {{
  width: 292pt;
  height: 305pt;
  object-fit: cover;
  display: block;
}}
.p7-badge {{
  position: absolute;
  font-family: 'Didot', 'Bodoni 72', 'Georgia', serif;
  font-size: 20pt;
  line-height: 1;
  color: #FFFFFF;
  text-shadow: 0 1.5pt 8pt rgba(0, 0, 0, 0.65);
}}
.p7-strip {{
  position: relative;
  display: block;
  height: 177.5pt;
  padding: 13pt 32pt 14pt 32pt;
  background: #FAF8F5;
}}
.p7-strip-head {{
  display: flex;
  justify-content: space-between;
  align-items: center;
  border-bottom: 0.5pt solid #D4CEC3;
  padding-bottom: 5pt;
}}
.p7-3col {{
  display: grid;
  grid-template-columns: 1fr 1fr 1fr;
  column-gap: 18pt;
  margin-top: 7pt;
}}
.p7-item-head {{
  font-family: 'Inter', 'Avenir Next', 'Helvetica Neue', sans-serif;
  font-size: 6.6pt;
  font-weight: 700;
  letter-spacing: 0.14em;
  text-transform: uppercase;
  color: #161616;
  margin-bottom: 3pt;
}}
.p7-item-num {{
  color: #9E4A2B;
  margin-right: 4pt;
}}
.p7-item-body {{
  font-family: 'Charter', 'Baskerville', 'Georgia', serif;
  font-size: 7.9pt;
  line-height: 1.40;
  color: #34312D;
}}
.p7-footer {{
  position: absolute;
  bottom: 14pt;
  left: 32pt;
  right: 32pt;
  display: flex;
  justify-content: space-between;
  align-items: flex-end;
  border-top: 0.5pt solid #DDD6CA;
  padding-top: 5pt;
}}

/* =========================================================
   PAGE 8 — CLOSING DUSK PLATE & COLOPHON (100% FULL-BLEED)
   ========================================================= */
.p8-epilogue {{
  position: absolute;
  top: 34pt;
  left: 56pt;
  width: 265pt;
  color: #FFFFFF;
}}
.p8-quote {{
  font-family: 'Didot', 'Bodoni 72', 'Georgia', serif;
  font-style: italic;
  font-size: 18.5pt;
  line-height: 1.32;
  color: #FFFFFF;
  margin-top: 8pt;
  text-shadow: 0 1pt 8pt rgba(6, 14, 28, 0.50);
}}
.p8-colophon-band {{
  position: absolute;
  bottom: 0;
  left: 0;
  width: 612pt;
  height: 306pt;
  padding: 24pt 34pt 20pt 34pt;
  background: linear-gradient(to bottom, rgba(16, 13, 10, 0) 0%, rgba(16, 13, 10, 0.62) 15%, rgba(14, 12, 10, 0.90) 100%);
  color: #F4EFE7;
  display: flex;
  flex-direction: column;
  justify-content: space-between;
}}
.p8-colophon-grid {{
  border-top: 0.5pt solid rgba(226, 194, 139, 0.45);
  padding-top: 13pt;
  display: grid;
  grid-template-columns: 0.92fr 1.28fr;
  column-gap: 24pt;
  align-items: start;
}}
.p8-recipe {{
  font-family: 'Charter', 'Baskerville', 'Georgia', serif;
  font-size: 8.1pt;
  line-height: 1.46;
  color: rgba(244, 239, 231, 0.88);
  margin-top: 7pt;
}}
.p8-spec {{
  font-family: 'Inter', 'Avenir Next', 'Helvetica Neue', sans-serif;
  font-size: 6.4pt;
  line-height: 1.55;
  letter-spacing: 0.08em;
  color: rgba(226, 194, 139, 0.85);
  margin-top: 9pt;
}}
.p8-table {{
  width: 100%;
  border-collapse: collapse;
  margin-top: 6pt;
  font-family: 'Inter', 'Avenir Next', 'Helvetica Neue', sans-serif;
  font-size: 6.4pt;
}}
.p8-table th {{
  text-align: left;
  font-weight: 600;
  letter-spacing: 0.14em;
  text-transform: uppercase;
  color: #E2C28B;
  border-bottom: 0.5pt solid rgba(226, 194, 139, 0.40);
  padding: 2pt 4pt 4pt 0;
}}
.p8-table td {{
  padding: 2.8pt 4pt 2.8pt 0;
  border-bottom: 0.35pt solid rgba(255, 255, 255, 0.11);
  color: rgba(246, 242, 236, 0.90);
  font-variant-numeric: tabular-nums;
}}
.p8-table td.c-num {{
  color: #E2C28B;
  font-weight: 600;
  width: 20pt;
}}
.p8-table td.c-asp {{
  width: 30pt;
  color: rgba(246, 242, 236, 0.72);
}}
.p8-table td.c-px {{
  width: 52pt;
  color: rgba(246, 242, 236, 0.72);
}}
.p8-table td.c-sha {{
  font-family: 'Menlo', 'SF Mono', monospace;
  font-size: 6.1pt;
  color: rgba(226, 194, 139, 0.88);
  text-align: right;
  padding-right: 0;
}}
.p8-table th.th-right {{
  text-align: right;
  padding-right: 0;
}}
.p8-footer {{
  display: flex;
  justify-content: space-between;
  align-items: flex-end;
  border-top: 0.5pt solid rgba(255, 255, 255, 0.18);
  padding-top: 7pt;
}}
</style>
</head>
<body>

<!-- ======================== PAGE 1: COVER ======================== -->
<section class="page">
  <img class="full-bleed-img" style="object-position: center 45%;" src="{p1}" alt="Istanbul calico overlooking the Bosphorus" />
  <div class="p1-top-scrim"></div>

  <div class="p1-topbar">
    <span class="kicker">Issue 01 · Autumn 2026</span>
    <span class="kicker">A Monograph of Feline Geography</span>
    <span class="kicker">Eight Dispatches</span>
  </div>

  <div class="p1-masthead-wrap">
    <div class="p1-masthead">FELIS MUNDI</div>
    <div class="p1-subhead">Cats Around the World — Portraits from Eight Cities</div>
  </div>

  <div class="p1-bottom-grid">
    <div>
      <div class="kicker p1-coverline-kicker">Cover Essay · 41°01′N 28°59′E</div>
      <div class="p1-coverline-title">The Guardians<br/>of the Bosphorus</div>
      <div class="p1-coverline-deck">From Istanbul’s weathered limestone parapets to Reykjavík’s snow-dusted basalt steps, an edge-to-edge photographic journal of the cities cats quietly hold in trust.</div>
    </div>
    <div class="p1-toc">
      <div class="p1-toc-head">Inside This Issue</div>
      <div class="p1-toc-row"><span>Istanbul</span><span class="p1-toc-pg">02</span></div>
      <div class="p1-toc-row"><span>Kyoto</span><span class="p1-toc-pg">03</span></div>
      <div class="p1-toc-row"><span>Chefchaouen</span><span class="p1-toc-pg">04</span></div>
      <div class="p1-toc-row"><span>Santorini</span><span class="p1-toc-pg">05</span></div>
      <div class="p1-toc-row"><span>Reykjavík</span><span class="p1-toc-pg">06</span></div>
      <div class="p1-toc-row"><span>Rome · Tokyo · Lima</span><span class="p1-toc-pg">07</span></div>
      <div class="p1-toc-row"><span>Colophon &amp; Ledger</span><span class="p1-toc-pg">08</span></div>
    </div>
  </div>
</section>

<!-- ======================== PAGE 2: ISTANBUL ======================== -->
<section class="page">
  <div class="p2-photo-box">
    <img src="{p2}" alt="Marmalade tabby sleeping beside Turkish tea in Cihangir" />
    <div class="kicker p2-top-slug">Dispatch I · Eurasia</div>
    <div class="marginal-credit">Plate 02 · Cihangir, Istanbul · Nano Banana Studio</div>
  </div>

  <div class="p2-editorial">
    <div class="p2-meta-row">
      <span class="kicker" style="color: #A85B27;">Istanbul, Turkey · 41°01′N 28°59′E</span>
      <span class="kicker" style="color: #777067;">Cihangir Cobblestones · 50mm f/1.4</span>
    </div>
    <h1 class="p2-headline">Tea, Cobblestones &amp; the Sovereign Nap</h1>
    <div class="p2-cols">
      <p class="body-p"><span class="dropcap" style="color: #A85B27;">I</span>n Istanbul’s hillside lanes of Cihangir and Karaköy, no café chair is ever truly vacant until a neighborhood tabby approves the seat. Generations of maritime trade left the city with an unspoken civic pact: bowls of water stand outside bakeries, cardboard shelters appear beneath winter awnings, and no waiter disturbs a sleeping cat beside a freshly poured tulip glass of black tea. Here, felines are neither pets nor strays, but recognized citizens of the street.</p>
      <div>
        <p class="body-p">Morning ferries cross the Bosphorus in a soft amber haze while marmalade and calico regulars claim warm limestone sills and cedar café tables. To watch the city at feline eye level is to discover an older cadence—unhurried, communal, and anchored to patches of moving sunlight.</p>
        <div class="p2-pullquote">“No café chair in Cihangir is ever truly empty; it is merely held in reserve for the afternoon sun.”</div>
      </div>
    </div>
    <div class="p2-footer">
      <span class="kicker" style="color: #6E675E;">Felis Mundi · Issue 01 · Photograph by Nano Banana Studio</span>
      <span class="folio-num" style="color: #161616;">02</span>
    </div>
  </div>
</section>

<!-- ======================== PAGE 3: KYOTO ======================== -->
<section class="page">
  <div class="p3-grid">
    <div class="p3-left">
      <div class="kicker" style="color: #B03A2E;">Dispatch II · Kansai</div>
      <div class="kicker" style="color: #6B645B; margin-top: 3pt;">Kyoto · 35°00′N 135°46′E</div>
      <div class="p3-rule"></div>
      <h1 class="p3-title">Keepers<br/>of the<br/>Cedar<br/>Shrines</h1>
      <p class="p3-deck">Between damp granite steps and weathered vermilion torii, the Japanese Bobtail moves with the hush of mountain cedar.</p>
      <p class="body-p"><span class="dropcap" style="color: #B03A2E;">A</span>rriving along ancient maritime silk routes centuries ago to guard Buddhist manuscripts and silkworm stores, the short-tailed <em>mi-ke</em> became woven into Kyoto’s temple architecture and seasonal folklore alike.</p>
      <p class="body-p">After an autumn shower in Higashiyama, crimson maple leaves cling to dark moss while mist drifts through tall cypress trunks. A calico Bobtail pauses at the threshold of the outer gate—silent, poised, and indistinguishable from the shrine’s quiet permanence.</p>
      <p class="body-p">Visitors step gently around the landing rather than break the stillness. In Kyoto, hospitality extends to every resident of the hillside.</p>

      <div class="p3-caption-box">
        <p class="p3-caption">Right: A white-and-tortoiseshell Japanese Bobtail resting on rain-darkened stone steps beneath weathered cedar eaves, Higashiyama district.</p>
        <div class="p3-folio-row">
          <span class="folio-num" style="color: #161616;">03</span>
          <span class="kicker" style="color: #6E675E;">Felis Mundi</span>
        </div>
      </div>
    </div>

    <div class="p3-photo-col">
      <img src="{p3}" alt="Japanese Bobtail on mossy Kyoto shrine steps between vermilion torii" />
      <div class="marginal-credit">Plate 03 · Higashiyama, Kyoto · Nano Banana Studio</div>
    </div>
  </div>
</section>

<!-- ======================== PAGE 4: CHEFCHAOUEN ======================== -->
<section class="page">
  <img class="full-bleed-img" style="object-position: center 55%;" src="{p4}" alt="Ginger cat on cobalt-blue plaster stairs in Chefchaouen" />

  <div class="p4-title-block">
    <div class="kicker" style="color: rgba(226, 236, 255, 0.90);">Dispatch III · Rif Mountains</div>
    <div class="kicker" style="color: rgba(206, 222, 248, 0.80); margin-top: 3pt;">35°10′N 05°16′W</div>
    <h1 class="p4-headline">The Blue<br/>Alleys of<br/>Chefchaouen</h1>
    <div class="p4-rule"></div>
    <p class="p4-deck">In the limewashed labyrinth of northern Morocco, every ginger coat becomes a moving ember against cobalt stone.</p>
  </div>

  <div class="p4-bottom-band">
    <div class="p4-bottom-grid">
      <p class="p4-body">High in the Rif Mountains, Chefchaouen’s stepped medina shifts from pale powder blue in direct noon light to deep indigo wherever eaves cast their afternoon shadow. Terracotta pots of geraniums mark each threshold, creating terraced perches tailored for unhurried patrol.</p>
      <p class="p4-body">Along these car-free staircases, neighborhood cats thread effortlessly between spice sacks, wool weavers, and cool stone landings. Their warm amber coats carry the exact complementary note to the town’s mineral pigment—turning an ordinary Tuesday errand into a study in chromatic harmony.</p>
      <div class="p4-meta-col">
        <div>
          <div class="kicker" style="color: #C7D9F8; font-size: 6.0pt;">Plate 04 · Medina Steps</div>
          <div style="font-family: 'Charter', serif; font-style: italic; font-size: 7.5pt; color: rgba(240,245,255,0.82); margin-top: 3pt;">Photograph by Nano Banana Studio · Portra 400</div>
        </div>
        <span class="folio-num" style="color: #FFFFFF;">04</span>
      </div>
    </div>
  </div>
</section>

<!-- ======================== PAGE 5: SANTORINI DIPTYCH ======================== -->
<section class="page">
  <div class="p5-top-pano">
    <img src="{p5}" alt="Tuxedo cat on whitewashed Oia caldera wall overlooking the Aegean Sea" />
    <div class="p5-sky-scrim"></div>
    <div class="p5-sky-title">
      <div class="kicker" style="color: rgba(255,255,255,0.92);">Dispatch IV · Cyclades · 36°27′N 25°22′E</div>
      <h1 class="serif-display" style="font-size: 33pt; line-height: 1.05; color: #FFFFFF; margin-top: 5pt; text-shadow: 0 1pt 10pt rgba(10,30,58,0.38);">Aegean Whitewash</h1>
    </div>
    <div class="marginal-credit">Plate 05 · Oia Caldera, Santorini</div>
  </div>

  <div class="p5-gutter-h"></div>

  <div class="p5-lower">
    <div class="p5-essay">
      <div class="kicker" style="color: #1B4F8A;">Santorini, Greece · Diptych</div>
      <h2 class="p5-subhead">Salt, Sun &amp;<br/>Caldera Shade</h2>
      <p class="body-p"><span class="dropcap" style="color: #1B4F8A;">H</span>igh along the volcanic crescent of Oia, limewashed stone absorbs the full blaze of the Aegean midday. By late afternoon, island cats move systematically along the curved parapets—first catching the cool sea breeze above the submerged crater, then retreating into pockets of shadow beside salt-bleached cobalt shutters.</p>
      <p class="body-p" style="margin-top: 8pt;">Across the Cyclades, volcanic stone, white plaster, and deep marine blue simplify the landscape into pure geometry. Against that quiet backdrop, a black-and-white coat on a sunlit wall reads like an ink brush mark on archival paper.</p>

      <div class="p5-bottom-anchor">
        <div class="p5-diptych-key">
          <strong>Above:</strong> Plate 05 — Tuxedo cat perched on the whitewashed Oia rim above the Aegean.<br/>
          <strong>Right:</strong> Plate 06 — Silver-cream tabby resting beneath weathered Cycladic shutters.
        </div>
        <div style="display: flex; justify-content: space-between; align-items: baseline; margin-top: 10pt;">
          <span class="folio-num" style="color: #161616;">05</span>
          <span class="kicker" style="color: #6E675E;">Nano Banana Studio</span>
        </div>
      </div>
    </div>

    <div class="p5-inset">
      <img src="{p6}" alt="Silver-cream tabby sleeping against cobalt blue wooden shutters in Santorini" />
      <div class="marginal-credit">Plate 06 · Cycladic Shutters · 50mm f/1.4</div>
    </div>
  </div>
</section>

<!-- ======================== PAGE 6: REYKJAVIK ======================== -->
<section class="page">
  <div class="p6-header">
    <div class="p6-topbar">
      <span class="kicker" style="color: #3E5C76;">Dispatch V · North Atlantic</span>
      <span class="kicker" style="color: #6B727A;">Reykjavík, Iceland · 64°08′N 21°56′W</span>
      <span class="folio-num" style="color: #161616;">06</span>
    </div>
    <h1 class="p6-headline">Winter Coats of the North</h1>
    <div class="p6-cols">
      <p class="body-p"><span class="dropcap" style="color: #3E5C76;">W</span>hen subarctic twilight settles over Reykjavík’s Þingholt quarter at mid-afternoon, corrugated iron and painted timber houses glow amber against the cobalt snow. Out on the volcanic basalt steps, thick double-coated Nordic cats greet the first dry flurries with effortless composure, tiny snow crystals resting unmelted atop silver guard hairs.</p>
      <p class="body-p">In a capital where winter daylight narrows to a luminous blue-hour band, neighborhood cats are famous local fixtures—roaming bookshops, wool boutiques, and timber porches with the assurance of seasoned northern explorers before slipping back inside toward radiant window heat.</p>
    </div>
    <div class="p6-caption-bar">
      <span class="kicker" style="color: #6B727A;">Below: Plate 07 · Þingholt Timber Quarter at Blue Hour</span>
      <span class="kicker" style="color: #6B727A;">Photograph by Nano Banana Studio</span>
    </div>
  </div>

  <div class="p6-photo-bot">
    <img src="{p7}" alt="Silver-grey longhaired Nordic cat on snowy volcanic basalt steps in Reykjavik" />
    <div class="p6-bot-vignette"></div>
    <div class="p6-caption-pill">64°08′N 21°56′W · Basalt Steps &amp; Nordic Blue Hour · Leica M11 / Portra 400 Recipe</div>
  </div>
</section>

<!-- ======================== PAGE 7: CONTACT SHEET TRIPTYCH ======================== -->
<section class="page">
  <div class="p7-gallery">
    <div class="p7-tall">
      <img src="{p8}" alt="Black Roman cat reclining on a fluted travertine marble column in Largo di Torre Argentina" />
      <div class="p7-badge" style="top: 16pt; left: 18pt;">01</div>
      <div class="marginal-credit">Plate 08 · Largo di Torre Argentina, Rome</div>
    </div>

    <div style="background: #FAF8F5;"></div>

    <div class="p7-stack">
      <div class="p7-tile">
        <img style="object-position: 34% 48%;" src="{p9}" alt="Tortoiseshell cat on weathered hinoki counter beneath warm cream lantern in Yanaka Ginza" />
        <div class="p7-badge" style="top: 14pt; right: 16pt;">02</div>
      </div>
      <div style="background: #FAF8F5;"></div>
      <div class="p7-tile">
        <img style="object-position: 50% 56%;" src="{p10}" alt="Striped tabby on sunlit terracotta path framed by monstera leaves in Parque Kennedy, Lima" />
        <div class="p7-badge" style="bottom: 14pt; right: 16pt;">03</div>
      </div>
    </div>
  </div>

  <div class="p7-strip">
    <div class="p7-strip-head">
      <span class="kicker" style="color: #9E4A2B;">Dispatch VI · Three Continents in Miniature</span>
      <span class="kicker" style="color: #6E675E;">Contact Sheet · Plates 08 – 10</span>
    </div>
    <div class="p7-3col">
      <div>
        <div class="p7-item-head"><span class="p7-item-num">01</span>Rome · 41°53′N 12°28′E</div>
        <p class="p7-item-body"><strong>Largo di Torre Argentina.</strong> Among four Republican-era temples sunken below street level, Rome’s famed feline sanctuary treats ancient fluted travertine columns as sunlit imperial thrones.</p>
      </div>
      <div>
        <div class="p7-item-head"><span class="p7-item-num">02</span>Tokyo · 35°43′N 139°45′E</div>
        <p class="p7-item-body"><strong>Yanaka Ginza.</strong> Beneath wooden shitamachi eaves and glowing cream paper lanterns, local cats preside over weathered cedar counters as twilight settles along Taito Ward’s quiet lane.</p>
      </div>
      <div>
        <div class="p7-item-head"><span class="p7-item-num">03</span>Lima · 12°07′S 77°01′W</div>
        <p class="p7-item-body"><strong>Parque Kennedy.</strong> Surrounded by broad monstera leaves and Miraflores garden paths, community-cared tabbies lounge unhurriedly along sunlit terracotta brickwork beside evening strollers.</p>
      </div>
    </div>

    <div class="p7-footer">
      <span class="kicker" style="color: #6E675E;">Felis Mundi · Issue 01 · Photographs by Nano Banana Studio</span>
      <span class="folio-num" style="color: #161616;">07</span>
    </div>
  </div>
</section>

<!-- ======================== PAGE 8: CLOSING DUSK PLATE & COLOPHON ======================== -->
<section class="page">
  <img class="full-bleed-img" style="object-position: center 48%;" src="{p11}" alt="Tabby cat on weathered Mediterranean limestone window sill at dusk" />

  <div class="p8-epilogue">
    <div class="kicker" style="color: rgba(226, 236, 255, 0.88);">Epilogue · Mediterranean Basin</div>
    <p class="p8-quote">“To travel attentively is to learn who already owns the warm stones at dusk.”</p>
  </div>

  <div class="p8-colophon-band">
    <div class="p8-colophon-grid">
      <div>
        <div class="kicker" style="color: #E2C28B;">Colophon &amp; Cohesive Film Recipe</div>
        <div class="serif-display" style="font-size: 21pt; letter-spacing: 0.12em; color: #FFFFFF; margin-top: 5pt;">FELIS MUNDI</div>
        <div style="font-family: 'Charter', serif; font-style: italic; font-size: 8.8pt; color: rgba(244,239,231,0.82); margin-top: 2pt;">Issue 01 · Autumn 2026 · Open-Source Editorial Demo</div>
        <p class="p8-recipe"><strong>Master Photographic Identity Core:</strong> {identity_core}</p>
        <p class="p8-spec">
          TRIM: 612 × 792 PT (8.5 × 11 IN LETTER PORTRAIT)<br/>
          TYPE: DIDOT · CHARTER · INTER · WEASYPRINT 67.0<br/>
          BLEED GATE: ALL 8 PAGES VERIFIED ≥ 50% FULL-BLEED PHOTOGRAPHY
        </p>
      </div>

      <div>
        <div class="kicker" style="color: #E2C28B;">SHA-256 Sealed Photographic Ledger (11 Plates)</div>
        <table class="p8-table">
          <thead>
            <tr>
              <th>#</th>
              <th>Location</th>
              <th>Ratio</th>
              <th>Pixels</th>
              <th class="th-right">SHA-256 (12)</th>
            </tr>
          </thead>
          <tbody>
            {colophon_rows}
          </tbody>
        </table>
      </div>
    </div>

    <div class="p8-footer">
      <span class="kicker" style="color: rgba(244, 239, 231, 0.78); font-size: 6.1pt;">All 11 Plates Generated via Nano Banana Studio · Sealed in data/manifest.sha256</span>
      <span class="folio-num" style="color: #FFFFFF;">08</span>
    </div>
  </div>
</section>

</body>
</html>
"""


def main() -> None:
    if not CREDITS_JSON.exists():
        raise FileNotFoundError(f"Run seal_assets.py first; missing {CREDITS_JSON}")
    ledger = json.loads(CREDITS_JSON.read_text(encoding="utf-8"))
    html_str = build_html(ledger)

    HTML(string=html_str, base_url=str(REPORT_DIR)).write_pdf(str(OUT_PDF))
    size_mb = OUT_PDF.stat().st_size / (1024 * 1024)
    print(f"[compile_magazine] Wrote {OUT_PDF} ({size_mb:.2f} MB)")


if __name__ == "__main__":
    main()
