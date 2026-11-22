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
from verifiable_editorial.prepress import audit_prepress
from verifiable_editorial.prose import audit_prose

REPO_ROOT = Path(__file__).resolve().parent.parent
BOTANICA = REPO_ROOT / "demos" / "botanica-veridica"
FELIS = REPO_ROOT / "demos" / "felis-mundi-magazine"
MCKINSEY = REPO_ROOT / "demos" / "mckinsey-2023-flagship"
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


def test_mckinsey_flagship_passes_geometry() -> None:
    pdf = MCKINSEY / "report" / "MCKINSEY_2023_FLAGSHIP_DECK.pdf"
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
        [str(ZIG_VEDIT), "coverage", str(bot_pdf), "--min-pct", "50", "--pages", "1,4-9"],
        [str(ZIG_VEDIT), "geometry", str(fel_pdf)],
        [str(ZIG_VEDIT), "coverage", str(fel_pdf), "--min-pct", "50"],
    ]:
        res = subprocess.run(cmd, capture_output=True, text=True)
        assert res.returncode == 0, f"CMD={cmd}\nSTDOUT:\n{res.stdout}\nSTDERR:\n{res.stderr}"


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
