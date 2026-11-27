"""Adversarial Sabotage & Regression Test Suite for verifiable-editorial.

Proves every single anti-cheat & visual-QA gate ACTUALLY REJECTS deliberate sabotage (exit != 0 / passed == False)
AND cleanly passes on our verified production PDFs. Zero weakened tests, zero mocks of the gates themselves.
"""

from __future__ import annotations

import hashlib
import io
import json
import shutil
import subprocess
import sys
from pathlib import Path
from PIL import Image
from reportlab.lib.colors import HexColor
from reportlab.pdfgen import canvas
import pytest

from verifiable_editorial.contrast import audit_contrast
from verifiable_editorial.coverage import audit_coverage
from verifiable_editorial.geometry import audit_geometry
from verifiable_editorial.links import audit_links
from verifiable_editorial.prepress import audit_prepress
from verifiable_editorial.prose import audit_prose

REPO_ROOT = Path(__file__).resolve().parent.parent
BOTANICA = REPO_ROOT / "demos" / "botanica-veridica"
FELIS = REPO_ROOT / "demos" / "felis-mundi-magazine"
CONSULTING_FLAGSHIP = REPO_ROOT / "demos" / "consulting-flagship"
CARBON = REPO_ROOT / "demos" / "global-carbon-telemetry"
TYPST_DEMO = REPO_ROOT / "demos" / "typst-carbon-monograph"


def _make_sample_jpg(path: Path, size: tuple[int, int] = (400, 300), color=(40, 120, 80)) -> Path:
    Image.new("RGB", size, color).save(path, format="JPEG")
    return path


# ==============================================================================
# 1. ADVERSARIAL SABOTAGE TESTS — EVERY GATE MUST CATCH AND REJECT DELIBERATE CHEATS
# ==============================================================================


def test_sabotage_wcag_rejects_low_contrast_dark_text(tmp_path: Path) -> None:
    """Sabotage B: Low-contrast slate text (#505862 on #051C2C, ~2.1:1) MUST fail WCAG AA."""
    pdf = tmp_path / "bad_contrast.pdf"
    c = canvas.Canvas(str(pdf), pagesize=(612, 792))
    c.setFillColor(HexColor("#051C2C"))
    c.rect(0, 0, 612, 792, fill=1, stroke=0)
    c.setFillColor(HexColor("#505862"))
    c.setFont("Helvetica", 11)
    c.drawString(50, 700, "Unreadable dark-mode executive body text")
    c.showPage()
    c.save()

    res = audit_contrast(pdf)
    assert res["passed"] is False
    assert res["total_violations"] >= 1
    assert res["worst_contrast_ratio"] < 3.0


def test_sabotage_geometry_rejects_overlapping_text_spans(tmp_path: Path) -> None:
    """Sabotage C: Two colliding text labels at the same coordinates MUST fail geometry collision gate."""
    pdf = tmp_path / "collision.pdf"
    c = canvas.Canvas(str(pdf), pagesize=(612, 792))
    c.setFillColor(HexColor("#111111"))
    c.setFont("Helvetica-Bold", 11)
    c.drawString(80, 600, "ANGIOSPERMS TRUE FLOWERS")
    c.setFont("Helvetica", 11)
    c.drawString(95, 599, "Malvaceae OTT 659136 191 flw")
    c.showPage()
    c.save()

    res = audit_geometry(pdf)
    assert res["passed"] is False
    assert res["total_collisions"] >= 1


def test_sabotage_geometry_rejects_clip_path_sliced_text(tmp_path: Path) -> None:
    """Sabotage D: Text sliced mid-word by a PDF clip path (W n) MUST be caught by clip-path detector."""
    pdf = tmp_path / "clipped.pdf"
    c = canvas.Canvas(str(pdf), pagesize=(612, 792))
    c.saveState()
    p = c.beginPath()
    p.rect(50, 680, 80, 30)
    c.clipPath(p, stroke=0, fill=0)
    c.setFillColor(HexColor("#111111"))
    c.setFont("Helvetica", 12)
    c.drawString(54, 690, "Thick low-resin bark insulates cambium from fire")
    c.restoreState()
    c.showPage()
    c.save()

    res = audit_geometry(pdf)
    assert res["passed"] is False
    assert res["total_clipped"] >= 1


def test_sabotage_geometry_rejects_orphan_headline_wrap(tmp_path: Path) -> None:
    """Sabotage E: Wide display headline wrapping a single short orphan word onto line 2 MUST be flagged."""
    pdf = tmp_path / "orphan.pdf"
    c = canvas.Canvas(str(pdf), pagesize=(612, 792))
    c.setFillColor(HexColor("#111111"))
    c.setFont("Helvetica-Bold", 24)
    c.drawString(40, 720, "Global Occurrence, Herbaria & Bloom")
    c.drawString(40, 692, "Calendars")
    c.showPage()
    c.save()

    res = audit_geometry(pdf)
    assert res["passed"] is False
    assert res["total_headline_orphans"] >= 1


def test_sabotage_coverage_rejects_clip_inflated_sub50_photo(tmp_path: Path) -> None:
    """Sabotage F: An image whose unclipped rect spans 75% of the page, but PDF clip path cuts it to 40%,
    MUST fail the >=50% dual-key visible coverage gate (defeating raw get_image_rects inflation)."""
    img = _make_sample_jpg(tmp_path / "plate.jpg", size=(600, 600), color=(30, 110, 75))
    pdf = tmp_path / "sub50_clipped.pdf"
    c = canvas.Canvas(str(pdf), pagesize=(612, 792))
    c.saveState()
    # Clip strictly to top 40% (316.8pt of 792pt) while drawing unclipped image across 75% (594pt)
    p = c.beginPath()
    p.rect(0, 792 - 316.8, 612, 316.8)
    c.clipPath(p, stroke=0, fill=0)
    c.drawImage(str(img), 0, 792 - 594, width=612, height=594)
    c.restoreState()
    c.showPage()
    c.save()

    res = audit_coverage(pdf, min_pct=50.0, min_bleed_edges=2)
    assert res["passed"] is False
    assert 38.0 <= res["min_visible_pct"] <= 42.0


def test_sabotage_rule10_rejects_hallucinated_prose_number(tmp_path: Path) -> None:
    """Sabotage A: A fabricated statistic ('14,999') typed directly in PDF prose MUST fail Rule 10."""
    ledger = tmp_path / "provenance_ledger.json"
    ledger.write_text(
        json.dumps({"ginkgo.gbif_total_occurrences": {"value": 64896, "source_file": "raw.json"}}),
        encoding="utf-8",
    )
    pdf = tmp_path / "hallucinated_prose.pdf"
    c = canvas.Canvas(str(pdf), pagesize=(612, 792))
    c.setFont("Helvetica", 11)
    c.drawString(50, 700, "Verified count is 64,896 but a hallucinated claim says 14,999 specimens.")
    c.showPage()
    c.save()

    res = audit_prose(pdf, ledger_path=ledger)
    assert res["passed"] is False
    tokens = {u["token"] for u in res["ungrounded"]}
    assert "14,999" in tokens
    assert "64,896" not in tokens


def test_sabotage_rule3_ast_rejects_hardcoded_literal_assert(tmp_path: Path) -> None:
    """Sabotage H: A verifier script containing a hardcoded numeric literal assert MUST fail Rule 3 AST check."""
    sys.path.insert(0, str(BOTANICA / "scripts"))
    import verify_integrity as vi

    bad_script = tmp_path / "cheating_verifier.py"
    bad_script.write_text("def check(x):\n    assert x == 64896\n", encoding="utf-8")
    errs = vi.ast_anti_circular_check([bad_script])
    assert len(errs) >= 1
    assert "64896" in errs[0]


def test_sabotage_sha256_latch_rejects_tampered_raw_byte(tmp_path: Path) -> None:
    """Sabotage G: Flipping a single byte in a raw data file MUST trip verify_integrity.py (exit 1)."""
    # Copy minimal Botanica data tree into tmp_path and tamper 1 byte in raw JSON
    demo_copy = tmp_path / "botanica_tamper"
    shutil.copytree(BOTANICA / "data", demo_copy / "data")
    shutil.copytree(BOTANICA / "scripts", demo_copy / "scripts")
    shutil.copytree(BOTANICA / "report" / "assets", demo_copy / "report" / "assets")

    target = demo_copy / "data" / "raw" / "gbif_total_ginkgo.json"
    orig = target.read_text(encoding="utf-8")
    target.write_text(orig + " ", encoding="utf-8")  # 1-byte tamper!

    proc = subprocess.run([sys.executable, str(demo_copy / "scripts" / "verify_integrity.py")], capture_output=True, text=True)
    assert proc.returncode != 0
    assert "SHA-256 mismatch" in proc.stderr


# ==============================================================================
# 2. CLEAN PASS REGRESSION TESTS — ALL SHIPPED DEMOS MUST PASS EVERY GATE
# ==============================================================================


def test_botanica_monograph_passes_all_four_gates() -> None:
    pdf = BOTANICA / "report" / "BOTANICA_VERIDICA_MONOGRAPH.pdf"
    cr = audit_contrast(pdf)
    geo = audit_geometry(pdf)
    cov = audit_coverage(pdf, min_pct=50.0, pages={1, 4, 5, 6, 7, 8, 9})
    pr = audit_prose(
        pdf,
        ledger_path=BOTANICA / "data" / "provenance_ledger.json",
        summary_path=BOTANICA / "data" / "summary_metrics.json",
        citations_path=BOTANICA / "data" / "background_citations.json",
        manifest_path=BOTANICA / "data" / "manifest.sha256",
    )

    assert cr["passed"] is True, cr
    assert geo["passed"] is True, geo
    assert cov["passed"] is True, cov
    assert pr["passed"] is True, pr


def test_felis_mundi_passes_geometry_and_coverage() -> None:
    pdf = FELIS / "report" / "FELIS_MUNDI_MAGAZINE.pdf"
    geo = audit_geometry(pdf)
    cov = audit_coverage(pdf, min_pct=50.0)
    assert geo["passed"] is True, geo
    assert cov["passed"] is True, cov
    assert cov["min_visible_pct"] >= 60.0


def test_sabotage_rule10_rejects_sign_flip(tmp_path: Path) -> None:
    """Sabotage I: Flipping a negative ledger metric (-45.0%) to +45.0% in PDF prose MUST fail Rule 10."""
    ledger = tmp_path / "provenance_ledger.json"
    ledger.write_text(
        json.dumps([{"metric_id": "chn_ci_change", "value": -45.01, "unit": "%"}]),
        encoding="utf-8",
    )
    pdf = tmp_path / "sign_flip.pdf"
    c = canvas.Canvas(str(pdf), pagesize=(612, 792))
    c.setFont("Helvetica", 11)
    c.drawString(50, 700, "Carbon intensity moved -45.0% in reality, not +45.0%.")
    c.showPage()
    c.save()

    res = audit_prose(pdf, ledger_path=ledger)
    assert res["passed"] is False
    tokens = {u["token"] for u in res["ungrounded"]}
    assert "+45.0%" in tokens
    assert "-45.0%" not in tokens


def test_sabotage_prepress_rejects_low_dpi_image(tmp_path: Path) -> None:
    """Sabotage J: Upscaling a 100x100px raster across 400x400pt (~18 effective DPI) MUST fail prepress."""
    img = _make_sample_jpg(tmp_path / "tiny.jpg", size=(100, 100), color=(20, 80, 120))
    pdf = tmp_path / "low_dpi.pdf"
    c = canvas.Canvas(str(pdf), pagesize=(612, 792))
    c.drawImage(str(img), 50, 200, width=400, height=400)
    c.showPage()
    c.save()

    res = audit_prepress(pdf, min_dpi=300.0, run_verapdf=False)
    assert res["passed"] is False
    assert res["min_effective_dpi"] is not None and res["min_effective_dpi"] < 25.0
    assert any("effective DPI" in f for f in res["failures"])


def test_sabotage_prepress_rejects_missing_bleed_unembedded_font_and_untagged_ua(tmp_path: Path) -> None:
    """Sabotage K: Standard untagged ReportLab PDF using Base-14 Helvetica MUST fail bleed, font, and PDF/UA checks."""
    pdf = tmp_path / "untagged_base14.pdf"
    c = canvas.Canvas(str(pdf), pagesize=(612, 792))
    c.setFont("Helvetica", 12)
    c.drawString(50, 700, "Untagged PDF with unembedded Base-14 Helvetica and zero bleed box.")
    c.showPage()
    c.save()

    res = audit_prepress(pdf, require_bleed=True, require_ua=True, run_verapdf=False)
    assert res["passed"] is False
    assert any("Unembedded font" in f for f in res["failures"])
    assert any("bleed box" in f for f in res["failures"])
    assert any("PDF/UA structure" in f for f in res["failures"])


def test_consulting_flagship_passes_geometry() -> None:
    pdf = CONSULTING_FLAGSHIP / "report" / "CONSULTING_FLAGSHIP_DECK.pdf"
    geo = audit_geometry(pdf)
    assert geo["passed"] is True, geo


def test_typst_monograph_passes_all_five_gates_and_verapdf() -> None:
    """Production regression: Rust-native Typst PDF/UA-1 monograph MUST pass all 5 gates (including veraPDF when installed)."""
    pdf = TYPST_DEMO / "report" / "TYPST_CARBON_MONOGRAPH_UA1.pdf"
    cr = audit_contrast(pdf)
    geo = audit_geometry(pdf)
    pr = audit_prose(
        pdf,
        ledger_path=CARBON / "data" / "provenance_ledger.json",
        summary_path=CARBON / "data" / "summary_metrics.json",
        citations_path=TYPST_DEMO / "data" / "background_citations.json",
        manifest_path=CARBON / "data" / "manifest.sha256",
    )
    pp = audit_prepress(pdf, min_dpi=300.0, require_ua=True, run_verapdf=True)

    assert cr["passed"] is True, cr
    assert geo["passed"] is True, geo
    assert pr["passed"] is True, pr
    assert pp["passed"] is True, pp
    assert pp["unembedded_fonts"] == []
    assert pp["pdf_ua_structure"]["structural_pass"] is True
    if shutil.which("verapdf"):
        assert pp["verapdf_ua1"] is not None
        assert pp["verapdf_ua1"]["compliant"] is True
        assert pp["verapdf_ua1"]["failed_rules"] == 0


# ==============================================================================
# 3. SOVEREIGN ZIG 0.17.0 HARNESS + p2zig KERNEL PARITY + PDF INJECTION CLOSED LOOP
# ==============================================================================

ZIG_VEDIT = REPO_ROOT / "zig" / "zig-out" / "bin" / "vedit"


def test_p2zig_kernels_parity_and_tir_provenance() -> None:
    """Verify all 10 editorial kernels exist in Python source AND transpiled Zig-TIR module with exact math."""
    from verifiable_editorial import kernels_p2zig_src as kpy

    zig_src = (REPO_ROOT / "zig" / "src" / "kernels_p2zig.zig").read_text(encoding="utf-8")
    assert "// uroboros:zig-tir" in zig_src
    for fn_name in [
        "rel_channel_x1000000",
        "wcag_contrast_x100",
        "wcag_passes_aa",
        "cmyk_gcr_tac_x10",
        "span_collision_kind",
        "is_orphan_headline",
        "rule10_is_grounded_x100",
        "effective_dpi_x10",
        "detect_grid_columns",
        "classify_page_archetype",
        "bleed_edge_count",
        "coverage_passes",
    ]:
        assert f'pub fn @"{fn_name}"' in zig_src

    assert kpy.wcag_contrast_x100(0, 0, 0, 255, 255, 255) == 2100
    assert kpy.wcag_passes_aa(kpy.wcag_contrast_x100(0x50, 0x58, 0x62, 0x05, 0x1C, 0x2C), 110, False) is False
    assert kpy.cmyk_gcr_tac_x10(0, 0, 0) == 2600
    assert kpy.effective_dpi_x10(100, 100, 4000, 4000) == 180
    assert kpy.rule10_is_grounded_x100(-4500, [-4501]) is True
    assert kpy.rule10_is_grounded_x100(4500, [-4501]) is False
    assert kpy.bleed_edge_count(300, 300, 300, 0, 612, 792) == 3
    assert kpy.coverage_passes(60000, 100000, 500, 3, 2) is True
    assert kpy.coverage_passes(40000, 100000, 500, 3, 2) is False


@pytest.mark.skipif(not ZIG_VEDIT.exists() or not shutil.which("mutool"), reason="Zig vedit binary or mutool unavailable")
def test_zig_harness_rejects_all_sabotage_gates(tmp_path: Path) -> None:
    """Compiled bare-metal Zig 0.17.0 `vedit` binary MUST independently reject every sabotage vector."""
    # 1. Low-contrast sabotage
    bad_cr = tmp_path / "z_bad_cr.pdf"
    c = canvas.Canvas(str(bad_cr), pagesize=(612, 792))
    c.setFillColor(HexColor("#051C2C"))
    c.rect(0, 0, 612, 792, fill=1, stroke=0)
    c.setFillColor(HexColor("#505862"))
    c.setFont("Helvetica", 11)
    c.drawString(50, 700, "Unreadable low contrast text")
    c.showPage()
    c.save()
    r1 = subprocess.run([str(ZIG_VEDIT), "contrast", str(bad_cr)], capture_output=True, text=True)
    assert r1.returncode != 0, r1.stdout

    # 2. Collision sabotage
    bad_geo = tmp_path / "z_bad_geo.pdf"
    c = canvas.Canvas(str(bad_geo), pagesize=(612, 792))
    c.setFont("Helvetica-Bold", 11)
    c.drawString(80, 600, "ANGIOSPERMS TRUE FLOWERS")
    c.setFont("Helvetica", 11)
    c.drawString(95, 599, "Malvaceae OTT 659136")
    c.showPage()
    c.save()
    r2 = subprocess.run([str(ZIG_VEDIT), "geometry", str(bad_geo)], capture_output=True, text=True)
    assert r2.returncode != 0, r2.stdout

    # 3. Sign-flip Rule 10 sabotage
    ledger = tmp_path / "ledger.json"
    ledger.write_text(json.dumps([{"metric_id": "ci_chg", "value": -45.01}]), encoding="utf-8")
    bad_sign = tmp_path / "z_bad_sign.pdf"
    c = canvas.Canvas(str(bad_sign), pagesize=(612, 792))
    c.setFont("Helvetica", 11)
    c.drawString(50, 700, "Flipped sign +45.0% instead of -45.0%.")
    c.showPage()
    c.save()
    r3 = subprocess.run([str(ZIG_VEDIT), "prose", str(bad_sign), "--ledger", str(ledger)], capture_output=True, text=True)
    assert r3.returncode != 0, r3.stdout
    assert "+45.0%" in r3.stdout

    # 4. Prepress low-DPI + unembedded Base-14 + untagged PDF/UA sabotage
    img = _make_sample_jpg(tmp_path / "tiny.jpg", size=(100, 100), color=(20, 80, 120))
    bad_pp = tmp_path / "z_bad_pp.pdf"
    c = canvas.Canvas(str(bad_pp), pagesize=(612, 792))
    c.drawImage(str(img), 50, 200, width=400, height=400)
    c.setFont("Helvetica", 12)
    c.drawString(50, 700, "Untagged Base-14 PDF")
    c.showPage()
    c.save()
    r4 = subprocess.run(
        [str(ZIG_VEDIT), "prepress", str(bad_pp), "--min-dpi", "300", "--require-bleed", "--require-ua", "--no-verapdf"],
        capture_output=True,
        text=True,
    )
    assert r4.returncode != 0, r4.stdout

    # 5. Pure-Zig W/W* clip-path character-slicing sabotage
    bad_clip = tmp_path / "z_bad_clip.pdf"
    c = canvas.Canvas(str(bad_clip), pagesize=(612, 792))
    c.saveState()
    p = c.beginPath()
    p.rect(50, 680, 80, 30)
    c.clipPath(p, stroke=0, fill=0)
    c.setFillColor(HexColor("#111111"))
    c.setFont("Helvetica", 12)
    c.drawString(54, 690, "Thick low-resin bark insulates cambium from fire")
    c.restoreState()
    c.showPage()
    c.save()
    r5 = subprocess.run([str(ZIG_VEDIT), "geometry", str(bad_clip)], capture_output=True, text=True)
    assert r5.returncode != 0, r5.stdout
    assert "clip_path_sliced_text" in r5.stdout

    # 6. Pure-Zig dual-key clip-inflated sub-50% photo coverage sabotage
    plate_img = _make_sample_jpg(tmp_path / "z_plate.jpg", size=(600, 600), color=(30, 110, 75))
    bad_cov = tmp_path / "z_bad_cov.pdf"
    c = canvas.Canvas(str(bad_cov), pagesize=(612, 792))
    c.saveState()
    p = c.beginPath()
    p.rect(0, 792 - 316.8, 612, 316.8)
    c.clipPath(p, stroke=0, fill=0)
    c.drawImage(str(plate_img), 0, 792 - 594, width=612, height=594)
    c.restoreState()
    c.showPage()
    c.save()
    r6 = subprocess.run([str(ZIG_VEDIT), "coverage", str(bad_cov), "--min-pct", "50", "--min-bleed", "2"], capture_output=True, text=True)
    assert r6.returncode != 0, r6.stdout
    assert "min_visible=40." in r6.stdout


@pytest.mark.skipif(not ZIG_VEDIT.exists() or not shutil.which("mutool"), reason="Zig vedit binary or mutool unavailable")
def test_zig_harness_full_sovereign_parity_on_botanica_and_felis() -> None:
    """Sovereign Zig `vedit` MUST independently pass contrast, geometry (incl. clip check) & dual-key coverage on Botanica and Felis Mundi."""
    bot_pdf = BOTANICA / "report" / "BOTANICA_VERIDICA_MONOGRAPH.pdf"
    fel_pdf = FELIS / "report" / "FELIS_MUNDI_MAGAZINE.pdf"

    for cmd in [
        [str(ZIG_VEDIT), "contrast", str(bot_pdf)],
        [str(ZIG_VEDIT), "geometry", str(bot_pdf)],
        [
            str(ZIG_VEDIT),
            "prose",
            str(bot_pdf),
            "--ledger",
            str(BOTANICA / "data" / "provenance_ledger.json"),
            "--summary",
            str(BOTANICA / "data" / "summary_metrics.json"),
            "--citations",
            str(BOTANICA / "data" / "background_citations.json"),
            "--manifest",
            str(BOTANICA / "data" / "manifest.sha256"),
        ],
        [str(ZIG_VEDIT), "coverage", str(bot_pdf), "--min-pct", "50", "--pages", "1,4-9"],
        [str(ZIG_VEDIT), "geometry", str(fel_pdf)],
        [str(ZIG_VEDIT), "coverage", str(fel_pdf), "--min-pct", "50"],
    ]:
        res = subprocess.run(cmd, capture_output=True, text=True)
        assert res.returncode == 0, f"CMD={cmd}\nSTDOUT:\n{res.stdout}\nSTDERR:\n{res.stderr}"

    # Verify exact Zig vs Python Rule 10 prose parity on Botanica, PRL, CAIE, and Exomundus
    for demo_pdf, demo_data in [
        (bot_pdf, BOTANICA / "data"),
        (REPO_ROOT / "demos/prl-yang-mills-chaos/report/PRL_YANG_MILLS_CHAOS_UA1.pdf", REPO_ROOT / "demos/prl-yang-mills-chaos/data"),
        (REPO_ROOT / "demos/caie-flowshop-journal/report/CAIE_FLOWSHOP_MANUSCRIPT_UA1.pdf", REPO_ROOT / "demos/caie-flowshop-journal/data"),
        (REPO_ROOT / "demos/exomundus-nasa-telemetry/report/EXOMUNDUS_NASA_TELEMETRY_UA1.pdf", REPO_ROOT / "demos/exomundus-nasa-telemetry/data"),
    ]:
        py_res = audit_prose(
            demo_pdf,
            demo_data / "provenance_ledger.json",
            demo_data / "summary_metrics.json",
            demo_data / "background_citations.json",
            demo_data / "manifest.sha256",
        )
        assert py_res["passed"], f"Python Rule 10 failed on {demo_pdf.name}: {py_res['ungrounded']}"
        zig_res = subprocess.run(
            [
                str(ZIG_VEDIT),
                "prose",
                str(demo_pdf),
                "--ledger",
                str(demo_data / "provenance_ledger.json"),
                "--summary",
                str(demo_data / "summary_metrics.json"),
                "--citations",
                str(demo_data / "background_citations.json"),
                "--manifest",
                str(demo_data / "manifest.sha256"),
            ],
            capture_output=True,
            text=True,
        )
        assert zig_res.returncode == 0, f"Zig Rule 10 failed on {demo_pdf.name}:\n{zig_res.stdout}"


@pytest.mark.skipif(not ZIG_VEDIT.exists() or not shutil.which("mutool"), reason="Zig vedit binary or mutool unavailable")
def test_zig_geometry_math_fonts_no_false_collisions() -> None:
    """NewCMMath quads span the font's full ascent/descent (~6.6x size on mutool 1.23); Zig must clamp them like Python's accurate bboxes."""
    repo = Path(__file__).resolve().parent.parent
    for pdf in [
        repo / "demos/exomundus-nasa-telemetry/report/EXOMUNDUS_NASA_TELEMETRY_UA1.pdf",
        repo / "demos/prl-yang-mills-chaos/report/PRL_YANG_MILLS_CHAOS_UA1.pdf",
        repo / "demos/typst-carbon-monograph/report/TYPST_CARBON_MONOGRAPH_UA1.pdf",
    ]:
        res = subprocess.run([str(ZIG_VEDIT), "geometry", str(pdf)], capture_output=True, text=True)
        assert res.returncode == 0 and "collisions=0" in res.stdout, res.stdout


@pytest.mark.skipif(
    not ZIG_VEDIT.exists() or not shutil.which("mutool") or not shutil.which("typst"),
    reason="Zig vedit, mutool, or typst unavailable",
)
def test_zig_harness_inject_init_and_zero_python_closed_loop(tmp_path: Path) -> None:
    """Closed-loop Pillar #5+#6 proof: Zig dissects a PDF -> registers archetype -> scaffolds project -> compiles Typst UA-1 -> passes Zig 5-gate court + veraPDF."""
    arch_dir = tmp_path / "archetypes"
    sample_pdf = TYPST_DEMO / "report" / "TYPST_CARBON_MONOGRAPH_UA1.pdf"

    inj = subprocess.run(
        [str(ZIG_VEDIT), "inject", str(sample_pdf), "--name", "loop-test", "--out-dir", str(arch_dir)],
        capture_output=True,
        text=True,
    )
    assert inj.returncode == 0, inj.stderr
    assert (arch_dir / "loop-test" / "blueprint.json").exists()
    assert (arch_dir / "loop-test" / "skeleton.typ").exists()
    assert (arch_dir / "loop-test" / "AGENT_CARD.md").exists()
    assert (arch_dir / "registry.json").exists()

    proj = tmp_path / "synth_pub"
    ini = subprocess.run(
        [str(ZIG_VEDIT), "init", str(proj), "--archetype", "loop-test", "--dir", str(arch_dir), "--title", "Loop Proof"],
        capture_output=True,
        text=True,
    )
    assert ini.returncode == 0, ini.stderr

    env = dict(**__import__("os").environ, VEDIT_BIN=str(ZIG_VEDIT))
    bld = subprocess.run(["bash", str(proj / "build.sh")], capture_output=True, text=True, env=env)
    assert bld.returncode == 0, f"STDOUT:\n{bld.stdout}\nSTDERR:\n{bld.stderr}"
    assert "[vedit:latch] PASS" in bld.stdout
    assert "[vedit:wcag_contrast] PASS" in bld.stdout
    assert "[vedit:geometry]      PASS" in bld.stdout
    assert "[vedit:prepress]      PASS" in bld.stdout
    if shutil.which("verapdf"):
        assert "verapdf_pass=106, verapdf_fail=0" in bld.stdout


@pytest.mark.skipif(not ZIG_VEDIT.exists() or not shutil.which("mutool"), reason="Zig vedit binary or mutool unavailable")
def test_exomundus_zero_python_monograph_passes_zig_latch_and_all_five_gates() -> None:
    """Zero-Python NASA Exoplanet monograph MUST pass Zig SHA-256 latch and all 5 Zig court gates + veraPDF."""
    exo = REPO_ROOT / "demos" / "exomundus-nasa-telemetry"
    pdf = exo / "report" / "EXOMUNDUS_NASA_TELEMETRY_UA1.pdf"

    lt = subprocess.run([str(ZIG_VEDIT), "latch", str(exo)], capture_output=True, text=True)
    assert lt.returncode == 0, lt.stdout + lt.stderr
    assert "manifest=5/5 SHA-256 verified" in lt.stdout

    aud = subprocess.run(
        [
            str(ZIG_VEDIT),
            "audit-all",
            str(pdf),
            "--ledger",
            str(exo / "data" / "provenance_ledger.json"),
            "--summary",
            str(exo / "data" / "summary_metrics.json"),
            "--citations",
            str(exo / "data" / "background_citations.json"),
            "--manifest",
            str(exo / "data" / "manifest.sha256"),
            "--require-ua",
        ],
        capture_output=True,
        text=True,
    )
    assert aud.returncode == 0, aud.stdout + aud.stderr
    assert "[vedit:rule10_prose] PASS" in aud.stdout
    assert "[vedit:wcag_contrast] PASS" in aud.stdout
    assert "[vedit:geometry]      PASS" in aud.stdout
    assert "[vedit:prepress]      PASS" in aud.stdout
    if shutil.which("verapdf"):
        assert "verapdf_pass=106, verapdf_fail=0" in aud.stdout


@pytest.mark.skipif(not ZIG_VEDIT.exists() or not shutil.which("mutool"), reason="Zig vedit binary or mutool unavailable")
def test_caie_flowshop_journal_passes_zig_latch_and_all_five_gates() -> None:
    """Zero-Python Elsevier CAIE two-column OR-Library paper MUST pass Zig SHA-256 latch, 5-gate court, veraPDF & A4 init loop."""
    caie = REPO_ROOT / "demos" / "caie-flowshop-journal"
    pdf = caie / "report" / "CAIE_FLOWSHOP_MANUSCRIPT_UA1.pdf"

    lt = subprocess.run([str(ZIG_VEDIT), "latch", str(caie)], capture_output=True, text=True)
    assert lt.returncode == 0, lt.stdout + lt.stderr
    assert "manifest=1/1 SHA-256 verified" in lt.stdout

    aud = subprocess.run(
        [
            str(ZIG_VEDIT),
            "audit-all",
            str(pdf),
            "--ledger",
            str(caie / "data" / "provenance_ledger.json"),
            "--summary",
            str(caie / "data" / "summary_metrics.json"),
            "--citations",
            str(caie / "data" / "background_citations.json"),
            "--manifest",
            str(caie / "data" / "manifest.sha256"),
            "--require-ua",
        ],
        capture_output=True,
        text=True,
    )
    assert aud.returncode == 0, aud.stdout + aud.stderr
    assert "[vedit:rule10_prose] PASS" in aud.stdout
    assert "[vedit:wcag_contrast] PASS" in aud.stdout
    assert "[vedit:geometry]      PASS" in aud.stdout
    assert "[vedit:prepress]      PASS" in aud.stdout
    if shutil.which("verapdf"):
        assert "verapdf_pass=106, verapdf_fail=0" in aud.stdout


@pytest.mark.skipif(not ZIG_VEDIT.exists() or not shutil.which("mutool"), reason="Zig vedit binary or mutool unavailable")
def test_prl_yang_mills_chaos_passes_zig_latch_and_all_five_gates() -> None:
    """Zero-Python APS Physical Review Letters (REVTeX 4.2) Yang-Mills chaos Letter MUST pass Zig SHA-256 latch, 5-gate court & veraPDF."""
    prl = REPO_ROOT / "demos" / "prl-yang-mills-chaos"
    pdf = prl / "report" / "PRL_YANG_MILLS_CHAOS_UA1.pdf"

    lt = subprocess.run([str(ZIG_VEDIT), "latch", str(prl)], capture_output=True, text=True)
    assert lt.returncode == 0, lt.stdout + lt.stderr
    assert "manifest=1/1 SHA-256 verified" in lt.stdout

    aud = subprocess.run(
        [
            str(ZIG_VEDIT),
            "audit-all",
            str(pdf),
            "--ledger",
            str(prl / "data" / "provenance_ledger.json"),
            "--summary",
            str(prl / "data" / "summary_metrics.json"),
            "--citations",
            str(prl / "data" / "background_citations.json"),
            "--manifest",
            str(prl / "data" / "manifest.sha256"),
            "--require-ua",
        ],
        capture_output=True,
        text=True,
    )
    assert aud.returncode == 0, aud.stdout + aud.stderr
    assert "[vedit:rule10_prose] PASS" in aud.stdout
    assert "[vedit:wcag_contrast] PASS" in aud.stdout
    assert "[vedit:geometry]      PASS" in aud.stdout
    assert "[vedit:prepress]      PASS" in aud.stdout
    if shutil.which("verapdf"):
        assert "verapdf_pass=106, verapdf_fail=0" in aud.stdout


# ==============================================================================
# 4. ROUND-2 ADVERSARIAL REGRESSION TESTS (ISSUE #2 ESCAPES — BOTH ZIG & PYTHON)
# ==============================================================================


def _find_unicode_ttf(required_codepoints: tuple[int, ...] = (0x2077, 0x2076, 0xFF19)) -> Path | None:
    import glob
    from reportlab.pdfbase.ttfonts import TTFontFile

    candidates = (
        glob.glob("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")
        + glob.glob("/usr/share/fonts/truetype/noto/NotoSans*.ttf")
        + glob.glob("/System/Library/Fonts/Supplemental/Arial Unicode.ttf")
        + glob.glob(str(Path.home() / ".cache/verifiable-editorial/fonts/**/*.ttf"), recursive=True)
    )
    for c in candidates:
        p = Path(c)
        if not p.exists():
            continue
        try:
            tf = TTFontFile(str(p), validate=0)
            if all(cp in tf.charToGlyph for cp in required_codepoints):
                return p
        except Exception:
            continue
    return None


def test_sabotage_rule10_rejects_precision_tolerance_and_blanket_structural_escapes(tmp_path: Path) -> None:
    """Issue #2 Escape 1: Half-ULP precision & contextual structurals MUST reject fabricated p-values, 52%/300, and 0.57/0.5262."""

    def _run_case(name: str, ledger_vals: list[float], text: str, expect_pass: bool) -> None:
        led = tmp_path / f"{name}.json"
        led.write_text(
            json.dumps({f"k{i}": {"value": v, "source_file": "raw.json"} for i, v in enumerate(ledger_vals)}),
            encoding="utf-8",
        )
        pdf = tmp_path / f"{name}.pdf"
        c = canvas.Canvas(str(pdf), pagesize=(612, 792))
        c.setFont("Helvetica", 11)
        c.drawString(50, 700, text)
        c.showPage()
        c.save()

        py = audit_prose(pdf, ledger_path=led)
        assert py["passed"] is expect_pass, f"Python mismatch on {name}: {py}"
        if ZIG_VEDIT.exists() and shutil.which("mutool"):
            z = subprocess.run([str(ZIG_VEDIT), "prose", str(pdf), "--ledger", str(led)], capture_output=True, text=True)
            assert (z.returncode == 0) is expect_pass, f"Zig mismatch on {name}:\n{z.stdout}"

    # Sabotage vectors (MUST FAIL)
    _run_case("p0049", [64896], "Significant at p = 0.049.", False)
    _run_case("p0001", [64896], "Fabricated p = 0.001 effect.", False)
    _run_case("surge_52", [64896], "A 52% surge in sales.", False)
    _run_case("specimens_300", [64896], "Only 300 specimens exist.", False)
    _run_case("specimens_5", [64896], "Only 5 specimens exist.", False)
    _run_case("ratio_057", [0.5255], "Ratio is 0.57.", False)
    _run_case("ratio_05262", [0.5255], "Ratio is 0.5262.", False)
    _run_case("ratio_05260", [0.5255, 64896], "Ratio is 0.5260 across 64,896 records.", False)
    _run_case("decimal_comma", [64.896], "The share was 64,897 percent.", False)
    _run_case("eight_digit_int", [45], "The count was 12345678 units.", False)

    # Controls (MUST PASS)
    _run_case("exact_and_round", [0.5255, 64896], "Ratio is 0.5255 (2dp: 0.53, 3dp: 0.526) across 64,896 records.", True)
    _run_case("contextual_ordinals", [64896], "See Figure 2 and Table 3 on Page 1 (Rule 10) for 64,896 rows.", True)


def test_sabotage_rule10_rejects_forged_exponents_and_fullwidth_digits(tmp_path: Path) -> None:
    """Issue #2 Escape 2 (+ Minor P9): Caret, layout-raised, and Unicode exponents + fullwidth digits MUST be audited."""
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont

    def _check_pdf(pdf: Path, ledger_vals: list[float], expect_pass: bool) -> None:
        led = tmp_path / f"{pdf.stem}.json"
        led.write_text(
            json.dumps({f"k{i}": {"value": v, "source_file": "raw.json"} for i, v in enumerate(ledger_vals)}),
            encoding="utf-8",
        )
        py = audit_prose(pdf, ledger_path=led)
        assert py["passed"] is expect_pass, f"Python mismatch on {pdf.name}: {py}"
        if ZIG_VEDIT.exists() and shutil.which("mutool"):
            z = subprocess.run([str(ZIG_VEDIT), "prose", str(pdf), "--ledger", str(led)], capture_output=True, text=True)
            assert (z.returncode == 0) is expect_pass, f"Zig mismatch on {pdf.name}:\n{z.stdout}"

    # 1. Caret 10^7 vs ledger 1e6 -> FAIL; 10^6 -> PASS
    for name, txt, exp_pass in [
        ("caret_10_7", "We sampled 10^7 points.", False),
        ("caret_10_6_ok", "We sampled 10^6 points.", True),
        ("sci_97e9_forged", "Flux is 9.7*10^9 erg.", False),
        ("sci_97e6_ok", "Flux is 9.7*10^6 erg.", True),
    ]:
        pdf = tmp_path / f"{name}.pdf"
        c = canvas.Canvas(str(pdf), pagesize=(612, 792))
        c.setFont("Helvetica", 11)
        c.drawString(50, 700, txt)
        c.showPage()
        c.save()
        _check_pdf(pdf, [9700000.0] if "97e6" in name else ([9.7] if "97e9" in name else [1000000.0]), exp_pass)

    # 2. Layout-positioned raised superscript 10^7 (as Typst/LaTeX emit) vs ledger 1e6 -> FAIL
    sup_pdf = tmp_path / "layout_sup_10_7.pdf"
    c = canvas.Canvas(str(sup_pdf), pagesize=(612, 792))
    c.setFont("Helvetica", 11)
    c.drawString(50, 700, "We sampled 10")
    c.setFont("Helvetica", 7)
    c.drawString(121, 704, "7")
    c.setFont("Helvetica", 11)
    c.drawString(127, 700, "points.")
    c.showPage()
    c.save()
    _check_pdf(sup_pdf, [1000000.0], False)

    # 3. Unicode superscript 10⁷ (when a TTF covering U+2076/U+2077 is present)
    sup_ttf = _find_unicode_ttf((0x2076, 0x2077))
    if sup_ttf is not None:
        fname = "TestUniSupR2"
        if fname not in pdfmetrics.getRegisteredFontNames():
            pdfmetrics.registerFont(TTFont(fname, str(sup_ttf)))
        for name, vals, txt, exp_pass in [
            ("uni_sup_10_7", [1000000.0], "We sampled 10\u2077 points.", False),
            ("uni_sup_10_6_ok", [1000000.0], "We sampled 10\u2076 points.", True),
        ]:
            pdf = tmp_path / f"{name}.pdf"
            c = canvas.Canvas(str(pdf), pagesize=(612, 792))
            c.setFont(fname, 11)
            c.drawString(50, 700, txt)
            c.showPage()
            c.save()
            _check_pdf(pdf, vals, exp_pass)

    # 4. Fullwidth digits ９９ (end-to-end PDF when a CJK/Unicode TTF is present, plus direct cleaner assertion)
    from verifiable_editorial.prose import _clean_page_text

    assert "99" in _clean_page_text("The count was \uff19\uff19 units.", 612.0, 792.0)
    fw_ttf = _find_unicode_ttf((0xFF19,))
    if fw_ttf is not None:
        fname_fw = "TestUniFwR2"
        if fname_fw not in pdfmetrics.getRegisteredFontNames():
            pdfmetrics.registerFont(TTFont(fname_fw, str(fw_ttf)))
        pdf = tmp_path / "uni_fullwidth_99.pdf"
        c = canvas.Canvas(str(pdf), pagesize=(612, 792))
        c.setFont(fname_fw, 11)
        c.drawString(50, 700, "The count was \uff19\uff19 units.")
        c.showPage()
        c.save()
        _check_pdf(pdf, [45.0], False)


def test_sabotage_geometry_rejects_horizontal_and_bottom_half_glyph_slicing(tmp_path: Path) -> None:
    """Issue #2 Escape 3: Clipping the top half (or bottom half) of glyphs MUST fail BOTH Python & Zig geometry gates."""
    line = "Thick low-resin bark insulates cambium from fire"

    def _draw_text(c: canvas.Canvas) -> None:
        c.setFillColor(HexColor("#111111"))
        c.setFont("Helvetica", 12)
        c.drawString(54, 690, line)

    def _clip_rect(c: canvas.Canvas, x: float, y: float, w: float, h: float) -> None:
        p = c.beginPath()
        p.rect(x, y, w, h)
        c.clipPath(p, stroke=0, fill=0)

    cases = [
        ("F_top_half_slice", lambda c: (c.saveState(), _clip_rect(c, 40, 680, 400, 14), _draw_text(c), c.restoreState()), True),
        ("F2_bottom_half_slice", lambda c: (c.saveState(), _clip_rect(c, 40, 694, 400, 20), _draw_text(c), c.restoreState()), True),
        (
            "A_clip_in_form_xobject",
            lambda c: (
                c.beginForm("F1"),
                c.saveState(),
                _clip_rect(c, 50, 680, 80, 30),
                _draw_text(c),
                c.restoreState(),
                c.endForm(),
                c.doForm("F1"),
            ),
            True,
        ),
        (
            "C_nested_inner_slices",
            lambda c: (
                c.saveState(),
                _clip_rect(c, 0, 0, 612, 792),
                c.saveState(),
                _clip_rect(c, 50, 680, 80, 30),
                _draw_text(c),
                c.restoreState(),
                c.restoreState(),
            ),
            True,
        ),
        ("D_clip_popped_control", lambda c: (c.saveState(), _clip_rect(c, 50, 680, 80, 30), c.restoreState(), _draw_text(c)), False),
        ("E_generous_clip_control", lambda c: (c.saveState(), _clip_rect(c, 40, 670, 400, 50), _draw_text(c), c.restoreState()), False),
    ]

    for name, draw_fn, expect_fail in cases:
        pdf = tmp_path / f"{name}.pdf"
        c = canvas.Canvas(str(pdf), pagesize=(612, 792))
        draw_fn(c)
        c.showPage()
        c.save()

        py = audit_geometry(pdf)
        assert (not py["passed"]) is expect_fail, f"Python geometry mismatch on {name}: {py}"
        if expect_fail:
            assert py["total_clipped"] >= 1, py
        if ZIG_VEDIT.exists() and shutil.which("mutool"):
            z = subprocess.run([str(ZIG_VEDIT), "geometry", str(pdf)], capture_output=True, text=True)
            assert (z.returncode != 0) is expect_fail, f"Zig geometry mismatch on {name}:\n{z.stdout}"
            if expect_fail:
                assert "clip_path_sliced_text" in z.stdout, z.stdout


# ==============================================================================
# 5. RULE 11 — CLICKABLE RESOURCE LINK & LIVE ANTI-HALLUCINATION COURT TESTS
# ==============================================================================


def test_sabotage_rule11_rejects_unlinked_text_placeholders_hidden_rects_and_missing_citations(tmp_path: Path) -> None:
    """Rule 11A/B: Plain-text dead URLs/DOIs, 0-link PDFs, placeholders, 0x0 rects & unlinked citations MUST fail both courts."""

    def _check_both(pdf: Path, *, citations: Path | None = None, expect_pass: bool) -> dict:
        py = audit_links(pdf, citations_path=citations, live=False)
        assert py["passed"] is expect_pass, f"Python Rule 11 mismatch on {pdf.name}: {py}"
        if ZIG_VEDIT.exists() and shutil.which("mutool"):
            cmd = [str(ZIG_VEDIT), "links", str(pdf), "--offline"]
            if citations is not None:
                cmd += ["--citations", str(citations)]
            z = subprocess.run(cmd, capture_output=True, text=True)
            assert (z.returncode == 0) is expect_pass, f"Zig Rule 11 mismatch on {pdf.name}:\n{z.stdout}\n{z.stderr}"
        return py

    # 1. Zero clickable links -> FAIL
    p_none = tmp_path / "no_links.pdf"
    c = canvas.Canvas(str(p_none), pagesize=(612, 792))
    c.setFont("Helvetica", 11)
    c.drawString(50, 700, "A report with zero clickable links.")
    c.showPage()
    c.save()
    res = _check_both(p_none, expect_pass=False)
    assert any(f["kind"] == "INSUFFICIENT_CLICKABLE_LINKS" for f in res["failures"])

    # 2. Dead plain-text URL + DOI without PDF /URI annotation -> FAIL
    p_dead = tmp_path / "unlinked_text.pdf"
    c = canvas.Canvas(str(p_dead), pagesize=(612, 792))
    c.setFont("Helvetica", 11)
    c.drawString(50, 720, "Verified source: https://typst.app/docs/reference/pdf/")
    c.linkURL("https://typst.app/docs/reference/pdf/", (50, 716, 300, 732), relative=0)
    c.drawString(50, 690, "Unlinked dead text: doi:10.1038/nature02417")
    c.showPage()
    c.save()
    res = _check_both(p_dead, expect_pass=False)
    assert any(f["kind"] == "UNLINKED_TEXT_RESOURCE" for f in res["failures"])

    # 3. Placeholder domain (example.com) + degenerate 0x0 link rect -> FAIL
    p_ph = tmp_path / "placeholder_and_tiny.pdf"
    c = canvas.Canvas(str(p_ph), pagesize=(612, 792))
    c.setFont("Helvetica", 11)
    c.drawString(50, 700, "Fake placeholder source")
    c.linkURL("https://example.com/fabricated-study", (50, 696, 180, 712), relative=0)
    c.linkURL("https://typst.app/docs/", (50, 680, 50.5, 680.5), relative=0)
    c.showPage()
    c.save()
    res = _check_both(p_ph, expect_pass=False)
    kinds = {f["kind"] for f in res["failures"]}
    assert any("PLACEHOLDER" in k for k in kinds)
    assert "DEGENERATE_OR_HIDDEN_LINK_RECT" in kinds

    # 4. Citation declared in background_citations.json missing clickable link in PDF -> FAIL
    cits = tmp_path / "background_citations.json"
    cits.write_text(
        json.dumps(
            {
                "citations": [
                    {"id": "c1", "values": [100], "source": "Typst Docs", "doi_or_url": "https://typst.app/docs/reference/pdf/"},
                    {"id": "c2", "values": [115], "source": "Koch 2004", "doi_or_url": "https://doi.org/10.1038/nature02417"},
                ]
            }
        ),
        encoding="utf-8",
    )
    p_miss = tmp_path / "missing_declared_link.pdf"
    c = canvas.Canvas(str(p_miss), pagesize=(612, 792))
    c.setFont("Helvetica", 11)
    c.drawString(50, 700, "Only c1 linked here")
    c.linkURL("https://typst.app/docs/reference/pdf/", (50, 696, 180, 712), relative=0)
    c.showPage()
    c.save()
    res = _check_both(p_miss, citations=cits, expect_pass=False)
    assert any(f["kind"] == "DECLARED_RESOURCE_NOT_CLICKABLE" for f in res["failures"])

    # 5. Control: both declared citations linked with visible rects -> PASS
    p_ok = tmp_path / "all_linked_ok.pdf"
    c = canvas.Canvas(str(p_ok), pagesize=(612, 792))
    c.setFont("Helvetica", 11)
    c.drawString(50, 720, "Typst Spec")
    c.linkURL("https://typst.app/docs/reference/pdf/", (50, 716, 140, 732), relative=0)
    c.drawString(50, 690, "Koch et al. (2004) doi:10.1038/nature02417")
    c.linkURL("https://doi.org/10.1038/nature02417", (50, 686, 280, 702), relative=0)
    c.showPage()
    c.save()
    _check_both(p_ok, citations=cits, expect_pass=True)


def test_sabotage_rule11_live_http_rejects_404_soft404_bot_challenge_and_403_on_both_courts(tmp_path: Path) -> None:
    """Rule 11C: Live HTTP court MUST pass real 200 pages and reject 404, HTTP-200 Soft-404, HTTP-200 Client Challenge & 403."""
    from http.server import BaseHTTPRequestHandler, HTTPServer
    import threading

    routes: dict[str, tuple[int, str]] = {
        "/real-report": (200, "<html><head><title>Verified Climate Telemetry 2026</title></head><body><h1>Mauna Loa</h1></body></html>"),
        "/hallucinated-404": (404, "<html><head><title>Not Found</title></head><body>Missing</body></html>"),
        "/soft-404": (200, "<html><head><title>404 - Page Not Found | Journal</title></head><body><h1>Article not found</h1></body></html>"),
        "/bot-challenge": (200, "<html><head><title>Client Challenge</title></head><body>Enable JavaScript</body></html>"),
        "/forbidden-403": (403, "<html><head><title>Just a moment...</title></head><body>Forbidden</body></html>"),
    }

    class _Handler(BaseHTTPRequestHandler):
        def do_GET(self) -> None:  # noqa: N802
            code, body = routes.get(self.path, (404, "<html><title>404 Not Found</title></html>"))
            payload = body.encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def log_message(self, fmt: str, *args: object) -> None:
            return

    srv = HTTPServer(("127.0.0.1", 0), _Handler)
    port = srv.server_address[1]
    th = threading.Thread(target=srv.serve_forever, daemon=True)
    th.start()
    try:
        cases = [
            ("real_200_ok", "/real-report", True),
            ("dead_404", "/hallucinated-404", False),
            ("soft_404_200", "/soft-404", False),
            ("bot_challenge_200", "/bot-challenge", False),
            ("waf_403", "/forbidden-403", False),
        ]
        for name, route, expect_pass in cases:
            url = f"http://127.0.0.1:{port}{route}"
            pdf = tmp_path / f"live_{name}.pdf"
            c = canvas.Canvas(str(pdf), pagesize=(612, 792))
            c.setFont("Helvetica", 11)
            c.drawString(50, 700, f"Source link: {url}")
            c.linkURL(url, (50, 696, 320, 712), relative=0)
            c.showPage()
            c.save()

            py = audit_links(pdf, live=True, timeout=5.0, allow_localhost=True)
            assert py["passed"] is expect_pass, f"Python live Rule 11 mismatch on {name}: {py}"
            if ZIG_VEDIT.exists() and shutil.which("mutool"):
                z = subprocess.run(
                    [str(ZIG_VEDIT), "links", str(pdf), "--timeout", "5", "--allow-localhost"],
                    capture_output=True,
                    text=True,
                )
                assert (z.returncode == 0) is expect_pass, f"Zig live Rule 11 mismatch on {name}:\n{z.stdout}\n{z.stderr}"
    finally:
        srv.shutdown()
        srv.server_close()


def test_published_flagship_demos_pass_rule11_clickable_link_integrity_offline() -> None:
    """All clickable-reference flagship PDFs MUST pass Rule 11 structural/clickable parity on BOTH Python and Zig."""
    for pdf in [
        BOTANICA / "report" / "BOTANICA_VERIDICA_MONOGRAPH.pdf",
        REPO_ROOT / "demos/caie-flowshop-journal/report/CAIE_FLOWSHOP_MANUSCRIPT_UA1.pdf",
        REPO_ROOT / "demos/cosmos-mobile-primer/report/COSMOS_MOBILE_PRIMER_UA1.pdf",
        REPO_ROOT / "demos/exomundus-nasa-telemetry/report/EXOMUNDUS_NASA_TELEMETRY_UA1.pdf",
        REPO_ROOT / "demos/prl-yang-mills-chaos/report/PRL_YANG_MILLS_CHAOS_UA1.pdf",
        TYPST_DEMO / "report" / "TYPST_CARBON_MONOGRAPH_UA1.pdf",
    ]:
        py = audit_links(pdf, live=False)
        assert py["passed"] is True, f"Python Rule 11 offline failed on {pdf.name}: {py}"
        if ZIG_VEDIT.exists() and shutil.which("mutool"):
            z = subprocess.run([str(ZIG_VEDIT), "links", str(pdf), "--offline"], capture_output=True, text=True)
            assert z.returncode == 0, f"Zig Rule 11 offline failed on {pdf.name}:\n{z.stdout}\n{z.stderr}"


def test_cosmos_mobile_primer_passes_whatsapp_budget_mobile_trim_and_6_gate_parity() -> None:
    """Mobile-native 9:16 subject-understanding primer MUST fit WhatsApp size budget (<1 MB), 360x640pt trim, and pass all gates."""
    import fitz

    demo = REPO_ROOT / "demos/cosmos-mobile-primer"
    pdf = demo / "report/COSMOS_MOBILE_PRIMER_UA1.pdf"
    assert pdf.exists() and pdf.stat().st_size < 1_000_000, f"WhatsApp PDF size budget exceeded: {pdf.stat().st_size}"

    doc = fitz.open(pdf)
    assert len(doc) == 12, f"Expected 12 mobile cards, got {len(doc)}"
    for pg in doc:
        assert abs(pg.rect.width - 360.0) <= 1.0 and abs(pg.rect.height - 640.0) <= 1.0

    # Verify archetype metadata records native mobile_portrait_9x16
    bp = json.loads((REPO_ROOT / "archetypes/mobile-primer/blueprint.json").read_text(encoding="utf-8"))
    assert bp["format_class"] == "mobile_portrait_9x16"

    assert audit_contrast(pdf)["passed"] is True
    assert audit_geometry(pdf)["passed"] is True
    assert audit_prose(
        pdf,
        ledger_path=demo / "data/provenance_ledger.json",
        summary_path=demo / "data/summary_metrics.json",
        citations_path=demo / "data/background_citations.json",
        manifest_path=demo / "data/manifest.sha256",
    )["passed"] is True
    assert audit_links(
        pdf,
        citations_path=demo / "data/background_citations.json",
        ledger_path=demo / "data/provenance_ledger.json",
        live=False,
    )["passed"] is True
    assert audit_prepress(pdf, min_dpi=300.0, require_ua=True, run_verapdf=bool(shutil.which("verapdf")))["passed"] is True
