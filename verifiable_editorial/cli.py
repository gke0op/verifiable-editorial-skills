"""Unified `vedit` CLI for verifiable-editorial verification & visual-QA gates."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from .contrast import audit_contrast
from .coverage import audit_coverage
from .fonts import fetch_fonts
from .geometry import audit_geometry
from .links import audit_links
from .prepress import audit_prepress
from .prose import audit_prose
from .spreads import render_spreads


def _parse_pages(spec: str | None) -> set[int] | None:
    if not spec:
        return None
    out: set[int] = set()
    for part in spec.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            lo, hi = part.split("-", 1)
            out.update(range(int(lo), int(hi) + 1))
        else:
            out.add(int(part))
    return out


def _emit(result: dict, json_path: Path | None) -> int:
    if json_path:
        json_path.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    gate = result.get("gate", "audit")
    passed = bool(result.get("passed", False))
    status = "PASS" if passed else "FAIL"
    print(f"[vedit:{gate}] {status} -> {result.get('pdf', '')}")

    if gate == "wcag_contrast":
        print(
            f"  spans={result['total_spans']} | worst_cr={result['worst_contrast_ratio']:.2f}:1 | "
            f"violations={result['total_violations']}"
        )
        for p in result["page_reports"]:
            for v in p["violations"][:5]:
                print(f"  [!] p.{v['page']} cr={v['ratio']}:1 (<{v['required']}) fg={v['fg']} bg={v['bg']} {v['text']!r}")
    elif gate == "geometry":
        print(
            f"  collisions={result['total_collisions']} | clipped={result['total_clipped']} | "
            f"overflow={result['total_trim_overflow']} | orphans={result['total_headline_orphans']} | "
            f"noisy_overlays={result['total_noisy_overlays']}"
        )
        for p in result["page_reports"]:
            for c in p["collisions"][:5]:
                print(f"  [!] p.{p['page']} COLLISION ({c['kind']}): {c['text_a']!r} <-> {c['text_b']!r}")
            for cl in p["clipped"][:5]:
                print(f"  [!] p.{p['page']} CLIPPED ({cl['visible_chars']}/{cl['total_chars']} chars): {cl['unclipped_text']!r}")
            for ov in p["trim_overflow"][:5]:
                print(f"  [!] p.{p['page']} OVERFLOW: {ov['text']!r} {ov['bbox']}")
            for orp in p["headline_orphans"][:5]:
                print(f"  [!] p.{p['page']} ORPHAN HEADLINE: {orp['first_line']!r} -> {orp['orphan_word']!r}")
            for ns in p["noisy_overlays"][:5]:
                print(f"  [!] p.{p['page']} NOISY OVERLAY (rms={ns['bg_edge_rms']}): {ns['text']!r}")
    elif gate == "photo_coverage":
        print(
            f"  enforced_pages={result['enforced_pages']} | min_visible={result['min_visible_pct']:.1f}% | "
            f"avg_visible={result['avg_visible_pct']:.1f}%"
        )
        for f in result["failures"]:
            print(f"  [!] {f}")
    elif gate == "rule10_prose_grounding":
        print(
            f"  numbers_checked={result['numbers_checked']} | authorized_pool={result['authorized_pool_size']} | "
            f"ungrounded={result['ungrounded_count']}"
        )
        for u in result["ungrounded"][:12]:
            print(f"  [!] p.{u['page']} UNGROUNDED {u['token']!r} in: ...{u['context']}...")
    elif gate == "prepress":
        dpi_str = f"{result['min_effective_dpi']:.1f}" if result["min_effective_dpi"] is not None else "n/a(vector)"
        ua = result["pdf_ua_structure"]
        vp = result.get("verapdf_ua1")
        vp_str = (
            f"compliant={vp['compliant']} (pass={vp.get('passed_rules')}, fail={vp.get('failed_rules')})"
            if vp and vp.get("available")
            else ("skipped" if vp is None else "not_installed")
        )
        print(
            f"  images={result['image_count']} | min_dpi={dpi_str} | unembedded_fonts={len(result['unembedded_fonts'])} | "
            f"bleed_all={result['bleed_all_pages']} | cmyk_p99_tac={result['simulated_cmyk_p99_tac_pct']:.1f}% | "
            f"ua_struct={ua['structural_pass']} | verapdf={vp_str}"
        )
        for w in result.get("warnings", []):
            print(f"  [warn] {w}")
        for f in result.get("failures", []):
            print(f"  [!] {f}")
    elif gate == "rule11_links":
        mode = "live" if result["live_checked"] else "offline"
        print(
            f"  clickable={result['clickable_links']} | unique={result['unique_uris']} | "
            f"text_urls={result['text_resources_found']} | declared={result['declared_resources_checked']} | "
            f"mode={mode} | failures={len(result['failures'])}"
        )
        for lr in result.get("live_results", []):
            mark = "OK" if lr["passed"] else "!"
            print(f"  [{mark}] {lr['uri']} -> {lr['verdict']} ({lr['title'][:64]})")
        for f in result.get("failures", []):
            print(f"  [!] p.{f['page']} {f['kind']}: {f['detail']}")

    return 0 if passed else 1


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="vedit", description="Verifiable Editorial PDF verification & visual-QA CLI.")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_cr = sub.add_parser("contrast", help="Background-sampled WCAG 2.1 contrast audit.")
    p_cr.add_argument("pdf", type=Path)
    p_cr.add_argument("--json", type=Path, default=None)

    p_geo = sub.add_parser("geometry", help="Deterministic collision, clip-path, overflow, orphan & texture linter.")
    p_geo.add_argument("pdf", type=Path)
    p_geo.add_argument("--no-orphans", action="store_true")
    p_geo.add_argument("--max-rms", type=float, default=55.0)
    p_geo.add_argument("--json", type=Path, default=None)

    p_cov = sub.add_parser("coverage", help="Exact clip-aware dual-key visible photo coverage gate.")
    p_cov.add_argument("pdf", type=Path)
    p_cov.add_argument("--min-pct", type=float, default=50.0)
    p_cov.add_argument("--min-edges", type=int, default=2)
    p_cov.add_argument("--pages", type=str, default=None, help="1-based page list/ranges, e.g. '1,4-9'")
    p_cov.add_argument("--json", type=Path, default=None)

    p_pr = sub.add_parser("prose", help="Rule 10 post-render PDF prose-to-ledger grounding auditor.")
    p_pr.add_argument("pdf", type=Path)
    p_pr.add_argument("--ledger", type=Path, default=None)
    p_pr.add_argument("--summary", type=Path, default=None)
    p_pr.add_argument("--citations", type=Path, default=None)
    p_pr.add_argument("--manifest", type=Path, default=None)
    p_pr.add_argument("--json", type=Path, default=None)

    p_lk = sub.add_parser("links", help="Rule 11 clickable PDF resource link & live anti-hallucination auditor.")
    p_lk.add_argument("pdf", type=Path)
    p_lk.add_argument("--citations", type=Path, default=None)
    p_lk.add_argument("--ledger", type=Path, default=None)
    p_lk.add_argument("--min-links", type=int, default=1)
    p_lk.add_argument("--offline", action="store_true", help="Check PDF clickable annotations & coverage without live HTTP probing.")
    p_lk.add_argument("--timeout", type=float, default=10.0)
    p_lk.add_argument("--allow-localhost", action="store_true", help="Allow 127.0.0.1/localhost URLs (strictly for local tests).")
    p_lk.add_argument("--json", type=Path, default=None)

    p_sp = sub.add_parser("spreads", help="Render facing-spread contact sheets ([2|3], [4|5], ...).")
    p_sp.add_argument("pdf", type=Path)
    p_sp.add_argument("--out-dir", type=Path, required=True)
    p_sp.add_argument("--dpi", type=int, default=150)
    p_sp.add_argument("--width", type=int, default=1600)

    p_pp = sub.add_parser("prepress", help="Print pre-press preflight (effective DPI, fonts, bleed, CMYK TAC, PDF/UA-1 + veraPDF).")
    p_pp.add_argument("pdf", type=Path)
    p_pp.add_argument("--min-dpi", type=float, default=300.0)
    p_pp.add_argument("--max-tac", type=float, default=300.0)
    p_pp.add_argument("--require-bleed", action="store_true")
    p_pp.add_argument("--require-ua", action="store_true")
    p_pp.add_argument("--no-verapdf", action="store_true")
    p_pp.add_argument("--json", type=Path, default=None)

    p_ft = sub.add_parser("fetch-fonts", help="Download cross-platform SIL-OFL editorial fonts (Cormorant, Source Serif 4, Inter, IBM Plex Mono).")
    p_ft.add_argument("--dir", type=Path, default=None)
    p_ft.add_argument("--force", action="store_true")

    p_all = sub.add_parser("audit-all", help="Run contrast + geometry (+ optional coverage, Rule 10 prose & prepress) together.")
    p_all.add_argument("pdf", type=Path)
    p_all.add_argument("--ledger", type=Path, default=None)
    p_all.add_argument("--summary", type=Path, default=None)
    p_all.add_argument("--citations", type=Path, default=None)
    p_all.add_argument("--manifest", type=Path, default=None)
    p_all.add_argument("--plate-pages", type=str, default=None)
    p_all.add_argument("--min-photo-pct", type=float, default=50.0)
    p_all.add_argument("--prepress-dpi", type=float, default=None, help="Also run prepress gate with this min DPI.")
    p_all.add_argument("--require-ua", action="store_true")
    p_all.add_argument("--verify-links", action="store_true", help="Also run Rule 11 clickable + live anti-hallucination link audit.")
    p_all.add_argument("--check-links-offline", action="store_true", help="Run Rule 11 clickable link audit without live HTTP probing.")
    p_all.add_argument("--min-links", type=int, default=1)

    args = ap.parse_args(argv)

    if args.cmd == "contrast":
        return _emit(audit_contrast(args.pdf), args.json)
    if args.cmd == "geometry":
        return _emit(audit_geometry(args.pdf, check_orphans=not args.no_orphans, max_bg_edge_rms=args.max_rms), args.json)
    if args.cmd == "coverage":
        return _emit(
            audit_coverage(args.pdf, min_pct=args.min_pct, min_bleed_edges=args.min_edges, pages=_parse_pages(args.pages)),
            args.json,
        )
    if args.cmd == "prose":
        return _emit(audit_prose(args.pdf, args.ledger, args.summary, args.citations, args.manifest), args.json)
    if args.cmd == "links":
        return _emit(
            audit_links(
                args.pdf,
                citations_path=args.citations,
                ledger_path=args.ledger,
                min_links=args.min_links,
                live=not args.offline,
                timeout=args.timeout,
                allow_localhost=args.allow_localhost,
            ),
            args.json,
        )
    if args.cmd == "spreads":
        written = render_spreads(args.pdf, args.out_dir, dpi=args.dpi, width=args.width)
        print(f"[vedit:spreads] Wrote {len(written)} facing spread(s) -> {args.out_dir}")
        return 0
    if args.cmd == "prepress":
        return _emit(
            audit_prepress(
                args.pdf,
                min_dpi=args.min_dpi,
                max_tac_pct=args.max_tac,
                require_bleed=args.require_bleed,
                require_ua=args.require_ua,
                run_verapdf=not args.no_verapdf,
            ),
            args.json,
        )
    if args.cmd == "fetch-fonts":
        mf = fetch_fonts(args.dir, force=args.force)
        print(f"[vedit:fetch-fonts] Ready ({len(mf['fonts'])} SIL-OFL fonts) -> {mf['font_dir']}")
        for f in mf["fonts"]:
            print(f"  - {f['file']:32s} [{f['status']}] {f['bytes']//1024:>4d} KB  sha256={f['sha256'][:12]}")
        return 0
    if args.cmd == "audit-all":
        rc = 0
        rc |= _emit(audit_contrast(args.pdf), None)
        rc |= _emit(audit_geometry(args.pdf), None)
        if args.plate_pages:
            rc |= _emit(audit_coverage(args.pdf, min_pct=args.min_photo_pct, pages=_parse_pages(args.plate_pages)), None)
        if args.ledger or args.summary:
            rc |= _emit(audit_prose(args.pdf, args.ledger, args.summary, args.citations, args.manifest), None)
        if args.prepress_dpi is not None or args.require_ua:
            rc |= _emit(
                audit_prepress(
                    args.pdf,
                    min_dpi=args.prepress_dpi if args.prepress_dpi is not None else 0.0,
                    require_ua=args.require_ua,
                ),
                None,
            )
        if args.verify_links or args.check_links_offline:
            rc |= _emit(
                audit_links(
                    args.pdf,
                    citations_path=args.citations,
                    ledger_path=args.ledger,
                    min_links=args.min_links,
                    live=args.verify_links,
                ),
                None,
            )
        return 1 if rc else 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
