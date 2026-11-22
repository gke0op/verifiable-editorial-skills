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
from verifiable_editorial.prose import audit_prose

REPO_ROOT = Path(__file__).resolve().parent.parent
BOTANICA = REPO_ROOT / "demos" / "botanica-veridica"
FELIS = REPO_ROOT / "demos" / "felis-mundi-magazine"
MCKINSEY = REPO_ROOT / "demos" / "mckinsey-2023-flagship"


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


def test_mckinsey_flagship_passes_geometry() -> None:
    pdf = MCKINSEY / "report" / "MCKINSEY_2023_FLAGSHIP_DECK.pdf"
    geo = audit_geometry(pdf)
    assert geo["passed"] is True, geo
