#!/usr/bin/env python3
"""Compile BOTANICA VERIDICA — Architecture of Extreme Plants (10-page Report x Magazine Monograph).

Features:
- Rule 6 compilation latch (refuses to compile unless verify_integrity.py exits 0)
- 100% live GBIF v1, iNaturalist v1, and Open Tree of Life v3 metrics & taxonomy
- Hybrid Nano Banana zero-text botanical plates + pure-vector SVG 90-deg anatomy overlays
- Interactive PDF/UA-1 tagged output with nested PDF bookmarks & clickable GBIF/OpenTree links
- Optional --prepress mode adding 3mm bleed & printer crop/registration marks
"""

from __future__ import annotations

import argparse
import html
import json
import os
import subprocess
import sys
from pathlib import Path
from weasyprint import HTML

REPORT_DIR = Path(__file__).resolve().parent
ROOT = REPORT_DIR.parent
sys.path.insert(0, str(REPORT_DIR))

from svg_exhibits import (
    SPECIES_COLOR,
    svg_anatomy_overlay,
    svg_country_concentration_bar,
    svg_dichotomous_key,
    svg_gbif_world_map,
    svg_herbarium_ratio_bars,
    svg_mini_monthly_bars,
    svg_morphology_strip,
    svg_phenology_matrix,
    svg_phylogenetic_cladogram,
    svg_scale_lineup,
    svg_sequoia_hydraulic_schematic,
)

ASSETS_DIR = REPORT_DIR / "assets"
SUMMARY_JSON = ROOT / "data" / "summary_metrics.json"
MANIFEST_PATH = ROOT / "data" / "manifest.sha256"
LEDGER_JSON = ROOT / "data" / "provenance_ledger.json"


def load_font_css() -> str:
    """Optional cross-platform Inter / custom TTF font loading (never hardcodes private host paths)."""
    blocks: list[str] = []
    for env_var in ("INTER_FONT_DIR", "BOTANICA_FONT_DIR"):
        raw = os.environ.get(env_var, "").strip()
        if not raw:
            continue
        p = Path(raw)
        if not p.is_dir():
            continue
        faces = [
            ("Inter-Regular.ttf", "Inter", 400, "normal"),
            ("Inter-Italic.ttf", "Inter", 400, "italic"),
            ("Inter-SemiBold.ttf", "Inter", 600, "normal"),
            ("Inter-Bold.ttf", "Inter", 700, "normal"),
        ]
        for fname, fam, wt, st in faces:
            fp = p / fname
            if fp.exists():
                blocks.append(
                    f"@font-face {{ font-family: '{fam}'; src: url('{fp.as_uri()}'); font-weight: {wt}; font-style: {st}; }}"
                )
    return "\n".join(blocks)


def asset_uri(name: str) -> str:
    p = ASSETS_DIR / name
    if not p.exists():
        raise FileNotFoundError(f"Missing botanical plate: {p}")
    return p.as_uri()


def iucn_badge_html(sp: dict) -> str:
    code = sp["iucn_effective_code"]
    label = sp["iucn_effective_label"]
    if code == "EN":
        return '<span class="iucn-pill iucn-en">IUCN · EN (ENDANGERED)</span>'
    if code == "VU":
        return '<span class="iucn-pill iucn-vu">IUCN · VU (VULNERABLE)</span>'
    if code:
        return f'<span class="iucn-pill iucn-na">IUCN · {html.escape(code)} ({html.escape((label or "").upper())})</span>'
    return '<span class="iucn-pill iucn-na">IUCN · [N/A: NOT EVALUATED]</span>'


def gbif_link_html(sp: dict) -> str:
    k = sp["gbif_usage_key"]
    return f'<a class="ext-link" href="https://www.gbif.org/species/{k}">GBIF #{k} ↗</a>'


def build_rule9_table_rows(species: list[dict]) -> str:
    rows = []
    for sp in species:
        col = SPECIES_COLOR[sp["slug"]]
        iucn_txt = sp["iucn_effective_code"] or "[N/A]"
        flw_txt = f"{sp['inat_flowering_total']:,}" if sp["inat_flowering_total"] > 0 else "0 (cones)"
        rows.append(
            "<tr>"
            f'<td><span class="dot-sm" style="background:{col};"></span>'
            f'<a class="tbl-link" href="#species-{sp["slug"]}"><em>{html.escape(sp["canonical_name"])}</em></a> '
            f'<span class="auth-sm">{html.escape(sp["authority"])}</span></td>'
            f'<td>{html.escape(sp["family"])}</td>'
            f'<td class="num"><a class="tbl-link" href="https://www.gbif.org/species/{sp["gbif_usage_key"]}">{sp["gbif_usage_key"]}</a></td>'
            f'<td class="num"><a class="tbl-link" href="https://tree.opentreeoflife.org/opentree/argus/ottol@{sp["opentree_ott_id"]}">{sp["opentree_ott_id"]}</a></td>'
            f'<td class="num"><strong>{html.escape(iucn_txt)}</strong></td>'
            f'<td class="num">{sp["gbif_total_occurrences"]:,}</td>'
            f'<td class="num">{sp["herbarium_share_pct"]:.1f}%</td>'
            f'<td class="num">{flw_txt}</td>'
            "</tr>"
        )
    return "\n".join(rows)


def build_html(summary: dict, manifest_count: int, ledger_count: int, prepress: bool = False) -> str:
    font_css = load_font_css()
    by_slug = {sp["slug"]: sp for sp in summary["species"]}
    port = summary["portfolio"]

    ginkgo = by_slug["ginkgo"]
    welw = by_slug["welwitschia"]
    seq = by_slug["sequoia"]
    vic = by_slug["victoria"]
    dio = by_slug["dionaea"]
    adan = by_slug["adansonia"]

    # Assets
    p1 = asset_uri("plate_01_cover_ginkgo.jpg")
    p2 = asset_uri("plate_02_ginkgo_specimen.jpg")
    p3 = asset_uri("plate_03_welwitschia_namib.jpg")
    p4 = asset_uri("plate_04_sequoia_redwood.jpg")
    p5 = asset_uri("plate_05_sequoia_cones.jpg")
    p6 = asset_uri("plate_06_victoria_pad.jpg")
    p7 = asset_uri("plate_07_dionaea_trap.jpg")
    p8 = asset_uri("plate_08_adansonia_baobab.jpg")

    # Core scientific SVGs (Pages 2, 3, 10)
    svg_clado = svg_phylogenetic_cladogram(summary, 540, 224)
    svg_morph = svg_morphology_strip(540, 94)
    svg_scale = svg_scale_lineup(540, 90)
    svg_map = svg_gbif_world_map(summary, 540, 222)
    svg_herb = svg_herbarium_ratio_bars(summary, 540, 128)
    svg_pheno = svg_phenology_matrix(summary, 540, 134)
    svg_key = svg_dichotomous_key(540, 256)

    # Species-page live mini-charts (concise uppercase titles for generous gap before n=)
    svg_ginkgo_mo = svg_mini_monthly_bars(
        ginkgo["inat_monthly_all"],
        SPECIES_COLOR["ginkgo"],
        "iNat Monthly Observations (Oct Peak)",
        f"n = {ginkgo['inat_observations_total']:,}",
        252,
        78,
    )
    svg_welw_countries = svg_country_concentration_bar(welw, 192, 74)
    svg_seq_hyd = svg_sequoia_hydraulic_schematic(252, 92)
    svg_vic_flw = svg_mini_monthly_bars(
        vic["inat_monthly_flowering"],
        SPECIES_COLOR["victoria"],
        "iNat Equatorial Flowering Calendar",
        f"n = {vic['inat_flowering_total']} flw",
        252,
        78,
    )
    svg_dio_flw = svg_mini_monthly_bars(
        dio["inat_monthly_flowering"],
        SPECIES_COLOR["dionaea"],
        "iNat Flowering Peak (May–Jun)",
        f"n = {dio['inat_flowering_total']} flw",
        252,
        78,
    )
    svg_adan_flw = svg_mini_monthly_bars(
        adan["inat_monthly_flowering"],
        SPECIES_COLOR["adansonia"],
        "iNat Nocturnal Bloom (Nov Peak)",
        f"n = {adan['inat_flowering_total']} flw",
        252,
        76,
    )

    # Pure-vector 90-deg anatomy overlays layered directly onto zero-text Nano Banana plates
    svg_ginkgo_anat = svg_anatomy_overlay(
        612,
        444,
        [
            {"px": 218, "py": 138, "lx": 152, "ly": 74, "align": "left", "color": "#8A530B", "title": "BILOBED LAMINA", "sub": "Cleft fan blade ('bi-loba')"},
            {"px": 196, "py": 224, "lx": 152, "ly": 248, "align": "left", "color": "#005F5A", "title": "DICHOTOMOUS VENATION", "sub": "Forking veins, zero cross-links"},
            {"px": 344, "py": 132, "lx": 442, "ly": 78, "align": "right", "color": "#8A530B", "title": "UNDULATE APEX", "sub": "Open radiating fan margin"},
            {"px": 438, "py": 276, "lx": 456, "ly": 208, "align": "right", "color": "#7D2F24", "title": "FLESHY SARCOTESTA", "sub": "Naked ovule coat (not true fruit)"},
            {"px": 348, "py": 318, "lx": 244, "ly": 384, "align": "left", "color": "#4E5650", "title": "SLENDER PETIOLE", "sub": "Flexible aerodynamic stalk"},
        ],
        scale_label="2 CM SCALE (SCHEMATIC)",
        pill_mode=False,
    )

    svg_welw_anat = svg_anatomy_overlay(
        374,
        791.5,
        [
            {"px": 144, "py": 362, "lx": 18, "ly": 158, "align": "right", "box_w": 158, "color": "#964123", "title": "STROBILI CONES", "sub": "Dioecious reproductive cones"},
            {"px": 188, "py": 434, "lx": 198, "ly": 228, "align": "right", "box_w": 158, "color": "#005F5A", "title": "BASAL MERISTEM CROWN", "sub": "Woody stem apex grows forever"},
            {"px": 266, "py": 518, "lx": 186, "ly": 698, "align": "right", "box_w": 170, "color": "#185D3B", "title": "TWIN PERMANENT LEAVES", "sub": "Only 2 foliage leaves for centuries"},
        ],
        scale_label=None,
        pill_mode=True,
    )

    svg_vic_anat = svg_anatomy_overlay(
        612,
        444,
        [
            {"px": 420, "py": 176, "lx": 334, "ly": 66, "align": "left", "box_w": 162, "color": "#185D3B", "title": "RADIAL PRIMARY RIBS", "sub": "Air-filled buoyant girder spokes"},
            {"px": 496, "py": 214, "lx": 442, "ly": 36, "align": "right", "box_w": 154, "color": "#9C1F32", "title": "CROSS-VEIN STRUTS", "sub": "Orthogonal stiffening web"},
            {"px": 422, "py": 304, "lx": 432, "ly": 400, "align": "right", "box_w": 164, "color": "#8A530B", "title": "THERMOGENIC BLOSSOM", "sub": "Nocturnal beetle-trap flower"},
            {"px": 156, "py": 348, "lx": 14, "ly": 198, "align": "right", "box_w": 156, "color": "#9C1F32", "title": "UPTURNED BURGUNDY RIM", "sub": "Hydrostatic perimeter lip"},
            {"px": 302, "py": 366, "lx": 14, "ly": 404, "align": "right", "box_w": 154, "color": "#005F5A", "title": "DRAINAGE NOTCH", "sub": "Spills tropical rainwater"},
        ],
        scale_label=None,
        pill_mode=True,
    )

    svg_dio_anat = svg_anatomy_overlay(
        612,
        444,
        [
            {"px": 244, "py": 134, "lx": 174, "ly": 76, "align": "left", "color": "#185D3B", "title": "INTERLOCKING CILIA", "sub": "Marginal prison bristles"},
            {"px": 356, "py": 156, "lx": 442, "ly": 78, "align": "right", "color": "#9C1F32", "title": "SENSORY TRIGGER HAIRS", "sub": "3 mechanoreceptors per lobe"},
            {"px": 394, "py": 206, "lx": 452, "ly": 194, "align": "right", "color": "#7D2F24", "title": "DIGESTIVE SURFACE", "sub": "Anthocyanin-rich enzyme glands"},
            {"px": 344, "py": 234, "lx": 442, "ly": 318, "align": "right", "color": "#005F5A", "title": "MIDRIB HINGE AXIS", "sub": "Elastic snap-buckling fold"},
            {"px": 218, "py": 290, "lx": 168, "ly": 324, "align": "left", "color": "#185D3B", "title": "WINGED PETIOLE", "sub": "Photosynthetic leaf stalk"},
        ],
        scale_label="1 CM SCALE (SCHEMATIC)",
        pill_mode=False,
    )

    svg_adan_anat = svg_anatomy_overlay(
        612,
        483.5,
        [
            {"px": 228, "py": 182, "lx": 410, "ly": 72, "align": "right", "box_w": 182, "color": "#2C4966", "title": "DECIDUOUS CROWN", "sub": "Sheds foliage in dry season"},
            {"px": 232, "py": 308, "lx": 410, "ly": 152, "align": "right", "box_w": 182, "color": "#8A530B", "title": "PACHYCAUL RESERVOIR", "sub": "Fibrous parenchyma stores water"},
        ],
        scale_label=None,
        pill_mode=True,
    )

    page_rule_extra = "bleed: 3mm; marks: crop cross;" if prepress else ""
    rule9_rows = build_rule9_table_rows(summary["species"])
    newick_sha = summary["phylogeny"]["raw_newick_sha256"][:16]

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<title>BOTANICA VERIDICA — Architecture of Extreme Plants</title>
<style>
{font_css}

@page {{
  size: 612pt 792pt;
  margin: 0;
  {page_rule_extra}
}}

* {{
  box-sizing: border-box;
  margin: 0;
  padding: 0;
}}

html, body {{
  width: 612pt;
  background: #FBF9F4;
  color: #181A18;
  font-family: 'Charter', 'Baskerville', 'Georgia', serif;
  -webkit-font-smoothing: antialiased;
}}

a {{
  color: inherit;
  text-decoration: none;
}}

.page {{
  position: relative;
  width: 612pt;
  height: 791.5pt;
  overflow: hidden;
  background: #FBF9F4;
  break-after: page;
  break-inside: avoid;
}}
.page:last-child {{
  break-after: auto;
}}

/* PDF Bookmark hierarchy */
.bm-1 {{
  bookmark-level: 1;
}}
.bm-2 {{
  bookmark-level: 2;
}}

.kicker {{
  font-family: 'Inter', 'Avenir Next', 'Helvetica Neue', sans-serif;
  font-size: 6.7pt;
  font-weight: 700;
  letter-spacing: 0.16em;
  text-transform: uppercase;
}}

.serif-display {{
  font-family: 'Didot', 'Bodoni 72', 'Georgia', serif;
  font-weight: 400;
}}

.folio-num {{
  font-family: 'Didot', 'Bodoni 72', 'Georgia', serif;
  font-size: 17.5pt;
  font-weight: 400;
  line-height: 1;
  color: #181A18;
}}

.body-p {{
  font-family: 'Charter', 'Baskerville', 'Georgia', serif;
  font-size: 8.85pt;
  line-height: 1.48;
  color: #242825;
  text-align: left;
  hyphens: none;
}}

.dropcap {{
  float: left;
  font-family: 'Didot', 'Bodoni 72', 'Georgia', serif;
  font-size: 33pt;
  line-height: 0.80;
  padding-top: 2.5pt;
  padding-right: 5.5pt;
  padding-bottom: 1pt;
}}

.iucn-pill {{
  display: inline-block;
  font-family: 'Inter', 'Avenir Next', 'Helvetica Neue', sans-serif;
  font-size: 6.1pt;
  font-weight: 700;
  letter-spacing: 0.11em;
  padding: 2.5pt 6pt;
  border-radius: 2pt;
  color: #FFFFFF;
  vertical-align: middle;
}}
.iucn-en {{ background: #8F1D24; }}
.iucn-vu {{ background: #8A4B08; }}
.iucn-na {{ background: #4A524E; }}

.ext-link {{
  font-family: 'Inter', 'Avenir Next', 'Helvetica Neue', sans-serif;
  font-size: 6.4pt;
  font-weight: 700;
  letter-spacing: 0.08em;
  color: #005F5A;
  border-bottom: 0.5pt solid #005F5A;
}}

.field-check {{
  background: #F1ECE1;
  border-left: 2pt solid #005F5A;
  padding: 7pt 9pt;
  margin-top: 7pt;
}}
.field-check-head {{
  font-family: 'Inter', 'Avenir Next', 'Helvetica Neue', sans-serif;
  font-size: 6.2pt;
  font-weight: 700;
  letter-spacing: 0.15em;
  text-transform: uppercase;
  color: #005F5A;
  margin-bottom: 2.5pt;
}}
.field-check-body {{
  font-family: 'Charter', 'Baskerville', 'Georgia', serif;
  font-size: 7.9pt;
  line-height: 1.40;
  color: #1F2320;
}}

.std-page-pad {{
  padding: 26pt 36pt 20pt 36pt;
  height: 791.5pt;
  position: relative;
}}
.running-top {{
  display: flex;
  justify-content: space-between;
  align-items: center;
  border-bottom: 0.6pt solid #CFC8B8;
  padding-bottom: 5.5pt;
  margin-bottom: 11pt;
}}
.running-bot {{
  position: absolute;
  bottom: 16pt;
  left: 36pt;
  right: 36pt;
  display: flex;
  justify-content: space-between;
  align-items: flex-end;
  border-top: 0.6pt solid #D5CEBE;
  padding-top: 5.5pt;
}}

.exhibit-label {{
  font-family: 'Inter', 'Avenir Next', 'Helvetica Neue', sans-serif;
  font-size: 6.6pt;
  font-weight: 700;
  letter-spacing: 0.14em;
  text-transform: uppercase;
  color: #005F5A;
  margin-bottom: 3pt;
}}
.exhibit-sub {{
  font-family: 'Charter', 'Baskerville', 'Georgia', serif;
  font-style: italic;
  font-size: 7.7pt;
  color: #464E49;
  margin-bottom: 6pt;
}}

/* =========================================================
   PAGE 1 — FULL-BLEED BOTANICAL COVER
   ========================================================= */
.full-bleed-img {{
  position: absolute;
  top: 0; left: 0;
  width: 612pt; height: 792pt;
  object-fit: cover;
  display: block;
}}
.p1-scrim {{
  position: absolute;
  top: 0; left: 0; width: 612pt; height: 792pt;
  background: linear-gradient(
    to bottom,
    rgba(11, 18, 17, 0.72) 0%,
    rgba(11, 18, 17, 0.34) 24%,
    rgba(11, 18, 17, 0.04) 45%,
    rgba(11, 18, 17, 0.10) 64%,
    rgba(10, 15, 14, 0.86) 86%,
    rgba(9, 13, 12, 0.94) 100%
  );
}}
.p1-topbar {{
  position: absolute;
  top: 22pt; left: 34pt; right: 34pt;
  display: flex;
  justify-content: space-between;
  color: #ECECE6;
  border-bottom: 0.5pt solid rgba(236, 236, 230, 0.40);
  padding-bottom: 6.5pt;
}}
.p1-masthead-wrap {{
  position: absolute;
  top: 44pt; left: 26pt; right: 26pt;
  text-align: center;
}}
.p1-masthead {{
  font-family: 'Didot', 'Bodoni 72', 'Georgia', serif;
  font-size: 46pt;
  font-weight: 400;
  letter-spacing: 0.13em;
  line-height: 1.04;
  color: #FFFFFF;
  margin-left: 0.13em;
}}
.p1-subhead {{
  margin-top: 9pt;
  font-family: 'Charter', 'Baskerville', 'Georgia', serif;
  font-style: italic;
  font-size: 12pt;
  color: #E7E5DC;
}}
.p1-bottom-grid {{
  position: absolute;
  bottom: 26pt; left: 34pt; right: 34pt;
  display: grid;
  grid-template-columns: 1.38fr 0.92fr;
  column-gap: 26pt;
  align-items: end;
}}
.p1-toc {{
  border-left: 0.6pt solid rgba(226, 200, 138, 0.55);
  padding-left: 14pt;
}}
.p1-toc-row {{
  display: flex;
  justify-content: space-between;
  align-items: baseline;
  font-family: 'Inter', 'Avenir Next', 'Helvetica Neue', sans-serif;
  font-size: 6.8pt;
  letter-spacing: 0.12em;
  text-transform: uppercase;
  line-height: 1.72;
  color: #F4F2EA;
}}
.p1-toc-pg {{
  font-family: 'Didot', 'Bodoni 72', 'Georgia', serif;
  font-size: 8.6pt;
  color: #E8C77B;
}}
.p1-telemetry-pill {{
  margin-top: 10pt;
  padding: 6pt 9pt;
  background: rgba(15, 28, 25, 0.88);
  border-left: 2pt solid #E8C77B;
  font-family: 'Inter', 'Avenir Next', 'Helvetica Neue', sans-serif;
  font-size: 6.3pt;
  font-weight: 600;
  letter-spacing: 0.09em;
  color: #F4F2EA;
}}

/* =========================================================
   SPECIES PLATE CONTAINERS (PAGES 4, 5, 6, 7, 8, 9)
   ========================================================= */
.top-plate-box {{
  position: relative;
  width: 612pt;
  height: 444pt;
  overflow: hidden;
  background: #F7F3E8;
  border-bottom: 0.6pt solid #D4CCB9;
}}
.top-plate-box img.plate-hero {{
  width: 612pt;
  height: 444pt;
  object-fit: cover;
  display: block;
}}
.plate-tag-pill {{
  position: absolute;
  top: 14pt;
  left: 16pt;
  background: rgba(251, 249, 244, 0.94);
  border: 0.5pt solid #C8C0AE;
  padding: 3pt 7pt;
  font-family: 'Inter', 'Avenir Next', 'Helvetica Neue', sans-serif;
  font-size: 6.1pt;
  font-weight: 700;
  letter-spacing: 0.14em;
  text-transform: uppercase;
  color: #181A18;
}}

.sp-bed {{
  position: relative;
  display: block;
  height: 347.5pt;
  padding: 15pt 34pt 14pt 34pt;
  background: #FBF9F4;
}}
.sp-header-row {{
  display: flex;
  justify-content: space-between;
  align-items: center;
  border-bottom: 0.5pt solid #D5CEBE;
  padding-bottom: 5pt;
  margin-bottom: 7pt;
}}
.sp-title-line {{
  display: flex;
  justify-content: space-between;
  align-items: baseline;
  margin-bottom: 8pt;
}}
.sp-binomial {{
  font-family: 'Didot', 'Bodoni 72', 'Georgia', serif;
  font-size: 23pt;
  line-height: 1.05;
  color: #181A18;
}}
.sp-binomial em {{
  font-style: italic;
}}
.sp-authority {{
  font-family: 'Charter', 'Baskerville', 'Georgia', serif;
  font-size: 11.5pt;
  color: #464E49;
  font-style: normal;
  margin-left: 5pt;
}}
.sp-common {{
  font-family: 'Inter', 'Avenir Next', 'Helvetica Neue', sans-serif;
  font-size: 7.4pt;
  font-weight: 700;
  letter-spacing: 0.14em;
  text-transform: uppercase;
  color: #464E49;
}}
.sp-2col {{
  display: grid;
  grid-template-columns: 1.04fr 0.96fr;
  column-gap: 22pt;
  align-items: start;
}}

/* Page 5 Welwitschia — Asymmetric 39/61 Block Split (no CSS grid around float drop cap!) */
.p5-left {{
  position: absolute;
  top: 0; left: 0;
  width: 238pt;
  height: 791.5pt;
  display: block;
  background: #FBF9F4;
  padding: 24pt 18pt 18pt 26pt;
  border-right: 0.6pt solid #D4CCB9;
}}
.p5-right {{
  position: absolute;
  top: 0; right: 0;
  width: 374pt;
  height: 791.5pt;
  overflow: hidden;
}}
.p5-right img {{
  width: 374pt;
  height: 792pt;
  object-fit: cover;
  object-position: 50% 52%;
  display: block;
}}

/* Page 6 Sequoia — Circular Magnifying-Lens Zoom Medallion */
.zoom-medallion {{
  position: absolute;
  bottom: 18pt;
  right: 22pt;
  width: 134pt;
  height: 134pt;
  border-radius: 67pt;
  overflow: hidden;
  border: 2.5pt solid #FBF9F4;
  box-shadow: 0 4pt 14pt rgba(10, 16, 12, 0.45);
}}
.zoom-medallion img {{
  width: 134pt;
  height: 134pt;
  object-fit: cover;
  display: block;
}}
.zoom-caption {{
  position: absolute;
  bottom: 18pt;
  right: 164pt;
  background: rgba(251, 249, 244, 0.95);
  border-left: 2pt solid #7D2F24;
  padding: 5pt 8pt;
  width: 126pt;
}}

/* Page 8 Dionaea — 3-Step NatGeo Action-Potential Badges */
.step-row {{
  display: flex;
  align-items: flex-start;
  gap: 6pt;
  margin-top: 5pt;
}}
.step-badge {{
  flex-shrink: 0;
  width: 13pt;
  height: 13pt;
  border-radius: 6.5pt;
  background: #9C1F32;
  color: #FFFFFF;
  font-family: 'Inter', 'Avenir Next', 'Helvetica Neue', sans-serif;
  font-size: 6.6pt;
  font-weight: 700;
  text-align: center;
  line-height: 13pt;
  margin-top: 1pt;
}}
.step-text {{
  font-family: 'Charter', 'Baskerville', 'Georgia', serif;
  font-size: 8.1pt;
  line-height: 1.38;
  color: #212522;
}}

/* Page 9 Adansonia — Calm Archival Top + 61% Bottom Full-Bleed */
.p9-top {{
  position: relative;
  display: block;
  height: 308pt;
  padding: 20pt 34pt 14pt 34pt;
  background: #FBF9F4;
  border-bottom: 0.6pt solid #D4CCB9;
}}
.p9-bot {{
  position: relative;
  width: 612pt;
  height: 483.5pt;
  overflow: hidden;
}}
.p9-bot img {{
  width: 612pt;
  height: 484pt;
  object-fit: cover;
  object-position: center 48%;
  display: block;
}}
.p9-bot-scrim {{
  position: absolute;
  top: 0; left: 0; width: 612pt; height: 484pt;
  background: linear-gradient(to bottom, rgba(16, 14, 12, 0) 0%, rgba(16, 14, 12, 0) 80%, rgba(12, 11, 9, 0.78) 100%);
}}

/* Page 10 Rule 9 Verification Tufte Table */
.r9-table {{
  width: 100%;
  border-collapse: collapse;
  margin-top: 6pt;
  font-family: 'Inter', 'Avenir Next', 'Helvetica Neue', sans-serif;
  font-size: 6.6pt;
}}
.r9-table th {{
  text-align: left;
  font-weight: 700;
  letter-spacing: 0.10em;
  text-transform: uppercase;
  color: #005F5A;
  border-top: 1.1pt solid #181A18;
  border-bottom: 0.75pt solid #181A18;
  padding: 4pt 3pt;
}}
.r9-table th.num, .r9-table td.num {{
  text-align: right;
  font-variant-numeric: tabular-nums;
}}
.r9-table td {{
  padding: 4.5pt 3pt;
  border-bottom: 0.35pt solid #D8D1C2;
  color: #181A18;
}}
.r9-table tr:last-child td {{
  border-bottom: 1.0pt solid #181A18;
}}
.dot-sm {{
  display: inline-block;
  width: 5.5pt;
  height: 5.5pt;
  border-radius: 3pt;
  margin-right: 4pt;
  vertical-align: middle;
}}
.tbl-link {{
  color: #005F5A;
  font-weight: 600;
}}
.auth-sm {{
  color: #464E49;
  font-size: 6.1pt;
}}
.receipt-grid {{
  display: grid;
  grid-template-columns: 1fr 1fr;
  column-gap: 18pt;
  margin-top: 10pt;
  background: #F1ECE1;
  padding: 10pt 12pt;
  border-top: 1.2pt solid #005F5A;
}}
</style>
</head>
<body>
<main>

<!-- ======================== PAGE 1: FULL-BLEED COVER ======================== -->
<article class="page" id="cover">
  <img class="full-bleed-img" style="object-position: center 48%;" src="{p1}" alt="Luminous golden Ginkgo biloba bilobed leaves and amber ovule seed on mossy basalt" />
  <div class="p1-scrim"></div>

  <div class="p1-topbar">
    <span class="kicker">Monograph 01 · Autumn 2026</span>
    <span class="kicker">Scientific Field Journal × Live Telemetry</span>
    <span class="kicker">Six Vascular Clades</span>
  </div>

  <div class="p1-masthead-wrap">
    <h1 class="p1-masthead bm-1">BOTANICA VERIDICA</h1>
    <div class="p1-subhead">Architecture of Extreme Plants — Live Taxonomy, Phylogeny &amp; Field Morphology</div>
  </div>

  <div class="p1-bottom-grid">
    <div>
      <div class="kicker" style="color:#E8C77B; margin-bottom:5pt;">Botanical Monograph × Learning Magazine</div>
      <div class="serif-display" style="font-size:25pt; line-height:1.05; color:#FFFFFF; margin-bottom:7pt;">Six Blueprints<br/>of Plant Survival</div>
      <p style="font-family:'Charter',serif; font-size:9.1pt; line-height:1.45; color:#F2EFE7; max-width:280pt;">
        From ancient gymnosperm fan-leaves to rapid carnivorous snap-buckling shells—every Latin authority, phylogenetic branch, occurrence dot, and bloom curve verified live from open biodiversity registries.
      </p>
      <div class="p1-telemetry-pill">
        LIVE AUDITED: {port['total_gbif_occurrences']:,} GBIF OCCURRENCES · {port['total_herbarium_specimens']:,} HERBARIA · {port['total_inat_observations']:,} iNAT RECORDS
      </div>
    </div>

    <nav class="p1-toc" aria-label="Contents">
      <div class="kicker" style="color:#E8C77B; font-size:6.2pt; margin-bottom:6pt;">Interactive Contents</div>
      <a class="p1-toc-row" href="#spread-phylogeny"><span>Phylogeny &amp; Morphology</span><span class="p1-toc-pg">02</span></a>
      <a class="p1-toc-row" href="#telemetry-map"><span>Global Map &amp; Phenology</span><span class="p1-toc-pg">03</span></a>
      <a class="p1-toc-row" href="#species-ginkgo"><span>Ginkgo biloba</span><span class="p1-toc-pg">04</span></a>
      <a class="p1-toc-row" href="#species-welwitschia"><span>Welwitschia mirabilis</span><span class="p1-toc-pg">05</span></a>
      <a class="p1-toc-row" href="#species-sequoia"><span>Sequoia sempervirens</span><span class="p1-toc-pg">06</span></a>
      <a class="p1-toc-row" href="#species-victoria"><span>Victoria amazonica</span><span class="p1-toc-pg">07</span></a>
      <a class="p1-toc-row" href="#species-dionaea"><span>Dionaea muscipula</span><span class="p1-toc-pg">08</span></a>
      <a class="p1-toc-row" href="#species-adansonia"><span>Adansonia digitata</span><span class="p1-toc-pg">09</span></a>
      <a class="p1-toc-row" href="#field-key"><span>Field Key &amp; Provenance</span><span class="p1-toc-pg">10</span></a>
    </nav>
  </div>
</article>

<!-- ======================== PAGE 2: PHYLOGENY & MORPHOLOGY (SPREAD LEFT) ======================== -->
<article class="page" id="spread-phylogeny">
  <div class="std-page-pad">
    <div class="running-top">
      <span class="kicker" style="color:#005F5A;">Section I · Evolutionary Architecture</span>
      <span class="kicker" style="color:#464E49;">Open Tree of Life v3 · Induced Newick Subtree</span>
    </div>

    <h1 class="serif-display bm-1" style="font-size:26pt; line-height:1.06; color:#181A18; margin-bottom:6pt;">Deep Branches of Seed-Plant Architecture</h1>
    <p class="body-p" style="margin-bottom:11pt;">
      Our six extreme plants span the deepest split in <em>Spermatophyta</em> (seed plants): three ancient <strong>gymnosperms</strong> bearing naked ovules or cones (<em>Ginkgo</em>, <em>Welwitschia</em>, <em>Sequoia</em>—yielding exactly <strong>0</strong> flowering records on iNaturalist) and three <strong>angiosperms</strong> spanning basal water lilies to specialized eudicots (<strong>{port['total_flowering_records']:,}</strong> verified bloom records).
    </p>

    <div class="exhibit-label">Exhibit 1 · Live Open Tree of Life Phylogenetic Cladogram (Collapsed Induced Subtree)</div>
    <div class="exhibit-sub">Parsed deterministically from raw Newick topology (SHA-256 {newick_sha}…); internal nodes reflect live OpenTree consensus.</div>
    <div style="margin-bottom:12pt;">{svg_clado}</div>

    <div class="exhibit-label">Exhibit 2 · Comparative Morphology Diagnostic Silhouettes (Field Pattern Recognition)</div>
    <div class="exhibit-sub">Pairing real specimens with simplified 2D structural silhouettes trains rapid taxonomic diagnosis across clades.</div>
    <div style="margin-bottom:12pt;">{svg_morph}</div>

    <div class="exhibit-label">Exhibit 3 · Structural Scale Span Across Featured Organs &amp; Organisms</div>
    <div style="margin-top:4pt;">{svg_scale}</div>

    <div class="running-bot">
      <span class="folio-num">02</span>
      <span class="kicker" style="color:#4E5650;">Botanica Veridica · Evolutionary Atlas</span>
    </div>
  </div>
</article>

<!-- ======================== PAGE 3: GBIF MAP, HERBARIA & PHENOLOGY (SPREAD RIGHT) ======================== -->
<article class="page" id="telemetry-map">
  <div class="std-page-pad">
    <div class="running-top">
      <span class="kicker" style="color:#005F5A;">Section II · Global Biodiversity Telemetry</span>
      <span class="kicker" style="color:#464E49;">GBIF v1 ({port['total_gbif_occurrences']:,} Records) &amp; iNaturalist v1</span>
    </div>

    <h1 class="serif-display bm-1" style="font-size:24pt; line-height:1.06; color:#181A18; margin-bottom:6pt;">Global Ranges, Herbaria &amp; Bloom Calendars</h1>
    <p class="body-p" style="margin-bottom:10pt;">
      Urban cultivation and citizen science skew raw counts toward temperate parks (<em>Ginkgo biloba</em> alone accounts for <strong>{ginkgo['gbif_total_occurrences']:,}</strong> GBIF entries), whereas rare desert and tropical taxa rely heavily on physical museum herbarium sheets—reaching <strong>{vic['herbarium_share_pct']:.1f}%</strong> in <em>Victoria amazonica</em> and <strong>{welw['herbarium_share_pct']:.1f}%</strong> in <em>Welwitschia mirabilis</em>.
    </p>

    <div class="exhibit-label">Exhibit 4 · Live GBIF Georeferenced Distribution ({port['total_sampled_map_points']} Audited Coordinate Points)</div>
    <div class="exhibit-sub">Each marker plots a real latitude/longitude pair fetched from api.gbif.org/v1/occurrence/search (120 georeferenced records per taxon).</div>
    <div style="margin-bottom:10pt;">{svg_map}</div>

    <div class="exhibit-label">Exhibit 5 · Museum Herbarium Share vs. Citizen-Science Observations</div>
    <div style="margin-bottom:10pt;">{svg_herb}</div>

    <div class="exhibit-label">Exhibit 6 · Live iNaturalist 12-Month Flowering Phenology Matrix (term_id=12 · Flowering)</div>
    <div>{svg_pheno}</div>

    <div class="running-bot">
      <span class="kicker" style="color:#4E5650;">Source: GBIF Backbone &amp; Occurrences + iNaturalist Phenology API</span>
      <span class="folio-num">03</span>
    </div>
  </div>
</article>

<!-- ======================== PAGE 4: GINKGO BILOBA (SPREAD 4-5 LEFT) ======================== -->
<article class="page" id="species-ginkgo">
  <div class="top-plate-box">
    <img class="plate-hero" style="object-position: center 50%;" src="{p2}" alt="Archival museum specimen plate of a bilobed Ginkgo biloba fan leaf and fleshy amber sarcotesta seed" />
    {svg_ginkgo_anat}
    <div class="plate-tag-pill">Plate 02 · Studio Specimen · Anatomy Overlay</div>
  </div>

  <div class="sp-bed">
    <div class="sp-header-row">
      <span class="kicker" style="color:{SPECIES_COLOR['ginkgo']};">Clade I · {html.escape(ginkgo['tax_class'])} · {html.escape(ginkgo['family'])}</span>
      <div>{iucn_badge_html(ginkgo)} &nbsp; {gbif_link_html(ginkgo)}</div>
    </div>

    <div class="sp-title-line">
      <h2 class="sp-binomial bm-2"><em>{html.escape(ginkgo['canonical_name'])}</em><span class="sp-authority">{html.escape(ginkgo['authority'])}</span></h2>
      <span class="sp-common">{html.escape(ginkgo['common_name'])}</span>
    </div>

    <div class="sp-2col">
      <div>
        <p class="body-p"><span class="dropcap" style="color:{SPECIES_COLOR['ginkgo']};">S</span>ole surviving member of the ancient order <em>Ginkgoales</em>, <em>Ginkgo biloba</em> preserves a leaf architecture absent in every modern broad-leaved flowering tree: veins fork repeatedly in pairs (<strong>dichotomous venation</strong>) without forming a reticulate mesh. Though urban street planting drives <strong>{ginkgo['gbif_total_occurrences']:,}</strong> global GBIF records—peaking sharply in October at <strong>{max(ginkgo['inat_monthly_all']):,}</strong> iNaturalist sightings when foliage turns luminous gold—wild populations remain IUCN <strong>Endangered</strong>.</p>
        <p class="body-p" style="margin-top:6pt;"><strong>Etymology:</strong> <em>Ginkgo</em> derives from a 17th-century transcription of Japanese <em>ginkyō</em> (“silver apricot”); Latin <em>biloba</em> marks the leaf’s central cleft. Its amber “fruit” is actually a naked gymnosperm seed wrapped in a butyric-acid fleshy coat (<em>sarcotesta</em>).</p>
      </div>

      <div>
        {svg_ginkgo_mo}
        <div class="field-check" style="border-left-color:{SPECIES_COLOR['ginkgo']};">
          <div class="field-check-head" style="color:{SPECIES_COLOR['ginkgo']};">Field Check · How to Diagnose in 5 Seconds</div>
          <div class="field-check-body">Hold a leaf against sunlight: true angiosperms form net-like vein loops, whereas <em>Ginkgo</em> veins radiate straight from petiole to rim in clean Y-forks—with zero cross-veins.</div>
        </div>
      </div>
    </div>

    <div class="running-bot" style="left:34pt; right:34pt;">
      <span class="folio-num">04</span>
      <span class="kicker" style="color:#4E5650;">Plate: Nano Banana Studio · GBIF {ginkgo['gbif_total_occurrences']:,} Occ · {ginkgo['herbarium_share_pct']:.1f}% Herbaria</span>
    </div>
  </div>
</article>

<!-- ======================== PAGE 5: WELWITSCHIA MIRABILIS (SPREAD 4-5 RIGHT) ======================== -->
<article class="page" id="species-welwitschia">
  <div class="p5-left">
    <div class="kicker" style="color:{SPECIES_COLOR['welwitschia']};">Clade II · {html.escape(welw['tax_class'])}</div>
    <div class="kicker" style="color:#4E5650; margin-top:2pt;">{html.escape(welw['family'])} · Namib Desert</div>
    <div style="margin:7pt 0 9pt 0;">{iucn_badge_html(welw)}</div>

    <h2 class="serif-display bm-2" style="font-size:25pt; line-height:1.04; color:#181A18; margin-bottom:4pt;"><em>Welwitschia<br/>mirabilis</em></h2>
    <div style="font-family:'Charter',serif; font-size:9.5pt; color:#464E49; margin-bottom:10pt;">{html.escape(welw['authority'])} · {gbif_link_html(welw)}</div>

    <p class="body-p"><span class="dropcap" style="color:{SPECIES_COLOR['welwitschia']};">A</span>cross the hyper-arid Namib gravel plains of Namibia and southern Angola, <em>Welwitschia</em> abandons conventional apical growth entirely. After producing its seed leaves, the shoot tip dies—leaving a woody ring of <strong>basal meristem</strong> that extrudes just <strong>two permanent strap leaves</strong> continuously for centuries.</p>
    <p class="body-p" style="margin-top:7pt;">Desert winds shred those twin blades into tangled ribbons while Atlantic radiation fog condenses across stomatal surfaces. Across GBIF’s <strong>{welw['gbif_total_occurrences']:,}</strong> global records, Namibia (<strong>{welw['top_countries'][0]['count']:,}</strong>) and Angola (<strong>{welw['top_countries'][1]['count']:,}</strong>) hold nearly four-fifths of all verified occurrences, and <strong>{welw['herbarium_share_pct']:.1f}%</strong> are preserved museum sheets.</p>

    <div style="margin-top:11pt;">{svg_welw_countries}</div>

    <div class="field-check" style="border-left-color:{SPECIES_COLOR['welwitschia']}; margin-top:9pt;">
      <div class="field-check-head" style="color:{SPECIES_COLOR['welwitschia']};">Field Check · Rule 5 Honesty Note</div>
      <div class="field-check-body">IUCN status returns <code>NOT_EVALUATED</code> in GBIF &amp; iNaturalist—reported transparently as <strong>[N/A]</strong> rather than guessed. Look for salmon-tan strobili cones crowning separate male and female plants.</div>
    </div>

    <div style="position:absolute; bottom:16pt; left:26pt; right:18pt; display:flex; justify-content:space-between; align-items:baseline; border-top:0.5pt solid #D5CEBE; padding-top:5pt;">
      <span class="kicker" style="color:#4E5650;">OTT {welw['opentree_ott_id']}</span>
      <span class="folio-num">05</span>
    </div>
  </div>

  <div class="p5-right">
    <img src="{p3}" alt="Wild Welwitschia mirabilis in Namib Desert gravel with woody crown, salmon strobili cones, and twin ribbon leaves" />
    {svg_welw_anat}
    <div class="plate-tag-pill">Plate 03 · Namib Desert · Field Plate</div>
  </div>
</article>

<!-- ======================== PAGE 6: SEQUOIA SEMPERVIRENS (SPREAD 6-7 LEFT) ======================== -->
<article class="page" id="species-sequoia">
  <div class="top-plate-box">
    <img class="plate-hero" style="object-position: center 50%;" src="{p4}" alt="Towering ancient Sequoia sempervirens coastal redwood trunks rising into silver Pacific fog above sword ferns" />
    <div class="plate-tag-pill">Plate 04 · Coastal Fog Belt · Habitat Plate</div>
    <div class="zoom-caption">
      <div class="kicker" style="color:#7D2F24; font-size:5.9pt;">Plate 05 · Macro Detail</div>
      <div style="font-family:'Charter',serif; font-size:7.4pt; line-height:1.35; color:#181A18; margin-top:2pt;">Two-ranked flat needles &amp; ~2 cm woody seed cones (<em>Cupressaceae</em>).</div>
    </div>
    <div class="zoom-medallion">
      <img src="{p5}" alt="Magnified macro view of Sequoia sempervirens flat green needles and two woody oval seed cones" />
    </div>
  </div>

  <div class="sp-bed">
    <div class="sp-header-row">
      <span class="kicker" style="color:{SPECIES_COLOR['sequoia']};">Clade III · {html.escape(seq['tax_class'])} · {html.escape(seq['family'])}</span>
      <div>{iucn_badge_html(seq)} &nbsp; {gbif_link_html(seq)}</div>
    </div>

    <div class="sp-title-line">
      <h2 class="sp-binomial bm-2"><em>{html.escape(seq['canonical_name'])}</em><span class="sp-authority">{html.escape(seq['authority'])}</span></h2>
      <span class="sp-common">{html.escape(seq['common_name'])}</span>
    </div>

    <div class="sp-2col">
      <div>
        <p class="body-p"><span class="dropcap" style="color:{SPECIES_COLOR['sequoia']};">E</span>arth’s tallest living organisms solve a brutal fluid-mechanics puzzle: pulling continuous water columns over 100 meters skyward against gravity without fatal xylem cavitation. Along northern California’s narrow marine layer, <em>Sequoia sempervirens</em> cheats the vertical limit by drinking summer advection fog straight through upper canopy needles.</p>
        <p class="body-p" style="margin-top:6pt;">Live biodiversity registries log <strong>{seq['gbif_total_occurrences']:,}</strong> GBIF occurrences (<strong>{seq['top_countries'][0]['count']:,}</strong> in the US, plus historic botanical plantings in France and Britain) and <strong>{seq['inat_observations_total']:,}</strong> year-round iNaturalist records, yet old-growth contraction keeps the species IUCN <strong>Endangered</strong>.</p>
      </div>

      <div>
        {svg_seq_hyd}
        <div class="field-check" style="border-left-color:{SPECIES_COLOR['sequoia']};">
          <div class="field-check-head" style="color:{SPECIES_COLOR['sequoia']};">Field Check · Coast Redwood vs. Giant Sequoia</div>
          <div class="field-check-body">Check the foliage medallion above: <em>Sequoia sempervirens</em> bears flat, two-ranked yew-like needles and olive-sized (~2 cm) cones, whereas Sierra <em>Sequoiadendron</em> has awl-like scaly foliage and egg-sized cones.</div>
        </div>
      </div>
    </div>

    <div class="running-bot" style="left:34pt; right:34pt;">
      <span class="folio-num">06</span>
      <span class="kicker" style="color:#4E5650;">Plates 04–05: Nano Banana Studio · {seq['gbif_preserved_specimens']:,} Herbarium Sheets ({seq['herbarium_share_pct']:.1f}%)</span>
    </div>
  </div>
</article>

<!-- ======================== PAGE 7: VICTORIA AMAZONICA (SPREAD 6-7 RIGHT) ======================== -->
<article class="page" id="species-victoria">
  <div class="top-plate-box">
    <img class="plate-hero" style="object-position: center 54%;" src="{p6}" alt="Giant floating Victoria amazonica lily pads showing upturned burgundy rim, drainage notch, radial underside structural ribs, and white nocturnal blossom" />
    {svg_vic_anat}
    <div class="plate-tag-pill">Plate 06 · Amazon Blackwater · Structural Anatomy</div>
  </div>

  <div class="sp-bed">
    <div class="sp-header-row">
      <span class="kicker" style="color:{SPECIES_COLOR['victoria']};">Clade IV · Basal Angiosperm · {html.escape(vic['family'])}</span>
      <div>{iucn_badge_html(vic)} &nbsp; {gbif_link_html(vic)}</div>
    </div>

    <div class="sp-title-line">
      <h2 class="sp-binomial bm-2"><em>{html.escape(vic['canonical_name'])}</em><span class="sp-authority">{html.escape(vic['authority'])}</span></h2>
      <span class="sp-common">{html.escape(vic['common_name'])}</span>
    </div>

    <div class="sp-2col">
      <div>
        <p class="body-p"><span class="dropcap" style="color:{SPECIES_COLOR['victoria']};">F</span>loating across calm Amazonian oxbow lakes, <em>Victoria amazonica</em> constructs a living thin-shell truss over two meters wide. Hollow radial primary girders bridged by orthogonal cross-veins distribute buoyancy so efficiently that Joseph Paxton modeled London’s 1851 Crystal Palace roof ribs directly on this underside grid.</p>
        <p class="body-p" style="margin-top:6pt;">Across all six featured plants, <em>Victoria</em> exhibits our highest museum reliance: <strong>{vic['herbarium_share_pct']:.1f}%</strong> (<strong>{vic['gbif_preserved_specimens']:,}</strong> of <strong>{vic['gbif_total_occurrences']:,}</strong> GBIF records) are preserved herbarium specimens collected across Brazil ({vic['top_countries'][0]['count']}), Peru ({vic['top_countries'][1]['count']}), Colombia ({vic['top_countries'][2]['count']}), and Guyana ({vic['top_countries'][3]['count']}).</p>
      </div>

      <div>
        {svg_vic_flw}
        <div class="field-check" style="border-left-color:{SPECIES_COLOR['victoria']};">
          <div class="field-check-head" style="color:{SPECIES_COLOR['victoria']};">Field Check · Two-Night Beetle Pollination</div>
          <div class="field-check-body">Each flower opens white and thermogenic on Night 1 (warming above ambient air to volatilize scent and trap scarab beetles), then reopens deep pink on Night 2 to release pollen-dusted beetles.</div>
        </div>
      </div>
    </div>

    <div class="running-bot" style="left:34pt; right:34pt;">
      <span class="kicker" style="color:#4E5650;">Plate: Nano Banana Studio · Equatorial Flowering n={vic['inat_flowering_total']} (iNat)</span>
      <span class="folio-num">07</span>
    </div>
  </div>
</article>

<!-- ======================== PAGE 8: DIONAEA MUSCIPULA (SPREAD 8-9 LEFT) ======================== -->
<article class="page" id="species-dionaea">
  <div class="top-plate-box">
    <img class="plate-hero" style="object-position: center 50%;" src="{p7}" alt="Museum macro specimen of an open crimson Dionaea muscipula Venus flytrap showing three sensory trigger hairs, marginal cilia, and winged petiole" />
    {svg_dio_anat}
    <div class="plate-tag-pill">Plate 07 · Studio Macro · Snap-Buckling Anatomy</div>
  </div>

  <div class="sp-bed">
    <div class="sp-header-row">
      <span class="kicker" style="color:{SPECIES_COLOR['dionaea']};">Clade V · {html.escape(dio['order'])} · {html.escape(dio['family'])}</span>
      <div>{iucn_badge_html(dio)} &nbsp; {gbif_link_html(dio)}</div>
    </div>

    <div class="sp-title-line">
      <h2 class="sp-binomial bm-2"><em>{html.escape(dio['canonical_name'])}</em><span class="sp-authority">{html.escape(dio['authority'])}</span></h2>
      <span class="sp-common">{html.escape(dio['common_name'])}</span>
    </div>

    <div class="sp-2col">
      <div>
        <p class="body-p"><span class="dropcap" style="color:{SPECIES_COLOR['dionaea']};">E</span>ndemic to nitrogen-poor coastal-plain pine savannas of the Carolinas—<strong>{dio['top_countries'][0]['count']:,}</strong> of <strong>{dio['gbif_total_occurrences']:,}</strong> GBIF occurrences (<strong>{dio['top_countries'][0]['count']/dio['gbif_total_occurrences']*100:.1f}%</strong>) lie in the United States—<em>Dionaea muscipula</em> supplements nutrient-starved soils with one of the fastest movements in botany.</p>
        <div class="step-row"><div class="step-badge">1</div><div class="step-text"><strong>First Mechanical Touch:</strong> Deflecting a sensory trichome triggers a calcium-ion action potential that primes electrical memory without closing on raindrops.</div></div>
        <div class="step-row"><div class="step-badge">2</div><div class="step-text"><strong>Second Touch (&lt;20 s):</strong> Crosses threshold; rapid turgor shift flips lobe curvature from convex to concave via elastic <em>snap-buckling</em> in ~100 ms.</div></div>
        <div class="step-row"><div class="step-badge">3</div><div class="step-text"><strong>Struggle Confirmation:</strong> Three additional touches seal the rim airtight and activate acid digestive enzymes.</div></div>
      </div>

      <div>
        {svg_dio_flw}
        <div class="field-check" style="border-left-color:{SPECIES_COLOR['dionaea']};">
          <div class="field-check-head" style="color:{SPECIES_COLOR['dionaea']};">Field Check · Why Flowers Tower Above Traps</div>
          <div class="field-check-body">Empirical iNaturalist phenology concentrates <strong>{dio['inat_monthly_flowering'][4] + dio['inat_monthly_flowering'][5]} of {dio['inat_flowering_total']}</strong> blooms (<strong>{(dio['inat_monthly_flowering'][4] + dio['inat_monthly_flowering'][5])/dio['inat_flowering_total']*100:.1f}%</strong>) into May–June—held atop tall 20–30 cm scapes so flying pollinators avoid the ground-level traps.</div>
        </div>
      </div>
    </div>

    <div class="running-bot" style="left:34pt; right:34pt;">
      <span class="folio-num">08</span>
      <span class="kicker" style="color:#4E5650;">Plate: Nano Banana Studio · IUCN VU · {dio['herbarium_share_pct']:.1f}% Herbaria</span>
    </div>
  </div>
</article>

<!-- ======================== PAGE 9: ADANSONIA DIGITATA (SPREAD 8-9 RIGHT) ======================== -->
<article class="page" id="species-adansonia">
  <div class="p9-top">
    <div class="sp-header-row">
      <span class="kicker" style="color:{SPECIES_COLOR['adansonia']};">Clade VI · {html.escape(adan['order'])} · {html.escape(adan['family'])}</span>
      <div>{iucn_badge_html(adan)} &nbsp; {gbif_link_html(adan)} &nbsp;&nbsp; <span class="folio-num">09</span></div>
    </div>

    <div class="sp-title-line">
      <h2 class="sp-binomial bm-2"><em>{html.escape(adan['canonical_name'])}</em><span class="sp-authority">{html.escape(adan['authority'])}</span></h2>
      <span class="sp-common">{html.escape(adan['common_name'])}</span>
    </div>

    <div class="sp-2col">
      <div>
        <p class="body-p"><span class="dropcap" style="color:{SPECIES_COLOR['adansonia']};">T</span>owering across Sub-Saharan savannas, <em>Adansonia digitata</em> builds its monumental bottle trunk not from dense hardwood, but from fibrous water-storing parenchyma rings—allowing the stem to swell during monsoon rains and contract measurably through months of drought while smooth, fire-resilient bark regenerates after savanna burns.</p>
        <p class="body-p" style="margin-top:6pt;">Live GBIF telemetry documents <strong>{adan['gbif_total_occurrences']:,}</strong> occurrences anchored across Benin (<strong>{adan['top_countries'][0]['count']:,}</strong>), South Africa (<strong>{adan['top_countries'][1]['count']:,}</strong>), Tanzania (<strong>{adan['top_countries'][2]['count']:,}</strong>), and Malawi (<strong>{adan['top_countries'][3]['count']:,}</strong>).</p>
      </div>

      <div>
        {svg_adan_flw}
        <div class="field-check" style="border-left-color:{SPECIES_COLOR['adansonia']}; margin-top:6pt;">
          <div class="field-check-head" style="color:{SPECIES_COLOR['adansonia']};">Field Check · Bat-Pollinated Nocturnal Blooms</div>
          <div class="field-check-body">Large pendulous white flowers unfurl at dusk—peaking empirically in <strong>November ({adan['inat_monthly_flowering'][10]}</strong> of {adan['inat_flowering_total']} iNat bloom records)—timed for straw-colored fruit bats at the onset of southern savanna rains.</div>
        </div>
      </div>
    </div>
  </div>

  <div class="p9-bot">
    <img src="{p8}" alt="Monumental Adansonia digitata African baobab with silvery-taupe pachycaul bottle trunk and sculptural crown at golden hour" />
    <div class="p9-bot-scrim"></div>
    {svg_adan_anat}
    <div class="plate-tag-pill">Plate 08 · African Savanna · Golden-Hour Field Plate</div>
    <div style="position:absolute; bottom:14pt; left:24pt; right:24pt; display:flex; justify-content:space-between; color:#F4F2EA;">
      <span class="kicker" style="font-size:6.1pt; color:#F4F2EA;">Adansonia digitata L. · Malvaceae · Pachycaul Stem-Succulent Architecture</span>
      <span class="kicker" style="font-size:6.1pt; color:#E8C77B;">Plate: Nano Banana Studio · OTT {adan['opentree_ott_id']}</span>
    </div>
  </div>
</article>

<!-- ======================== PAGE 10: DICHOTOMOUS KEY & CRYPTOGRAPHIC COLOPHON ======================== -->
<article class="page" id="field-key">
  <div class="std-page-pad">
    <div class="running-top">
      <span class="kicker" style="color:#005F5A;">Section III · Field Synthesis &amp; Verification</span>
      <span class="kicker" style="color:#464E49;">Interactive Identification Key · Rule 9 Taxonomy Court</span>
    </div>

    <h1 class="serif-display bm-1" style="font-size:24pt; line-height:1.06; color:#181A18; margin-bottom:5pt;">Dichotomous Field Key &amp; Provenance Ledger</h1>
    <p class="body-p" style="margin-bottom:8pt;">
      Follow five observable morphological traits below to classify all six clades in the field. Every species card jumps directly to its monograph plate; every numeric and taxonomic identifier in the verification ledger below links live to its upstream scientific registry.
    </p>

    <div class="exhibit-label">Exhibit 7 · Visual Dichotomous Identification Key (Click Any Species to Jump to Plate)</div>
    <div style="margin-top:4pt; margin-bottom:13pt;">{svg_key}</div>

    <div class="exhibit-label">Exhibit 8 · Rule 9 Scientific Taxonomy &amp; Live Open-Data Reconciliation Ledger</div>
    <table class="r9-table">
      <thead>
        <tr>
          <th>Accepted Binomial &amp; Authority (GBIF)</th>
          <th>Family</th>
          <th class="num">GBIF Key</th>
          <th class="num">OTT ID</th>
          <th class="num">IUCN</th>
          <th class="num">GBIF Occ.</th>
          <th class="num">Herb. %</th>
          <th class="num">iNat Flw.</th>
        </tr>
      </thead>
      <tbody>
        {rule9_rows}
      </tbody>
    </table>

    <div class="receipt-grid">
      <div>
        <div class="kicker" style="color:#005F5A; font-size:6.2pt; margin-bottom:4pt;">Cryptographic Integrity &amp; Anti-Cheat Audit</div>
        <p style="font-family:'Charter',serif; font-size:7.6pt; line-height:1.42; color:#1F2320;">
          <strong>Sealed Manifest:</strong> {manifest_count} raw API JSON &amp; plate files hashed in <code>data/manifest.sha256</code>.<br/>
          <strong>Atomic Provenance:</strong> {ledger_count} 1:1 tuples reconciled in <code>data/provenance_ledger.json</code>.<br/>
          <strong>Rule 3 &amp; Rule 9 Gates:</strong> Python AST anti-circular linter passed; all binomials, authorities, families, and OTT IDs verified verbatim against live APIs. Unlinked IUCN statuses preserved as explicit <code>[N/A]</code>.
        </p>
      </div>
      <div>
        <div class="kicker" style="color:#005F5A; font-size:6.2pt; margin-bottom:4pt;">Colophon &amp; Transparent Photographic Attribution</div>
        <p style="font-family:'Charter',serif; font-size:7.6pt; line-height:1.42; color:#1F2320;">
          <strong>Botanical Plates (01–08):</strong> Generated via Nano Banana Studio (AI Editorial Photography) with zero embedded text, then overlaid with deterministic pure-vector SVG anatomy diagrams.<br/>
          <strong>Production Spec:</strong> 612 × 792 pt · WeasyPrint 67.0 · PDF/UA-1 Tagged &amp; Bookmarked · Audited for WCAG 2.1 background-sampled contrast, clip-aware plate coverage, and facing-spread pacing.
        </p>
      </div>
    </div>

    <div class="running-bot">
      <span class="kicker" style="color:#4E5650;">Botanica Veridica · Open-Source Reference Demo (verifiable-editorial-skills)</span>
      <span class="folio-num">10</span>
    </div>
  </div>
</article>

</main>
</body>
</html>
"""


def main() -> int:
    parser = argparse.ArgumentParser(description="Compile BOTANICA VERIDICA scientific monograph PDF.")
    parser.add_argument("--prepress", action="store_true", help="Emit print-shop PDF with 3mm bleed & crop marks.")
    parser.add_argument("--skip-latch", action="store_true", help="Internal debug only; default enforces Rule 6 latch.")
    args = parser.parse_args()

    # Rule 6: Substance Precedence Compilation Latch
    if not args.skip_latch:
        res = subprocess.run([sys.executable, str(ROOT / "scripts" / "verify_integrity.py")], check=False)
        if res.returncode != 0:
            print("FAIL (Rule 6 Compilation Latch): verify_integrity.py did not pass. Refusing to compile.", file=sys.stderr)
            return 1

    summary = json.loads(SUMMARY_JSON.read_text(encoding="utf-8"))
    manifest_count = len([ln for ln in MANIFEST_PATH.read_text(encoding="utf-8").splitlines() if ln.strip()])
    ledger_count = len(json.loads(LEDGER_JSON.read_text(encoding="utf-8")))

    html_str = build_html(summary, manifest_count, ledger_count, prepress=args.prepress)
    out_name = "BOTANICA_VERIDICA_PREPRESS.pdf" if args.prepress else "BOTANICA_VERIDICA_MONOGRAPH.pdf"
    out_pdf = REPORT_DIR / out_name

    # Digital edition uses PDF/UA-1 tagged accessibility; prepress uses standard print PDF with crop/bleed marks
    write_kwargs = {} if args.prepress else {"pdf_variant": "pdf/ua-1"}
    HTML(string=html_str, base_url=str(REPORT_DIR)).write_pdf(str(out_pdf), **write_kwargs)

    size_mb = out_pdf.stat().st_size / (1024 * 1024)
    mode_lbl = "PREPRESS (3mm bleed + crop marks)" if args.prepress else "DIGITAL (PDF/UA-1 + bookmarks + links)"
    print(f"[compile_monograph] Wrote {out_pdf} ({size_mb:.2f} MB) [{mode_lbl}]")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
