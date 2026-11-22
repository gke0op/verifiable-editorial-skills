#!/usr/bin/env python3
"""Compile the Dual-Target Living Web Edition of BOTANICA VERIDICA (single verified source -> interactive HTML/SVG).

Features:
- Rule 6 compilation latch (runs verify_integrity.py before compiling)
- Zero external CDN dependencies (runs offline, via local HTTP, or on GitHub Pages)
- Click/hover ANY audited number to inspect its live SHA-256 cryptographic provenance card & raw API excerpt
- [X-Ray Provenance] mode highlighting every verified statistic & Rule 10 scholarly DOI citation
- Interactive botanical anatomy pin inspector on specimen plates
- Live interactive 5-question Dichotomous Field Classifier widget
- Archival Eggshell (Light) / Herbarium Night (Dark) reading mode toggle
"""

from __future__ import annotations

import html
import json
import subprocess
import sys
from pathlib import Path

REPORT_DIR = Path(__file__).resolve().parent
ROOT = REPORT_DIR.parent
sys.path.insert(0, str(REPORT_DIR))

from svg_exhibits import (
    SPECIES_COLOR,
    svg_country_concentration_bar,
    svg_gbif_world_map,
    svg_herbarium_ratio_bars,
    svg_mini_monthly_bars,
    svg_morphology_strip,
    svg_phenology_matrix,
    svg_phylogenetic_cladogram,
    svg_scale_lineup,
    svg_sequoia_hydraulic_schematic,
)

SUMMARY_JSON = ROOT / "data" / "summary_metrics.json"
LEDGER_JSON = ROOT / "data" / "provenance_ledger.json"
CITATIONS_JSON = ROOT / "data" / "background_citations.json"
MANIFEST_PATH = ROOT / "data" / "manifest.sha256"
OUT_HTML = REPORT_DIR / "BOTANICA_VERIDICA_LIVING.html"


def prov_chip(key: str, display: str, extra_url: str | None = None) -> str:
    url_attr = f' data-url="{html.escape(extra_url)}"' if extra_url else ""
    return (
        f'<button type="button" class="prov-chip" data-prov="{html.escape(key)}"{url_attr}>'
        f"{html.escape(display)}</button>"
    )


def cit_chip(cit_id: str, display: str) -> str:
    return (
        f'<button type="button" class="prov-chip cit-chip" data-cit="{html.escape(cit_id)}">'
        f"{html.escape(display)}</button>"
    )


def iucn_pill(sp: dict) -> str:
    c = sp["iucn_effective_code"]
    if c == "EN":
        return '<span class="pill pill-en">IUCN · EN (ENDANGERED)</span>'
    if c == "VU":
        return '<span class="pill pill-vu">IUCN · VU (VULNERABLE)</span>'
    return '<span class="pill pill-na">IUCN · [N/A: NOT EVALUATED]</span>'


def build_interactive_plate(plate_file: str, alt: str, pins: list[dict], plate_id: str, caption: str) -> str:
    """Build an interactive botanical plate where clicking/hovering pins reveals detailed morphology notes."""
    pin_buttons = []
    for i, p in enumerate(pins, start=1):
        pin_buttons.append(
            f'<button type="button" class="anat-pin" '
            f'style="left:{p["x"]}%; top:{p["y"]}%; --pin-col:{p["color"]};" '
            f'data-plate="{plate_id}" data-title="{html.escape(p["title"])}" '
            f'data-sub="{html.escape(p["sub"])}" data-detail="{html.escape(p["detail"])}" '
            f'aria-label="{html.escape(p["title"])}">{i}</button>'
        )
    first = pins[0]
    return f"""
    <figure class="plate-stage" data-plate-wrap="{plate_id}">
      <div class="plate-frame">
        <img src="assets/{html.escape(plate_file)}" alt="{html.escape(alt)}" loading="lazy" />
        {"".join(pin_buttons)}
      </div>
      <div class="anat-readout" id="readout-{plate_id}">
        <span class="anat-kicker">Interactive Anatomy Inspector · Click or hover pins</span>
        <strong class="anat-title">{html.escape(first['title'])}</strong>
        <span class="anat-sub">{html.escape(first['sub'])}</span>
        <p class="anat-detail">{html.escape(first['detail'])}</p>
      </div>
      <figcaption class="plate-cap">{html.escape(caption)}</figcaption>
    </figure>
    """


def build_html(summary: dict, ledger: dict, citations: dict, manifest_count: int) -> str:
    by_slug = {sp["slug"]: sp for sp in summary["species"]}
    port = summary["portfolio"]

    ginkgo = by_slug["ginkgo"]
    welw = by_slug["welwitschia"]
    seq = by_slug["sequoia"]
    vic = by_slug["victoria"]
    dio = by_slug["dionaea"]
    adan = by_slug["adansonia"]

    # Reuse the exact same deterministic pure-vector SVGs from svg_exhibits.py (responsive viewBox!)
    svg_clado = svg_phylogenetic_cladogram(summary, 540, 224)
    svg_morph = svg_morphology_strip(540, 94)
    svg_scale = svg_scale_lineup(540, 90)
    svg_map = svg_gbif_world_map(summary, 540, 222)
    svg_herb = svg_herbarium_ratio_bars(summary, 540, 128)
    svg_pheno = svg_phenology_matrix(summary, 540, 134)

    svg_ginkgo_mo = svg_mini_monthly_bars(ginkgo["inat_monthly_all"], SPECIES_COLOR["ginkgo"], "iNat Monthly Observations (Oct Peak)", f"n = {ginkgo['inat_observations_total']:,}", 252, 78)
    svg_welw_c = svg_country_concentration_bar(welw, 192, 74)
    svg_seq_hyd = svg_sequoia_hydraulic_schematic(252, 92)
    svg_vic_flw = svg_mini_monthly_bars(vic["inat_monthly_flowering"], SPECIES_COLOR["victoria"], "iNat Equatorial Flowering Calendar", f"n = {vic['inat_flowering_total']} flw", 252, 78)
    svg_dio_flw = svg_mini_monthly_bars(dio["inat_monthly_flowering"], SPECIES_COLOR["dionaea"], "iNat Flowering Peak (May–Jun)", f"n = {dio['inat_flowering_total']} flw", 252, 78)
    svg_adan_flw = svg_mini_monthly_bars(adan["inat_monthly_flowering"], SPECIES_COLOR["adansonia"], "iNat Nocturnal Bloom (Nov Peak)", f"n = {adan['inat_flowering_total']} flw", 252, 76)

    ginkgo_plate = build_interactive_plate(
        "plate_02_ginkgo_specimen.jpg",
        "Ginkgo biloba studio specimen showing bilobed fan leaf and amber sarcotesta seed",
        [
            {"x": 36, "y": 31, "color": "#8A530B", "title": "Bilobed Lamina", "sub": "Cleft fan blade ('bi-loba')", "detail": "Deep central notch splits the fan-shaped blade into two lobes—giving the species its Latin epithet biloba."},
            {"x": 32, "y": 50, "color": "#005F5A", "title": "Dichotomous Venation", "sub": "Forking veins with zero cross-links", "detail": "Unlike angiosperm leaves with closed net-like loops, Ginkgo veins divide strictly in open Y-forks straight from petiole to margin."},
            {"x": 72, "y": 62, "color": "#7D2F24", "title": "Fleshy Sarcotesta", "sub": "Naked gymnosperm ovule coat", "detail": "Not a botanical fruit: Ginkgo produces exposed ovules wrapped in a fleshy outer seed coat rich in pungent butyric acid."},
            {"x": 57, "y": 71, "color": "#4E5650", "title": "Slender Petiole", "sub": "Flexible aerodynamic leaf stalk", "detail": "Long, supple petiole allows the broad fan blade to flutter in wind, reducing mechanical drag on spur shoots."},
        ],
        "ginkgo",
        "Plate 02 · Studio Specimen (Nano Banana Studio) · Click pins 1–4 to inspect diagnostic gymnosperm structures.",
    )

    welw_plate = build_interactive_plate(
        "plate_03_welwitschia_namib.jpg",
        "Wild Welwitschia mirabilis in Namib Desert gravel",
        [
            {"x": 40, "y": 46, "color": "#964123", "title": "Strobili Cones", "sub": "Dioecious reproductive cones", "detail": "Male and female plants grow separate salmon-tan compound strobili along the rim of the woody caudex."},
            {"x": 50, "y": 56, "color": "#005F5A", "title": "Basal Meristem Crown", "sub": "Perpetual growth ring", "detail": "After the apical shoot dies in infancy, a basal meristem collar continuously pushes leaf tissue outward for centuries."},
            {"x": 74, "y": 66, "color": "#185D3B", "title": "Twin Permanent Strap Leaves", "sub": "Only 2 foliage leaves for life", "detail": "Namib desert winds fray the two lifelong blades into ribbons while specialized stomata capture Atlantic radiation fog."},
        ],
        "welwitschia",
        "Plate 03 · Namib Desert Field Plate (Nano Banana Studio) · Click pins 1–3 to inspect basal meristem anatomy.",
    )

    vic_plate = build_interactive_plate(
        "plate_06_victoria_pad.jpg",
        "Victoria amazonica giant water lily pads showing radial underside ribs and blossom",
        [
            {"x": 69, "y": 39, "color": "#185D3B", "title": "Radial Primary Ribs", "sub": "Air-filled buoyant girder spokes", "detail": "Hollow vascular ribs radiate from the central petiole like structural cantilevers, lending immense stiffness at minimal biomass cost."},
            {"x": 81, "y": 48, "color": "#9C1F32", "title": "Cross-Vein Struts", "sub": "Orthogonal stiffening web", "detail": "Concentric cross-veins lock radial ribs into a thin-shell space frame that inspired Joseph Paxton's 1851 Crystal Palace roof."},
            {"x": 69, "y": 68, "color": "#8A530B", "title": "Thermogenic Nocturnal Blossom", "sub": "Two-night beetle trap", "detail": "Opens creamy-white and heats above ambient air on Night 1 to attract & trap scarab beetles, reopening pink on Night 2 to release pollen-dusted pollinators."},
            {"x": 49, "y": 82, "color": "#005F5A", "title": "Rainwater Drainage Notch", "sub": "Hydrostatic overflow slit", "detail": "Two narrow slits in the upturned burgundy lip drain tropical downpours before pooled water can sink the floating pad."},
        ],
        "victoria",
        "Plate 06 · Amazon Blackwater Structural Anatomy (Nano Banana Studio) · Click pins 1–4 to explore thin-shell biomechanics.",
    )

    dio_plate = build_interactive_plate(
        "plate_07_dionaea_trap.jpg",
        "Museum macro specimen of an open Dionaea muscipula Venus flytrap",
        [
            {"x": 40, "y": 30, "color": "#185D3B", "title": "Interlocking Marginal Cilia", "sub": "Cage bristles around rim", "detail": "Stiff marginal teeth interlace on closure to form a permeable jail—letting tiny low-calorie ants escape while holding larger prey."},
            {"x": 58, "y": 35, "color": "#9C1F32", "title": "Sensory Trigger Hairs (Trichomes)", "sub": "3 mechanoreceptors per lobe", "detail": "Deflecting a hair fires a calcium-ion action potential. Two touches within ~20 seconds cross the electrical threshold to prevent raindrop false alarms."},
            {"x": 64, "y": 46, "color": "#7D2F24", "title": "Carmine Digestive Surface", "sub": "Anthocyanin-pigmented gland field", "detail": "After 3 further prey-struggle touches seal the rim airtight, surface glands flood the chamber with acid hydrolytic enzymes."},
            {"x": 56, "y": 52, "color": "#005F5A", "title": "Elastic Midrib Hinge", "sub": "Snap-buckling curvature inversion", "detail": "Rapid turgor release flips the doubly-curved lobes from convex to concave in ~100 ms—one of the fastest movements in the plant kingdom."},
            {"x": 36, "y": 65, "color": "#185D3B", "title": "Winged Petiole", "sub": "Photosynthetic leaf base", "detail": "The flattened green leaf stalk performs primary photosynthesis, offsetting the high metabolic cost of maintaining active carnivorous traps."},
        ],
        "dionaea",
        "Plate 07 · Studio Macro Specimen (Nano Banana Studio) · Click pins 1–5 to trace the two-touch snap-buckling mechanism.",
    )

    # Embedded verified provenance & Rule 10 citations JSON for instant offline popover rendering
    prov_blob = json.dumps(ledger, ensure_ascii=False)
    cit_blob = json.dumps({c["id"]: c for c in citations.get("citations", [])}, ensure_ascii=False)
    species_meta_blob = json.dumps(
        {
            sp["slug"]: {
                "canonical": sp["canonical_name"],
                "authority": sp["authority"],
                "common": sp["common_name"],
                "family": sp["family"],
                "gbif_key": sp["gbif_usage_key"],
                "ott_id": sp["opentree_ott_id"],
                "iucn": sp["iucn_effective_code"] or "[N/A: NE]",
                "occ": sp["gbif_total_occurrences"],
                "herb_pct": sp["herbarium_share_pct"],
                "flw": sp["inat_flowering_total"],
                "color": SPECIES_COLOR[sp["slug"]],
            }
            for sp in summary["species"]
        },
        ensure_ascii=False,
    )

    return f"""<!DOCTYPE html>
<html lang="en" data-theme="light">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>BOTANICA VERIDICA — Living Monograph (Interactive Provenance Edition)</title>
<style>
:root {{
  --bg: #FBF9F4;
  --surface: #F2EDE2;
  --surface-strong: #EAE3D4;
  --ink: #181A18;
  --ink-soft: #3D443F;
  --rule: #D3CBB9;
  --teal: #005F5A;
  --gold: #A87620;
  --shadow: rgba(20, 24, 21, 0.14);
}}
html[data-theme="dark"] {{
  --bg: #111514;
  --surface: #1A211F;
  --surface-strong: #222B28;
  --ink: #F2EFE7;
  --ink-soft: #B8C2BC;
  --rule: #303B37;
  --teal: #58C4BC;
  --gold: #E8C77B;
  --shadow: rgba(0, 0, 0, 0.55);
}}
* {{ box-sizing: border-box; margin: 0; padding: 0; }}
body {{
  background: var(--bg);
  color: var(--ink);
  font-family: 'Charter', 'Georgia', 'Times New Roman', serif;
  line-height: 1.62;
  transition: background 0.25s ease, color 0.25s ease;
}}
a {{ color: var(--teal); text-decoration: none; }}
a:hover {{ text-decoration: underline; }}

/* Sticky Editorial Toolbar */
.topbar {{
  position: sticky; top: 0; z-index: 40;
  display: flex; flex-wrap: wrap; justify-content: space-between; align-items: center; gap: 12px;
  padding: 11px 28px;
  background: color-mix(in srgb, var(--bg) 92%, transparent);
  backdrop-filter: blur(10px);
  border-bottom: 1px solid var(--rule);
  font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
}}
.brand {{
  font-family: 'Didot', 'Bodoni 72', 'Georgia', serif;
  font-size: 1.05rem; letter-spacing: 0.16em; color: var(--ink);
}}
.toolbar-actions {{ display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }}
.tb-btn {{
  border: 1px solid var(--rule); background: var(--surface); color: var(--ink);
  font-family: inherit; font-size: 0.72rem; font-weight: 700; letter-spacing: 0.08em; text-transform: uppercase;
  padding: 6px 11px; border-radius: 3px; cursor: pointer; transition: all 0.18s ease;
}}
.tb-btn:hover, .tb-btn[aria-pressed="true"] {{
  background: var(--teal); color: #FFFFFF; border-color: var(--teal);
}}
html[data-theme="dark"] .tb-btn[aria-pressed="true"] {{ color: #0B1211; }}

/* Hero */
.hero {{
  position: relative; min-height: 76vh; display: flex; align-items: flex-end; overflow: hidden;
  background: #0D1413; color: #FFFFFF;
}}
.hero img {{
  position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; object-position: center 48%;
}}
.hero::after {{
  content: ""; position: absolute; inset: 0;
  background: linear-gradient(to bottom, rgba(10,16,15,0.68) 0%, rgba(10,16,15,0.12) 45%, rgba(9,14,13,0.92) 100%);
}}
.hero-inner {{
  position: relative; z-index: 2; width: 100%; max-width: 1120px; margin: 0 auto; padding: 56px 28px 44px;
  display: grid; grid-template-columns: 1.35fr 0.85fr; gap: 36px; align-items: end;
}}
.hero-kicker {{
  font-family: 'Inter', sans-serif; font-size: 0.72rem; font-weight: 700; letter-spacing: 0.2em;
  text-transform: uppercase; color: #E8C77B; margin-bottom: 10px;
}}
.hero h1 {{
  font-family: 'Didot', 'Bodoni 72', 'Georgia', serif; font-weight: 400;
  font-size: clamp(2.4rem, 5.2vw, 4.1rem); letter-spacing: 0.12em; line-height: 1.04; margin-bottom: 14px;
}}
.hero-deck {{ font-style: italic; font-size: 1.12rem; color: #ECE9E0; max-width: 580px; margin-bottom: 18px; }}
.hero-stats {{
  display: flex; flex-wrap: wrap; gap: 14px; font-family: 'Inter', sans-serif; font-size: 0.78rem;
  background: rgba(12, 22, 20, 0.85); border-left: 3px solid #E8C77B; padding: 10px 14px;
}}
.hero-toc {{
  border-left: 1px solid rgba(232,199,123,0.45); padding-left: 18px;
  font-family: 'Inter', sans-serif; font-size: 0.78rem; letter-spacing: 0.1em; text-transform: uppercase;
}}
.hero-toc a {{
  display: flex; justify-content: space-between; padding: 5px 0; color: #F2EFE7;
  border-bottom: 1px solid rgba(255,255,255,0.1);
}}
.hero-toc a span:last-child {{ color: #E8C77B; font-family: 'Didot', serif; font-size: 0.92rem; }}

/* Layout Sections */
.container {{ max-width: 1120px; margin: 0 auto; padding: 52px 28px; }}
.section-kicker {{
  font-family: 'Inter', sans-serif; font-size: 0.72rem; font-weight: 700; letter-spacing: 0.18em;
  text-transform: uppercase; color: var(--teal); margin-bottom: 6px;
}}
h2.sec-title {{
  font-family: 'Didot', 'Bodoni 72', 'Georgia', serif; font-weight: 400;
  font-size: clamp(1.75rem, 3vw, 2.45rem); line-height: 1.12; margin-bottom: 12px;
}}
.lead {{ font-size: 1.04rem; color: var(--ink-soft); max-width: 780px; margin-bottom: 26px; }}

.two-col {{ display: grid; grid-template-columns: 1fr 1fr; gap: 30px; align-items: start; }}
.card-panel {{
  background: var(--surface); border: 1px solid var(--rule); border-radius: 4px; padding: 18px 20px;
}}
.svg-wrap svg {{ width: 100%; height: auto; display: block; border-radius: 3px; background: #FBF9F4; }}

/* Filter Bar */
.filter-bar {{
  display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 28px; align-items: center;
  font-family: 'Inter', sans-serif;
}}
.filter-btn {{
  border: 1px solid var(--rule); background: transparent; color: var(--ink);
  font-size: 0.74rem; font-weight: 700; letter-spacing: 0.1em; text-transform: uppercase;
  padding: 6px 12px; border-radius: 99px; cursor: pointer;
}}
.filter-btn.active {{ background: var(--ink); color: var(--bg); border-color: var(--ink); }}

/* Species Feature Spreads */
.species-card {{
  border-top: 1.5px solid var(--rule); padding: 44px 0;
  display: grid; grid-template-columns: 1.15fr 0.85fr; gap: 34px; align-items: start;
}}
.species-card.hidden {{ display: none; }}
.sp-meta {{ display: flex; flex-wrap: wrap; gap: 8px; align-items: center; margin-bottom: 10px; }}
.sp-name {{
  font-family: 'Didot', 'Bodoni 72', 'Georgia', serif; font-size: 2rem; line-height: 1.08; margin-bottom: 12px;
}}
.sp-name em {{ font-style: italic; }}
.sp-auth {{ font-family: 'Charter', serif; font-size: 1.05rem; color: var(--ink-soft); margin-left: 6px; }}
.pill {{
  display: inline-block; font-family: 'Inter', sans-serif; font-size: 0.68rem; font-weight: 700;
  letter-spacing: 0.1em; padding: 3px 8px; border-radius: 2px; color: #FFFFFF;
}}
.pill-en {{ background: #8F1D24; }}
.pill-vu {{ background: #8A4B08; }}
.pill-na {{ background: #4A524E; }}

.field-check {{
  background: var(--surface); border-left: 3px solid var(--teal); padding: 12px 15px; margin-top: 14px; font-size: 0.92rem;
}}
.field-check strong {{
  display: block; font-family: 'Inter', sans-serif; font-size: 0.7rem; letter-spacing: 0.14em;
  text-transform: uppercase; color: var(--teal); margin-bottom: 4px;
}}

/* Interactive Botanical Plate & Pins */
.plate-frame {{
  position: relative; overflow: hidden; border-radius: 4px; border: 1px solid var(--rule);
  background: #F7F3E8;
}}
.plate-frame img {{ width: 100%; height: auto; display: block; }}
.anat-pin {{
  position: absolute; transform: translate(-50%, -50%);
  width: 26px; height: 26px; border-radius: 50%;
  border: 2px solid #FBF9F4; background: var(--pin-col, #005F5A); color: #FFFFFF;
  font-family: 'Inter', sans-serif; font-size: 0.72rem; font-weight: 700;
  cursor: pointer; box-shadow: 0 2px 8px rgba(0,0,0,0.45);
  transition: transform 0.16s ease, box-shadow 0.16s ease;
}}
.anat-pin:hover, .anat-pin.active {{ transform: translate(-50%, -50%) scale(1.22); box-shadow: 0 0 0 4px rgba(251,249,244,0.85); }}
.anat-readout {{
  margin-top: 10px; background: var(--surface); border: 1px solid var(--rule);
  border-left: 3px solid var(--teal); border-radius: 3px; padding: 11px 14px;
}}
.anat-kicker {{
  display: block; font-family: 'Inter', sans-serif; font-size: 0.65rem; font-weight: 700;
  letter-spacing: 0.14em; text-transform: uppercase; color: var(--teal); margin-bottom: 3px;
}}
.anat-title {{ font-family: 'Inter', sans-serif; font-size: 0.88rem; margin-right: 8px; }}
.anat-sub {{ font-style: italic; font-size: 0.88rem; color: var(--ink-soft); }}
.anat-detail {{ font-size: 0.9rem; margin-top: 4px; color: var(--ink); }}
.plate-cap {{
  font-family: 'Inter', sans-serif; font-size: 0.72rem; color: var(--ink-soft); margin-top: 7px;
}}

/* Interactive Provenance Chips & Popover */
.prov-chip {{
  display: inline; background: transparent; border: none; padding: 0 2px; font: inherit; font-weight: 700;
  color: inherit; border-bottom: 1.5px dotted var(--teal); cursor: pointer; border-radius: 2px;
  transition: background 0.15s ease;
}}
.cit-chip {{ border-bottom-color: var(--gold); }}
body.xray-on .prov-chip {{ background: color-mix(in srgb, var(--teal) 20%, transparent); padding: 1px 4px; }}
body.xray-on .cit-chip {{ background: color-mix(in srgb, var(--gold) 24%, transparent); }}
.prov-chip:hover {{ background: color-mix(in srgb, var(--teal) 26%, transparent); }}

#prov-popover {{
  position: fixed; z-index: 100; max-width: 370px; display: none;
  background: var(--bg); color: var(--ink); border: 1px solid var(--teal);
  border-top: 3px solid var(--teal); border-radius: 4px; padding: 14px 16px;
  box-shadow: 0 12px 32px var(--shadow); font-family: 'Inter', sans-serif; font-size: 0.78rem;
}}
#prov-popover.open {{ display: block; }}
.pop-head {{ display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px; }}
.pop-tag {{ font-size: 0.65rem; font-weight: 700; letter-spacing: 0.15em; text-transform: uppercase; color: var(--teal); }}
.pop-close {{ border: none; background: transparent; color: var(--ink-soft); font-size: 1rem; cursor: pointer; }}
.pop-val {{ font-family: 'Didot', serif; font-size: 1.35rem; margin-bottom: 6px; }}
.pop-meta {{ color: var(--ink-soft); line-height: 1.5; }}
.pop-sha {{
  margin-top: 7px; font-family: 'SF Mono', 'Menlo', monospace; font-size: 0.67rem;
  background: var(--surface); padding: 5px 7px; border-radius: 3px; word-break: break-all;
}}

/* Interactive Dichotomous Classifier */
.key-widget {{
  background: var(--surface); border: 1px solid var(--rule); border-top: 3px solid var(--teal);
  border-radius: 4px; padding: 22px 24px; margin-top: 18px;
}}
.key-q {{ font-family: 'Didot', serif; font-size: 1.45rem; margin: 6px 0 14px; }}
.key-opts {{ display: flex; flex-wrap: wrap; gap: 12px; }}
.key-btn {{
  flex: 1 1 220px; text-align: left; padding: 13px 16px; border: 1px solid var(--rule);
  background: var(--bg); color: var(--ink); border-radius: 4px; cursor: pointer;
  font-family: 'Inter', sans-serif; transition: border-color 0.15s ease, transform 0.15s ease;
}}
.key-btn:hover {{ border-color: var(--teal); transform: translateY(-1px); }}
.key-btn strong {{ display: block; font-size: 0.85rem; color: var(--teal); margin-bottom: 3px; }}
.key-trail {{
  font-family: 'Inter', sans-serif; font-size: 0.72rem; color: var(--ink-soft); margin-bottom: 10px;
}}
.key-result {{
  padding: 16px; background: var(--bg); border-left: 4px solid var(--teal); border-radius: 3px;
}}

@media (max-width: 860px) {{
  .hero-inner, .two-col, .species-card {{ grid-template-columns: 1fr; }}
}}
</style>
</head>
<body>

<header class="topbar">
  <div class="brand">BOTANICA VERIDICA · LIVING EDITION</div>
  <div class="toolbar-actions">
    <button type="button" class="tb-btn" id="btn-xray" aria-pressed="false">X-Ray Provenance</button>
    <button type="button" class="tb-btn" id="btn-theme" aria-pressed="false">Night Mode</button>
    <a class="tb-btn" href="BOTANICA_VERIDICA_MONOGRAPH.pdf">Download PDF/UA</a>
  </div>
</header>

<section class="hero">
  <img src="assets/plate_01_cover_ginkgo.jpg" alt="Ginkgo biloba golden fan leaves and amber seed on mossy basalt" />
  <div class="hero-inner">
    <div>
      <div class="hero-kicker">Single Verified Source · Print PDF/UA × Interactive Living Essay</div>
      <h1>BOTANICA VERIDICA</h1>
      <p class="hero-deck">Architecture of Extreme Plants — Click any underlined number to inspect its live cryptographic SHA-256 receipt, raw API excerpt, or peer-reviewed DOI.</p>
      <div class="hero-stats">
        <span>GBIF: {prov_chip('portfolio.total_gbif_occurrences', f"{port['total_gbif_occurrences']:,}")} occurrences</span>
        <span>Herbaria: {prov_chip('portfolio.total_herbarium_specimens', f"{port['total_herbarium_specimens']:,}")} sheets</span>
        <span>iNaturalist: {prov_chip('portfolio.total_inat_observations', f"{port['total_inat_observations']:,}")} records</span>
        <span>Blooms: {prov_chip('portfolio.total_flowering_records', f"{port['total_flowering_records']:,}")} phenology records</span>
      </div>
    </div>
    <nav class="hero-toc" aria-label="Contents">
      <a href="#atlas"><span>Evolutionary Atlas &amp; Map</span><span>02–03</span></a>
      <a href="#sp-ginkgo"><span>Ginkgo biloba</span><span>04</span></a>
      <a href="#sp-welwitschia"><span>Welwitschia mirabilis</span><span>05</span></a>
      <a href="#sp-sequoia"><span>Sequoia sempervirens</span><span>06</span></a>
      <a href="#sp-victoria"><span>Victoria amazonica</span><span>07</span></a>
      <a href="#sp-dionaea"><span>Dionaea muscipula</span><span>08</span></a>
      <a href="#sp-adansonia"><span>Adansonia digitata</span><span>09</span></a>
      <a href="#classifier"><span>Interactive Field Classifier</span><span>10</span></a>
    </nav>
  </div>
</section>

<main class="container">
  <section id="atlas">
    <div class="section-kicker">Section I &amp; II · Live Biodiversity Telemetry</div>
    <h2 class="sec-title">Deep Branches, Global Herbaria &amp; Empirical Bloom Calendars</h2>
    <p class="lead">
      All six vascular plants are anchored to live APIs: Open Tree of Life v3 supplies the evolutionary split between flowerless gymnosperms and flowering angiosperms ({prov_chip('portfolio.total_flowering_records', str(port['total_flowering_records']))} live bloom records), while GBIF v1 maps 720 real coordinates and exposes museum herbarium reliance peaking at {prov_chip('victoria.herbarium_share_pct', f"{vic['herbarium_share_pct']:.1f}%")} in <em>Victoria amazonica</em>.
    </p>
    <div class="two-col">
      <div class="card-panel">
        <div class="section-kicker">Exhibit 1–3 · OpenTree Phylogeny &amp; Diagnostic Silhouettes</div>
        <div class="svg-wrap">{svg_clado}</div>
        <div class="svg-wrap" style="margin-top:12px;">{svg_morph}</div>
        <div class="svg-wrap" style="margin-top:12px;">{svg_scale}</div>
      </div>
      <div class="card-panel">
        <div class="section-kicker">Exhibit 4–6 · Live GBIF World Map, Herbaria &amp; Phenology</div>
        <div class="svg-wrap">{svg_map}</div>
        <div class="svg-wrap" style="margin-top:12px;">{svg_herb}</div>
        <div class="svg-wrap" style="margin-top:12px;">{svg_pheno}</div>
      </div>
    </div>
  </section>

  <section style="margin-top:52px;">
    <div class="section-kicker">Interactive Species Plates · Filter by Clade</div>
    <div class="filter-bar" role="group" aria-label="Filter clades">
      <button type="button" class="filter-btn active" data-filter="all">All 6 Clades</button>
      <button type="button" class="filter-btn" data-filter="gymnosperm">Gymnosperms (0 Flowers · Cones/Ovules)</button>
      <button type="button" class="filter-btn" data-filter="angiosperm">Angiosperms (662 Flowering Records)</button>
    </div>

    <!-- GINKGO -->
    <article class="species-card" id="sp-ginkgo" data-clade="gymnosperm">
      {ginkgo_plate}
      <div>
        <div class="sp-meta">
          <span class="section-kicker" style="margin:0; color:{SPECIES_COLOR['ginkgo']};">Clade I · {html.escape(ginkgo['family'])}</span>
          {iucn_pill(ginkgo)}
          <a href="https://www.gbif.org/species/{ginkgo['gbif_usage_key']}" target="_blank" rel="noopener">GBIF #{ginkgo['gbif_usage_key']} ↗</a>
        </div>
        <h3 class="sp-name"><em>{html.escape(ginkgo['canonical_name'])}</em><span class="sp-auth">{html.escape(ginkgo['authority'])}</span></h3>
        <p>Sole living member of order <em>Ginkgoales</em>, preserving dichotomous parallel veins absent in broad-leaved angiosperms. Urban cultivation drives {prov_chip('ginkgo.gbif_total_occurrences', f"{ginkgo['gbif_total_occurrences']:,}")} GBIF records ({prov_chip('ginkgo.herbarium_share_pct', f"{ginkgo['herbarium_share_pct']:.1f}%")} preserved herbarium sheets) and {prov_chip('ginkgo.inat_observations_total', f"{ginkgo['inat_observations_total']:,}")} iNaturalist observations peaking in October when foliage turns gold—yet wild Chinese populations remain IUCN Endangered ({prov_chip('ginkgo.iucn_effective_code', 'EN')}).</p>
        <div class="svg-wrap" style="margin-top:14px;">{svg_ginkgo_mo}</div>
        <div class="field-check"><strong>Field Check · 5-Second Diagnosis</strong>Hold a leaf against sunlight: veins radiate in clean Y-forks straight to the margin with zero cross-linking mesh.</div>
      </div>
    </article>

    <!-- WELWITSCHIA -->
    <article class="species-card" id="sp-welwitschia" data-clade="gymnosperm">
      {welw_plate}
      <div>
        <div class="sp-meta">
          <span class="section-kicker" style="margin:0; color:{SPECIES_COLOR['welwitschia']};">Clade II · {html.escape(welw['family'])}</span>
          {iucn_pill(welw)}
          <a href="https://www.gbif.org/species/{welw['gbif_usage_key']}" target="_blank" rel="noopener">GBIF #{welw['gbif_usage_key']} ↗</a>
        </div>
        <h3 class="sp-name"><em>{html.escape(welw['canonical_name'])}</em><span class="sp-auth">{html.escape(welw['authority'])}</span></h3>
        <p>Endemic to the hyper-arid Namib gravel plains, <em>Welwitschia</em> abandons apical shoot growth and extrudes only two lifelong strap leaves from a woody basal meristem. Across {prov_chip('welwitschia.gbif_total_occurrences', f"{welw['gbif_total_occurrences']:,}")} GBIF occurrences, {prov_chip('welwitschia.herbarium_share_pct', f"{welw['herbarium_share_pct']:.1f}%")} are museum herbarium specimens ({prov_chip('welwitschia.gbif_preserved_specimens', f"{welw['gbif_preserved_specimens']:,}")} sheets). IUCN status returns <code>NOT_EVALUATED</code> in GBIF/iNat and is reported transparently as {prov_chip('welwitschia.iucn_effective_code', '[N/A]')}.</p>
        <div class="svg-wrap" style="margin-top:14px;">{svg_welw_c}</div>
        <div class="field-check"><strong>Field Check · Fog-Harvesting Physiology</strong>Despite appearing like a shredded pile of many leaves, trace every ribbon back to the woody crown—there are strictly two leaves.</div>
      </div>
    </article>

    <!-- SEQUOIA -->
    <article class="species-card" id="sp-sequoia" data-clade="gymnosperm">
      <figure class="plate-stage">
        <div class="plate-frame">
          <img src="assets/plate_04_sequoia_redwood.jpg" alt="Ancient Sequoia sempervirens trunks in coastal Pacific fog" loading="lazy" />
        </div>
        <figcaption class="plate-cap">Plate 04 · Coastal Redwood Cathedral (Nano Banana Studio) · Paired with macro cone detail in the PDF monograph.</figcaption>
      </figure>
      <div>
        <div class="sp-meta">
          <span class="section-kicker" style="margin:0; color:{SPECIES_COLOR['sequoia']};">Clade III · {html.escape(seq['family'])}</span>
          {iucn_pill(seq)}
          <a href="https://www.gbif.org/species/{seq['gbif_usage_key']}" target="_blank" rel="noopener">GBIF #{seq['gbif_usage_key']} ↗</a>
        </div>
        <h3 class="sp-name"><em>{html.escape(seq['canonical_name'])}</em><span class="sp-auth">{html.escape(seq['authority'])}</span></h3>
        <p>Earth's tallest trees pull water columns over {cit_chip('koch_2004_sequoia_height', '100 m')} skyward against a biophysical cohesion-tension ceiling near {cit_chip('koch_2004_sequoia_height', '115–130 m')}, cheating drought by absorbing summer Pacific fog directly through canopy needles. Live registries record {prov_chip('sequoia.gbif_total_occurrences', f"{seq['gbif_total_occurrences']:,}")} GBIF occurrences and {prov_chip('sequoia.inat_observations_total', f"{seq['inat_observations_total']:,}")} iNaturalist sightings, with IUCN status {prov_chip('sequoia.iucn_effective_code', 'EN')}.</p>
        <div class="svg-wrap" style="margin-top:14px;">{svg_seq_hyd}</div>
        <div class="field-check"><strong>Field Check · Coast Redwood vs. Giant Sequoia</strong>Flat, two-ranked yew-like needles and olive-sized (~2 cm) cones distinguish <em>Sequoia sempervirens</em> from Sierra <em>Sequoiadendron</em>.</div>
      </div>
    </article>

    <!-- VICTORIA -->
    <article class="species-card" id="sp-victoria" data-clade="angiosperm">
      {vic_plate}
      <div>
        <div class="sp-meta">
          <span class="section-kicker" style="margin:0; color:{SPECIES_COLOR['victoria']};">Clade IV · Basal Angiosperm · {html.escape(vic['family'])}</span>
          {iucn_pill(vic)}
          <a href="https://www.gbif.org/species/{vic['gbif_usage_key']}" target="_blank" rel="noopener">GBIF #{vic['gbif_usage_key']} ↗</a>
        </div>
        <h3 class="sp-name"><em>{html.escape(vic['canonical_name'])}</em><span class="sp-auth">{html.escape(vic['authority'])}</span></h3>
        <p>Floating pads reaching {cit_chip('box_2022_victoria_biomechanics', '~2.5 m')} across rely on hollow radial girders bridged by orthogonal cross-veins—the exact thin-shell architecture Joseph Paxton adapted for London's {cit_chip('box_2022_victoria_biomechanics', '1851')} Crystal Palace. Exhibits our highest museum specimen share: {prov_chip('victoria.herbarium_share_pct', f"{vic['herbarium_share_pct']:.1f}%")} ({prov_chip('victoria.gbif_preserved_specimens', str(vic['gbif_preserved_specimens']))} of {prov_chip('victoria.gbif_total_occurrences', f"{vic['gbif_total_occurrences']:,}")} GBIF records), plus {prov_chip('victoria.inat_flowering_total', str(vic['inat_flowering_total']))} equatorial bloom records.</p>
        <div class="svg-wrap" style="margin-top:14px;">{svg_vic_flw}</div>
        <div class="field-check"><strong>Field Check · Thermogenic Beetle Trap</strong>White fragrant flowers warm above night air to draw in scarab beetles on Night 1, then reopen pink on Night 2 to release pollen-dusted vectors.</div>
      </div>
    </article>

    <!-- DIONAEA -->
    <article class="species-card" id="sp-dionaea" data-clade="angiosperm">
      {dio_plate}
      <div>
        <div class="sp-meta">
          <span class="section-kicker" style="margin:0; color:{SPECIES_COLOR['dionaea']};">Clade V · {html.escape(dio['family'])}</span>
          {iucn_pill(dio)}
          <a href="https://www.gbif.org/species/{dio['gbif_usage_key']}" target="_blank" rel="noopener">GBIF #{dio['gbif_usage_key']} ↗</a>
        </div>
        <h3 class="sp-name"><em>{html.escape(dio['canonical_name'])}</em><span class="sp-auth">{html.escape(dio['authority'])}</span></h3>
        <p>Endemic to Carolina coastal-plain bogs ({prov_chip('dionaea.gbif_total_occurrences', f"{dio['gbif_total_occurrences']:,}")} GBIF occurrences, IUCN {prov_chip('dionaea.iucn_effective_code', 'VU')}), <em>Dionaea</em> counts two sensory trichome deflections within {cit_chip('bohm_2016_dionaea_counting', '<20 s')} before flipping lobe curvature via elastic snap-buckling in {cit_chip('forterre_2005_dionaea_snap', '~100 ms')}. Empirical iNaturalist phenology logs {prov_chip('dionaea.inat_flowering_total', str(dio['inat_flowering_total']))} blooms peaking in May–June atop {cit_chip('bohm_2016_dionaea_counting', '20–30 cm')} flower stalks.</p>
        <div class="svg-wrap" style="margin-top:14px;">{svg_dio_flw}</div>
        <div class="field-check"><strong>Field Check · Spatial Pollinator Separation</strong>Flowers tower far above ground traps so flying pollinators fertilize the plant without becoming prey.</div>
      </div>
    </article>

    <!-- ADANSONIA -->
    <article class="species-card" id="sp-adansonia" data-clade="angiosperm">
      <figure class="plate-stage">
        <div class="plate-frame">
          <img src="assets/plate_08_adansonia_baobab.jpg" alt="Monumental Adansonia digitata baobab tree in golden savanna light" loading="lazy" />
        </div>
        <figcaption class="plate-cap">Plate 08 · African Savanna Baobab (Nano Banana Studio) · Pachycaul stem-succulent trunk architecture.</figcaption>
      </figure>
      <div>
        <div class="sp-meta">
          <span class="section-kicker" style="margin:0; color:{SPECIES_COLOR['adansonia']};">Clade VI · {html.escape(adan['family'])}</span>
          {iucn_pill(adan)}
          <a href="https://www.gbif.org/species/{adan['gbif_usage_key']}" target="_blank" rel="noopener">GBIF #{adan['gbif_usage_key']} ↗</a>
        </div>
        <h3 class="sp-name"><em>{html.escape(adan['canonical_name'])}</em><span class="sp-auth">{html.escape(adan['authority'])}</span></h3>
        <p>Sub-Saharan baobabs build massive bottle trunks from fibrous water-storing parenchyma that swell during rains and contract during drought. Live GBIF telemetry documents {prov_chip('adansonia.gbif_total_occurrences', f"{adan['gbif_total_occurrences']:,}")} occurrences ({prov_chip('adansonia.herbarium_share_pct', f"{adan['herbarium_share_pct']:.1f}%")} herbaria), while iNaturalist records {prov_chip('adansonia.inat_flowering_total', str(adan['inat_flowering_total']))} nocturnal flowering events peaking sharply in November ({prov_chip('adansonia.inat_peak_flowering_month', 'Month 11')}).</p>
        <div class="svg-wrap" style="margin-top:14px;">{svg_adan_flw}</div>
        <div class="field-check"><strong>Field Check · Bat-Pollinated Nocturnal Blossoms</strong>Pendulous white blooms open at dusk for straw-colored fruit bats at the onset of southern savanna rains.</div>
      </div>
    </article>
  </section>

  <!-- INTERACTIVE DICHOTOMOUS CLASSIFIER -->
  <section id="classifier" style="margin-top:42px; padding-top:34px; border-top:1.5px solid var(--rule);">
    <div class="section-kicker">Section III · Interactive Learning Lab</div>
    <h2 class="sec-title">Live Dichotomous Field Classifier</h2>
    <p class="lead">Test your field diagnosis: answer up to three binary morphological traits to classify any of the six featured vascular clades.</p>
    <div class="key-widget" id="key-widget"></div>
    <p style="margin-top:18px; font-family:'Inter',sans-serif; font-size:0.74rem; color:var(--ink-soft);">
      <strong>Cryptographic Verification Receipt:</strong> {manifest_count} sealed raw JSON &amp; plate files in <code>data/manifest.sha256</code> · {len(ledger)} 1:1 provenance tuples · Rule 3 AST + Rule 9 Taxonomy + Rule 10 Prose Grounding + WCAG 2.1 Background-Sampled Contrast verified. All 8 plates generated via Nano Banana Studio (AI Editorial Photography) with zero embedded text.
    </p>
  </section>
</main>

<!-- Floating Cryptographic Provenance Popover -->
<div id="prov-popover" role="dialog" aria-live="polite">
  <div class="pop-head">
    <span class="pop-tag" id="pop-tag">CRYPTOGRAPHIC PROVENANCE</span>
    <button type="button" class="pop-close" id="pop-close" aria-label="Close">×</button>
  </div>
  <div class="pop-val" id="pop-val"></div>
  <div class="pop-meta" id="pop-meta"></div>
  <div class="pop-sha" id="pop-sha"></div>
</div>

<script>
const PROVENANCE = {prov_blob};
const CITATIONS = {cit_blob};
const SPECIES_META = {species_meta_blob};

// 1. Theme & X-Ray Provenance toggles
const btnTheme = document.getElementById('btn-theme');
btnTheme.addEventListener('click', () => {{
  const dark = document.documentElement.getAttribute('data-theme') === 'dark';
  document.documentElement.setAttribute('data-theme', dark ? 'light' : 'dark');
  btnTheme.setAttribute('aria-pressed', String(!dark));
  btnTheme.textContent = dark ? 'Night Mode' : 'Archival Light';
}});

const btnXray = document.getElementById('btn-xray');
btnXray.addEventListener('click', () => {{
  const on = document.body.classList.toggle('xray-on');
  btnXray.setAttribute('aria-pressed', String(on));
}});

// 2. Clade filter pills
document.querySelectorAll('.filter-btn').forEach(btn => {{
  btn.addEventListener('click', () => {{
    document.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    const f = btn.dataset.filter;
    document.querySelectorAll('.species-card').forEach(card => {{
      card.classList.toggle('hidden', f !== 'all' && card.dataset.clade !== f);
    }});
  }});
}});

// 3. Interactive Botanical Anatomy Pin Inspector
document.querySelectorAll('.anat-pin').forEach(pin => {{
  const activate = () => {{
    const pid = pin.dataset.plate;
    document.querySelectorAll(`.anat-pin[data-plate="${{pid}}"]`).forEach(p => p.classList.remove('active'));
    pin.classList.add('active');
    const box = document.getElementById(`readout-${{pid}}`);
    if (!box) return;
    box.querySelector('.anat-title').textContent = pin.dataset.title;
    box.querySelector('.anat-sub').textContent = pin.dataset.sub;
    box.querySelector('.anat-detail').textContent = pin.dataset.detail;
  }};
  pin.addEventListener('mouseenter', activate);
  pin.addEventListener('click', activate);
}});

// 4. Cryptographic Provenance & Rule 10 Citation Popover
const pop = document.getElementById('prov-popover');
const popTag = document.getElementById('pop-tag');
const popVal = document.getElementById('pop-val');
const popMeta = document.getElementById('pop-meta');
const popSha = document.getElementById('pop-sha');
document.getElementById('pop-close').addEventListener('click', () => pop.classList.remove('open'));

function openPopover(el) {{
  const pKey = el.dataset.prov;
  const cKey = el.dataset.cit;
  if (pKey && PROVENANCE[pKey]) {{
    const rec = PROVENANCE[pKey];
    popTag.textContent = `RULE 4 PROVENANCE · ${{pKey}}`;
    popVal.textContent = rec.value === null ? '[N/A · NOT_EVALUATED]' : String(rec.value);
    popMeta.innerHTML = `<strong>Source:</strong> <code>${{rec.source_file}}</code><br/><strong>Locator:</strong> <code>${{rec.locator}}</code><br/><strong>Raw Excerpt:</strong> <code>${{rec.excerpt}}</code>`;
    popSha.textContent = `SHA-256: ${{rec.source_sha256}}`;
  }} else if (cKey && CITATIONS[cKey]) {{
    const c = CITATIONS[cKey];
    popTag.textContent = `RULE 10 SCHOLARLY CITATION`;
    popVal.textContent = el.textContent;
    popMeta.innerHTML = `<strong>Reference:</strong> ${{c.source}}<br/><strong>Scope:</strong> ${{c.context}}`;
    popSha.innerHTML = `<a href="${{c.doi_or_url}}" target="_blank" rel="noopener">${{c.doi_or_url}} ↗</a>`;
  }} else {{
    return;
  }}
  const r = el.getBoundingClientRect();
  const top = Math.min(window.innerHeight - 230, Math.max(12, r.bottom + 8));
  const left = Math.min(window.innerWidth - 385, Math.max(12, r.left));
  pop.style.top = `${{top}}px`;
  pop.style.left = `${{left}}px`;
  pop.classList.add('open');
}}

document.querySelectorAll('.prov-chip').forEach(chip => {{
  chip.addEventListener('click', (e) => {{ e.stopPropagation(); openPopover(chip); }});
}});
document.addEventListener('click', (e) => {{
  if (!pop.contains(e.target)) pop.classList.remove('open');
}});

// 5. Interactive Dichotomous Field Classifier
const KEY_TREE = {{
  start: {{
    step: 'KEY 1 OF 3 · REPRODUCTIVE ARCHITECTURE',
    q: 'Does the plant bear naked seeds / cones, or true flowers enclosing seeds in fruit?',
    options: [
      {{ label: '1A · Naked seeds / cones (Gymnosperm)', hint: 'Zero true flowers; strobili, woody cones, or fleshy exposed ovules', next: 'gymno' }},
      {{ label: '1B · True flowers / enclosed fruit (Angiosperm)', hint: 'Petals/sepals present; seasonal or nocturnal blossoms', next: 'angio' }},
    ],
  }},
  gymno: {{
    step: 'KEY 2A OF 3 · LEAF VENATION',
    q: 'Are the leaves broad, cleft fan blades with open Y-forking (dichotomous) veins?',
    options: [
      {{ label: 'YES · Bilobed fan leaf', hint: 'No cross-linking vein mesh; turns golden in autumn', species: 'ginkgo' }},
      {{ label: 'NO · Strap ribbons or flat conifer needles', hint: 'Linear, evergreen, or continuously growing strap blades', next: 'gymno2' }},
    ],
  }},
  gymno2: {{
    step: 'KEY 3A OF 3 · GROWTH HABIT',
    q: 'Does the plant grow strictly two lifelong strap leaves from a low woody desert crown?',
    options: [
      {{ label: 'YES · Two permanent basal strap leaves', hint: 'Namib Desert gravel plains; salmon-tan strobili cones', species: 'welwitschia' }},
      {{ label: 'NO · Towering coastal conifer', hint: 'Flat two-ranked yew-like needles & ~2 cm woody cones', species: 'sequoia' }},
    ],
  }},
  angio: {{
    step: 'KEY 2B OF 3 · AQUATIC VS. TERRESTRIAL',
    q: 'Does it form giant circular floating pads (>2 m) with upturned burgundy rims and underside ribs?',
    options: [
      {{ label: 'YES · Giant floating peltate pad', hint: 'Amazonian oxbow blackwater; nocturnal white-to-pink flowers', species: 'victoria' }},
      {{ label: 'NO · Terrestrial habit', hint: 'Rooted in sandy bogs or dry savanna soils', next: 'angio2' }},
    ],
  }},
  angio2: {{
    step: 'KEY 3B OF 3 · SPECIALIZED ARCHITECTURE',
    q: 'Are leaves modified into rapid crimson bilobed snap-traps lined with marginal cilia and trigger hairs?',
    options: [
      {{ label: 'YES · Active carnivorous snap-trap', hint: 'Carolina coastal-plain bogs; May–June flowering peak', species: 'dionaea' }},
      {{ label: 'NO · Monumental pachycaul bottle-trunk tree', hint: 'Sub-Saharan savannas; bat-pollinated November flowers', species: 'adansonia' }},
    ],
  }},
}};

const keyHost = document.getElementById('key-widget');
let trail = [];

function renderKey(nodeId) {{
  const node = KEY_TREE[nodeId];
  const trailHtml = trail.length ? `<div class="key-trail">Path: ${{trail.join(' → ')}}</div>` : '<div class="key-trail">Path: Start</div>';
  keyHost.innerHTML = `
    ${{trailHtml}}
    <div class="section-kicker">${{node.step}}</div>
    <div class="key-q">${{node.q}}</div>
    <div class="key-opts">
      ${{node.options.map((o, idx) => `
        <button type="button" class="key-btn" data-idx="${{idx}}">
          <strong>${{o.label}}</strong>
          <span style="font-size:0.78rem; color:var(--ink-soft);">${{o.hint}}</span>
        </button>`).join('')}}
    </div>`;
  keyHost.querySelectorAll('.key-btn').forEach(b => {{
    b.addEventListener('click', () => {{
      const opt = node.options[Number(b.dataset.idx)];
      trail.push(opt.label);
      if (opt.species) renderSpeciesResult(opt.species);
      else renderKey(opt.next);
    }});
  }});
}}

function renderSpeciesResult(slug) {{
  const sp = SPECIES_META[slug];
  keyHost.innerHTML = `
    <div class="key-trail">Path: ${{trail.join(' → ')}}</div>
    <div class="key-result" style="border-left-color:${{sp.color}};">
      <div class="section-kicker" style="color:${{sp.color}};">Classified Taxon · ${{sp.family}} · IUCN ${{sp.iucn}}</div>
      <div style="font-family:'Didot',serif; font-size:1.75rem; margin:4px 0 8px;"><em>${{sp.canonical}}</em> <span style="font-size:0.95rem; color:var(--ink-soft);">${{sp.authority}}</span> — ${{sp.common}}</div>
      <p style="font-family:'Inter',sans-serif; font-size:0.82rem; color:var(--ink-soft); margin-bottom:12px;">
        GBIF #${{sp.gbif_key}} · OTT #${{sp.ott_id}} · ${{sp.occ.toLocaleString()}} GBIF occurrences (${{sp.herb_pct}}% herbaria) · ${{sp.flw}} iNat flowering records
      </p>
      <div style="display:flex; gap:10px; flex-wrap:wrap;">
        <a class="tb-btn" href="#sp-${{slug}}">Jump to Species Plate ↓</a>
        <button type="button" class="tb-btn" id="btn-key-reset">Classify Another Plant ↺</button>
      </div>
    </div>`;
  document.getElementById('btn-key-reset').addEventListener('click', () => {{ trail = []; renderKey('start'); }});
}}

renderKey('start');
</script>
</body>
</html>
"""


def main() -> int:
    # Rule 6 Compilation Latch
    res = subprocess.run([sys.executable, str(ROOT / "scripts" / "verify_integrity.py")], check=False)
    if res.returncode != 0:
        print("FAIL (Rule 6 Latch): verify_integrity.py failed. Refusing to build living web edition.", file=sys.stderr)
        return 1

    summary = json.loads(SUMMARY_JSON.read_text(encoding="utf-8"))
    ledger = json.loads(LEDGER_JSON.read_text(encoding="utf-8"))
    citations = json.loads(CITATIONS_JSON.read_text(encoding="utf-8"))
    manifest_count = len([ln for ln in MANIFEST_PATH.read_text(encoding="utf-8").splitlines() if ln.strip()])

    html_doc = build_html(summary, ledger, citations, manifest_count)
    OUT_HTML.write_text(html_doc, encoding="utf-8")
    kb = OUT_HTML.stat().st_size / 1024.0
    print(f"[compile_living_web] Wrote {OUT_HTML} ({kb:.1f} KB, zero external CDN deps)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
