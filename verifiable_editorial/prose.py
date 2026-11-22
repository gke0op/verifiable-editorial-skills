"""Rule 10 — Post-Render PDF Prose-to-Ledger Grounding Auditor.

Extracts quantitative numeric and scientific-notation tokens directly from the FINAL compiled PDF bytes
(`fitz.open(pdf)`) and verifies that every quantitative claim in body copy, tables, and exhibits traces back to:
  (a) an exact scalar (or exact derived ratio/sum) in `provenance_ledger.json` / `summary_metrics.json`,
      matched at the token's own displayed decimal precision (half-ULP rounding, zero coarse ±0.051 catch-all),
  (b) an explicitly documented scholarly citation in `background_citations.json` (with DOI/URL), or
  (c) explicitly marked contextual structural ordinals (e.g. `Page 3`, `Figure 2`, `Table 1`, `Rule 10`,
      page-footer `p / N` matching current page & total pages, or trim spec `W × H pt`).

Closes anti-cheat loopholes including fabricated small p-values, blanket structural whitelists,
unchecked scientific-notation exponents (`10^7`, `10⁷`, `9.7×10⁹`), sign flips, and fullwidth digits (`９９`).
"""

from __future__ import annotations

import json
import math
import re
from pathlib import Path
from typing import Any
import fitz  # PyMuPDF

_SUP_MAP = str.maketrans(
    {
        "⁰": "0",
        "¹": "1",
        "²": "2",
        "³": "3",
        "⁴": "4",
        "⁵": "5",
        "⁶": "6",
        "⁷": "7",
        "⁸": "8",
        "⁹": "9",
        "⁻": "-",
        "⁺": "+",
    }
)
_FULLWIDTH_MAP = str.maketrans(
    {
        "０": "0",
        "１": "1",
        "２": "2",
        "３": "3",
        "４": "4",
        "５": "5",
        "６": "6",
        "７": "7",
        "８": "8",
        "９": "9",
        "＋": "+",
        "－": "-",
        "．": ".",
        "，": ",",
        "％": "%",
    }
)

# Match scientific notation (mantissa × 10^exp, bare 10^exp, explicit base^exp, mantissa e/E exp) or plain numbers
SCI_OR_NUM_RE = re.compile(
    r"(?<![A-Za-z0-9_#\-])"
    r"(?:"
    # Group 1..4: mantissa × 10^exp (ASCII caret with paired ()/{} or bare, OR Unicode superscript)
    r"([+\-\u2212]?)(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)\s*[×xX·*]\s*10"
    r"(?:\^\s*(?:\(\s*([+\-\u2212]?\d+)\s*\)|\{\s*([+\-\u2212]?\d+)\s*\}|([+\-\u2212]?\d+))|([⁺⁻]?[⁰¹²³⁴⁵⁶⁷⁸⁹]+))"
    r"|"
    # Group 7..11: bare 10^exp (ASCII caret with paired ()/{} or bare, OR Unicode superscript)
    r"([+\-\u2212]?)10"
    r"(?:\^\s*(?:\(\s*([+\-\u2212]?\d+)\s*\)|\{\s*([+\-\u2212]?\d+)\s*\}|([+\-\u2212]?\d+))|([⁺⁻]?[⁰¹²³⁴⁵⁶⁷⁸⁹]+))"
    r"|"
    # Group 12..16: explicit ASCII caret base^exp (e.g. 2^10)
    r"([+\-\u2212]?)(\d+(?:\.\d+)?)\^\s*(?:\(\s*([+\-\u2212]?\d+)\s*\)|\{\s*([+\-\u2212]?\d+)\s*\}|([+\-\u2212]?\d+))"
    r"|"
    # Group 17..19: standard ASCII scientific notation (e.g. 1.25e-15, 1E7)
    r"([+\-\u2212]?)(\d+(?:\.\d+)?)[eE]([+\-\u2212]?\d+)"
    r"|"
    # Group 20..22: plain signed/unsigned number with optional thousands commas, decimals, and %
    r"([+\-\u2212]?)(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)(%?)"
    r")"
    r"(?![A-Za-z0-9_])"
)

# Require at least one hex letter [a-f] so pure 8+ digit fabricated integers are never stripped as SHA hashes
HEX_HASH_RE = re.compile(r"\b(?=[0-9a-f]*[a-f])[0-9a-f]{8,64}\b")
DOI_RE = re.compile(r"(?:doi:\s*)?\b10\.\d{4,9}/\s*[-._;()/:A-Za-z0-9]+", re.IGNORECASE)

# Explicit contextual structural keywords permitting an unsigned integer ordinal directly after them
STRUCTURAL_PREFIX_RE = re.compile(
    r"(?:^|[\s(\[;:,·•/])"
    r"(?:page|pages|p\.|pp\.|fig\.|figs\.|figure|figures|table|tables|tab\.|plate|plates|"
    r"exhibit|exhibits|section|sections|sec\.|chapter|ch\.|appendix|eq\.|eqs\.|equation|equations|"
    r"rule|rules|gate|gates|slide|slides|ref\.|refs\.|vol\.|issue|no\.|pillar|§)"
    r"\s*(?:#|\(|\[)?\s*$",
    re.IGNORECASE,
)

# SI unit reciprocal/power exponents (e.g. yr⁻¹, yr −1, cm⁻³, m²)
SI_UNIT_EXP_RE = re.compile(
    r"\b(?:yr|s|m|cm|mm|km|kg|g|L|K|mol|Hz|W|J|Pa|eV|pc|AU|hr|min|day)"
    r"\s*(?:[⁺⁻][⁰¹²³⁴⁵⁶⁷⁸⁹]+|\^?[−\-]1\b)"
)
LETTER_SUP_RE = re.compile(r"(?<=[A-Za-z\u0370-\u03FF\U0001D400-\U0001D7FF])[⁺⁻]?[⁰¹²³⁴⁵⁶⁷⁸⁹]+")

SKIP_KEYS = {
    "sampled_coordinates",
    "lat",
    "lon",
    "width_pt",
    "height_pt",
    "bbox",
    "raw_newick_sha256",
    "decimal_dates",
    "average_ppm",
    "deseasonalized_ppm",
    "co2_series_2000_2024",
    "ci_series_2000_2024",
}


def _collect_numbers_recursive(obj: Any, out: set[float]) -> None:
    if isinstance(obj, bool):
        return
    if isinstance(obj, (int, float)):
        fv = float(obj)
        if math.isfinite(fv):
            out.add(fv)
        return
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k in SKIP_KEYS:
                continue
            _collect_numbers_recursive(v, out)
    elif isinstance(obj, list):
        # Also allow exact sums of pure numeric lists (e.g. 2-month flowering windows or totals)
        if obj and all(isinstance(x, (int, float)) and not isinstance(x, bool) for x in obj):
            s = float(sum(obj))
            if math.isfinite(s):
                out.add(s)
            # Pairwise adjacent sums (e.g., May+June flowering window) and their exact % of list sum
            for i in range(len(obj) - 1):
                pair = float(obj[i] + obj[i + 1])
                if math.isfinite(pair):
                    out.add(pair)
                    if s > 0:
                        out.add((pair / s) * 100.0)
        for item in obj:
            _collect_numbers_recursive(item, out)


def _derive_exact_ratios(summary: dict[str, Any], out: set[float]) -> None:
    """Register exact deterministic percentages derived from validated species/country counts."""
    for sp in summary.get("species", []):
        tot = sp.get("gbif_total_occurrences")
        if isinstance(tot, (int, float)) and tot > 0:
            for c in sp.get("top_countries", []):
                cnt = c.get("count")
                if isinstance(cnt, (int, float)):
                    out.add((cnt / tot) * 100.0)


def _load_authorized_numbers(
    ledger_path: Path | None,
    summary_path: Path | None,
    citations_path: Path | None,
    page_count: int,
) -> tuple[set[float], dict[str, Any]]:
    del page_count  # No blanket structural whitelist; pagination is checked strictly in context.
    authorized: set[float] = set()
    meta = {"ledger_values": 0, "summary_values": 0, "background_citations": 0}

    if ledger_path and ledger_path.exists():
        ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
        before = len(authorized)
        _collect_numbers_recursive(ledger, authorized)
        # Register top-level ledger record count directly (e.g. len(ledger))
        authorized.add(float(len(ledger)))
        meta["ledger_values"] = len(authorized) - before

    if summary_path and summary_path.exists():
        summary = json.loads(summary_path.read_text(encoding="utf-8"))
        before = len(authorized)
        _collect_numbers_recursive(summary, authorized)
        _derive_exact_ratios(summary, authorized)
        meta["summary_values"] = len(authorized) - before

    if citations_path and citations_path.exists():
        cits = json.loads(citations_path.read_text(encoding="utf-8"))
        entries = cits.get("citations", []) if isinstance(cits, dict) else cits
        for entry in entries:
            if not entry.get("source") or not entry.get("doi_or_url"):
                raise ValueError(f"Rule 10 citation missing source/doi_or_url: {entry}")
            vals = entry.get("values", [])
            if "value" in entry:
                vals = list(vals) + [entry["value"]]
            for v in vals:
                fv = float(v)
                if math.isfinite(fv):
                    authorized.add(fv)
        meta["background_citations"] = len(entries)

    return authorized, meta


def _is_grounded(
    val: float,
    decimals: int,
    authorized: set[float],
    *,
    sci_exp: int | None = None,
    bare_power: bool = False,
) -> bool:
    """Verify that some exact authorized value rounds to `val` at its displayed decimal precision (half-ULP)."""
    if not math.isfinite(val):
        return False
    if bare_power:
        eps = max(1e-30, abs(val) * 1e-9)
        return any(abs(a - val) <= eps for a in authorized)
    if sci_exp is not None:
        half_ulp = 0.5 * (10.0 ** (sci_exp - decimals))
        eps = max(1e-30, abs(val) * 1e-12)
        return any(abs(a - val) <= half_ulp + eps for a in authorized)
    half_ulp = 0.5 * (10.0 ** (-decimals))
    eps = max(1e-12, abs(val) * 1e-12)
    return any(abs(a - val) <= half_ulp + eps for a in authorized)


def _is_math_italic_before(s: str, pos: int) -> bool:
    if pos <= 0:
        return False
    cp = ord(s[pos - 1])
    return 0x1D400 <= cp <= 0x1D7FF


def _is_page_pagination(cleaned: str, start: int, end: int, num_val: int, page_idx: int, page_count: int) -> bool:
    """Allow explicit page-footer pagination `<page_idx> / <page_count>` or `<page_idx> of <page_count>`."""
    if num_val == page_idx:
        after = cleaned[end : min(len(cleaned), end + 20)]
        m = re.match(r"^\s*(?:/|of)\s*(\d+)(?![A-Za-z0-9_.%])", after, re.IGNORECASE)
        if m and int(m.group(1)) == page_count:
            return True
    if num_val == page_count:
        before = cleaned[max(0, start - 20) : start]
        m = re.search(r"(?<![A-Za-z0-9_.])(\d+)\s*(?:/|of)\s*$", before, re.IGNORECASE)
        if m and int(m.group(1)) == page_idx:
            return True
    return False


def _extract_page_text_with_script_breaks(page: fitz.Page) -> str:
    """Extract page text preserving scientific `10^exp` superscripts while separating footnote/script breaks.

    - Raised smaller spans containing an integer exponent directly after standalone `10` emit `^<exp>`
      so rendered `10^7` / `10^{-14}` stay auditable as true powers of 10.
    - All other >=1.5pt font-size transitions insert whitespace so `2024` + footnote `1` never fuse into `20241`.
    """
    lines_out: list[str] = []
    for block in page.get_text("dict").get("blocks", []):
        if block.get("type") != 0:
            continue
        for line in block.get("lines", []):
            parts: list[str] = []
            prev_size: float | None = None
            prev_cy: float | None = None
            for span in line.get("spans", []):
                txt = span.get("text", "")
                if not txt:
                    continue
                size = float(span.get("size", 10.0))
                bbox = span.get("bbox", (0.0, 0.0, 0.0, 0.0))
                cy = 0.5 * (float(bbox[1]) + float(bbox[3]))
                if parts and prev_size is not None:
                    is_raised_exp = (
                        size <= prev_size - 1.5
                        and prev_cy is not None
                        and cy < prev_cy - prev_size * 0.10
                        and re.match(r"^\s*[+\-\u2212]?\d+\s*$", txt) is not None
                    )
                    if is_raised_exp and re.search(r"(?:^|[^0-9])10\s*$", "".join(parts)):
                        parts.append("^" + txt.strip())
                        prev_size = size
                        prev_cy = cy
                        continue
                    if (
                        abs(size - prev_size) >= 1.5
                        and not parts[-1].endswith((" ", "\t", "\n"))
                        and not txt.startswith((" ", "\t", "\n"))
                    ):
                        parts.append(" ")
                parts.append(txt)
                prev_size = size
                prev_cy = cy
            if parts:
                lines_out.append("".join(parts))
    return "\n".join(lines_out)


def _clean_page_text(raw_text: str, page_w: float, page_h: float) -> str:
    cleaned = raw_text.replace("\u00ad", "").translate(_FULLWIDTH_MAP)
    cleaned = re.sub(r"https?://\S+", " ", cleaned)
    cleaned = DOI_RE.sub(" ", cleaned)
    cleaned = HEX_HASH_RE.sub(" ", cleaned)
    cleaned = re.sub(r"SHA-?\s*256(?::?\s+[0-9a-fA-F]{6,})?", " ", cleaned)
    cleaned = re.sub(
        r"(?:PDF/UA-\d+|ISO\s+\d+(?:-\d+)?|WCAG\s+\d+\.\d+|WeasyPrint\s+\d+\.\d+|Typst\s+\d+\.\d+(?:\.\d+)?|veraPDF\s+\d+\.\d+(?:\.\d+)?|SHA-256|term_id=\d+)",
        " ",
        cleaned,
    )
    cleaned = SI_UNIT_EXP_RE.sub(" ", cleaned)
    cleaned = LETTER_SUP_RE.sub(" ", cleaned)
    pw, ph = int(round(page_w)), int(round(page_h))
    cleaned = re.sub(rf"\b{pw}\s*[×xX]\s*{ph}\s*pt\b", " ", cleaned)
    return cleaned


def _parse_exp(ascii_exp: str | None, sup_exp: str | None) -> int | None:
    raw = ascii_exp if ascii_exp is not None else (sup_exp.translate(_SUP_MAP) if sup_exp is not None else None)
    if raw is None:
        return None
    try:
        ev = int(raw.replace("\u2212", "-"))
        return ev if -300 <= ev <= 300 else None
    except ValueError:
        return None


def audit_prose(
    pdf_path: Path | str,
    ledger_path: Path | str | None = None,
    summary_path: Path | str | None = None,
    citations_path: Path | str | None = None,
    manifest_path: Path | str | None = None,
) -> dict:
    """Rule 10: Extract every quantitative number from rendered PDF bytes and verify precision-aware ledger grounding."""
    pdf_path = Path(pdf_path)
    doc = fitz.open(pdf_path)
    page_count = len(doc)

    lp = Path(ledger_path) if ledger_path else None
    sp = Path(summary_path) if summary_path else None
    cp = Path(citations_path) if citations_path else None
    mp = Path(manifest_path) if manifest_path else None

    authorized, meta = _load_authorized_numbers(lp, sp, cp, page_count)
    if mp and mp.exists():
        m_lines = [ln for ln in mp.read_text(encoding="utf-8").splitlines() if ln.strip()]
        authorized.add(float(len(m_lines)))

    ungrounded: list[dict] = []
    total_checked = 0

    for idx, page in enumerate(doc, start=1):
        raw_text = _extract_page_text_with_script_breaks(page)
        cleaned = _clean_page_text(raw_text, page.rect.width, page.rect.height)

        for match in SCI_OR_NUM_RE.finditer(cleaned):
            tok_display = match.group(0)
            val: float
            decs = 0
            sci_exp: int | None = None
            bare_power = False

            if match.group(2) is not None:
                # mantissa × 10^exp
                sign, mant = match.group(1), match.group(2)
                e_asc = match.group(3) or match.group(4) or match.group(5)
                e_sup = match.group(6)
                ev = _parse_exp(e_asc, e_sup)
                if ev is None:
                    continue
                try:
                    mv = float(mant.replace(",", ""))
                except ValueError:
                    continue
                if sign in ("-", "\u2212"):
                    mv = -mv
                val = mv * (10.0 ** ev)
                decs = len(mant.split(".")[1]) if "." in mant else 0
                sci_exp = ev
            elif (
                match.group(8) is not None
                or match.group(9) is not None
                or match.group(10) is not None
                or match.group(11) is not None
            ):
                # bare 10^exp
                sign = match.group(7)
                e_asc = match.group(8) or match.group(9) or match.group(10)
                e_sup = match.group(11)
                ev = _parse_exp(e_asc, e_sup)
                if ev is None:
                    continue
                val = 10.0 ** ev
                if sign in ("-", "\u2212"):
                    val = -val
                sci_exp = ev
                bare_power = True
            elif match.group(13) is not None:
                # explicit base^exp
                sign, base_s = match.group(12), match.group(13)
                e_asc = match.group(14) or match.group(15) or match.group(16)
                ev = _parse_exp(e_asc, None)
                if ev is None:
                    continue
                try:
                    bv = float(base_s)
                    val = bv ** ev
                except (ValueError, OverflowError):
                    continue
                if sign in ("-", "\u2212"):
                    val = -val
                bare_power = True
            elif match.group(18) is not None:
                # ASCII mantissa[eE]exp
                sign, mant, e_asc = match.group(17), match.group(18), match.group(19)
                ev = _parse_exp(e_asc, None)
                if ev is None:
                    continue
                try:
                    mv = float(mant)
                except ValueError:
                    continue
                if sign in ("-", "\u2212"):
                    mv = -mv
                val = mv * (10.0 ** ev)
                decs = len(mant.split(".")[1]) if "." in mant else 0
                sci_exp = ev
            else:
                # Plain number
                sign = match.group(20)
                raw_num = match.group(21)
                suffix = match.group(22)
                # Unicode mathematical italic variable immediately before +/− (e.g. 𝑖−1, 𝑘−1) is binary subtraction
                if sign in ("-", "\u2212", "+") and _is_math_italic_before(cleaned, match.start()):
                    sign = ""
                    tok_display = raw_num + suffix
                else:
                    tok_display = sign + raw_num + suffix

                # Leading-zero 2-digit plate/page ordinals "01".."12" (unsigned, no %, no decimal)
                if not sign and not suffix and len(raw_num) == 2 and raw_num.startswith("0") and "." not in raw_num:
                    continue

                decs = len(raw_num.split(".")[1]) if "." in raw_num else 0
                # Contextual structural ordinals: ONLY unsigned bare integers (no %, no decimal, no comma)
                if not sign and not suffix and decs == 0 and "," not in raw_num:
                    prefix = cleaned[max(0, match.start() - 32) : match.start()]
                    if STRUCTURAL_PREFIX_RE.search(prefix):
                        continue
                    try:
                        int_val = int(raw_num)
                    except ValueError:
                        int_val = -1
                    if int_val >= 1 and _is_page_pagination(cleaned, match.start(), match.end(), int_val, idx, page_count):
                        continue

                try:
                    val = float(raw_num.replace(",", ""))
                except ValueError:
                    continue
                if sign in ("-", "\u2212"):
                    val = -val

            total_checked += 1
            if not _is_grounded(val, decs, authorized, sci_exp=sci_exp, bare_power=bare_power):
                start = max(0, match.start() - 32)
                end = min(len(cleaned), match.end() + 32)
                snippet = " ".join(cleaned[start:end].split())
                ungrounded.append(
                    {
                        "page": idx,
                        "token": tok_display,
                        "value": val,
                        "context": snippet,
                    }
                )

    doc.close()
    return {
        "gate": "rule10_prose_grounding",
        "pdf": pdf_path.name,
        "pages": page_count,
        "authorized_pool_size": len(authorized),
        "sources_loaded": meta,
        "numbers_checked": total_checked,
        "ungrounded_count": len(ungrounded),
        "ungrounded": ungrounded,
        "passed": len(ungrounded) == 0,
    }
