"""Rule 11 — Clickable Resource Link & Live Anti-Hallucination Auditor (`vedit links`).

Audits the FINAL compiled PDF bytes (`fitz.open(pdf)`) to guarantee that:
  1. Every external resource, URL, and DOI printed in PDF text or declared in
     `background_citations.json` / `provenance_ledger.json` is an actual clickable PDF
     `/Subtype /Link` `/URI` annotation with a valid, visible bounding box (`>= 2x2 pt` inside trim).
  2. No placeholder, local, or malformed domains (`example.com`, `localhost`, `.invalid`, `TODO`) ship.
  3. Every clickable external link is ACTUALLY VISITED AND VERIFIED LIVE before finalizing:
     - Academic/dataset DOIs (incl. `doi.org`, `link.aps.org/doi/`, `nature.com/articles/`) are verified
       against the authoritative CNRI/IDF DOI Handle Registry (`https://doi.org/api/handles/<doi>`),
       defeating both publisher Cloudflare walls and HTTP-200 JS challenge traps on fake article URLs.
     - WAF-fronted open-science portals (`gbif.org/species/<id>`, `inaturalist.org/taxa/<id>`) are
       verified against their official public REST APIs.
     - All other URLs are fetched via live HTTP GET (following redirects), inspecting HTTP status,
       `<title>`, and `<h1>` to reject 404/410/403/5xx, DNS failures, Soft-404 pages, and
       HTTP-200 bot-challenge interstitials (`Client Challenge`, `Just a moment...`).
"""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
import html
import json
from pathlib import Path
import re
from typing import Any
import urllib.error
import urllib.parse
import urllib.request
import fitz  # PyMuPDF

TEXT_URL_RE = re.compile(r"https?://[^\s<>()\[\]\"']+")
TEXT_DOI_RE = re.compile(r"(?:doi:\s*)?\b(10\.\d{4,9}/[-._;()/:A-Za-z0-9]+)", re.IGNORECASE)
TITLE_RE = re.compile(r"<title[^>]*>(.*?)</title>", re.IGNORECASE | re.DOTALL)
H1_RE = re.compile(r"<h1[^>]*>(.*?)</h1>", re.IGNORECASE | re.DOTALL)
TAG_STRIP_RE = re.compile(r"<[^>]+>")

PLACEHOLDER_HOSTS = {
    "example.com",
    "www.example.com",
    "example.org",
    "www.example.org",
    "example.net",
    "www.example.net",
    "foo.bar",
    "your-domain.com",
    "yourdomain.com",
    "placeholder.com",
    "placeholder.org",
}
LOCAL_HOSTS = {"localhost", "127.0.0.1", "0.0.0.0", "::1", "[::1]"}
PLACEHOLDER_TLDS = (".invalid", ".test", ".local", ".example", ".localhost")
PLACEHOLDER_TOKENS = ("placeholder", "todo", "tbd", "insert-url", "your-link")

BOT_CHALLENGE_PATTERNS = (
    "client challenge",
    "just a moment",
    "attention required",
    "verify you are human",
    "are you a robot",
    "bot detection",
    "pardon our interruption",
    "ddos-guard",
    "security check",
    "access denied",
    "enable javascript and cookies to continue",
)

SOFT_404_PATTERNS = (
    "404 not found",
    "error 404",
    "404 error",
    "404 -",
    "404 |",
    "page not found",
    "article not found",
    "document not found",
    "doi not found",
    "file not found",
    "resource not found",
    "record not found",
    "cannot be found",
    "could not be found",
    "couldn't be found",
    "this page doesn't exist",
    "this page does not exist",
    "page does not exist",
    "no longer available",
    "broken link",
)

USER_AGENT = "Mozilla/5.0 (compatible; verifiable-editorial-vedit/0.6; +https://github.com/gke0op/verifiable-editorial-skills)"


def _strip_trailing_punct(raw: str) -> str:
    s = raw.replace("\u00ad", "").strip()
    while s and s[-1] in ".,;:!?'\"":
        s = s[:-1]
    while s.endswith(")") and s.count(")") > s.count("("):
        s = s[:-1]
    while s.endswith("]") and s.count("]") > s.count("["):
        s = s[:-1]
    return s


def _extract_doi_from_uri(uri: str) -> str | None:
    """Extract a canonical DOI (`10.xxxx/...`) from doi.org or known publisher DOI/article URLs."""
    u = _strip_trailing_punct(uri)
    m_bare = re.match(r"^(?:doi:\s*)?(10\.\d{4,9}/\S+)$", u, re.IGNORECASE)
    if m_bare:
        return m_bare.group(1)
    parsed = urllib.parse.urlparse(u)
    host = (parsed.hostname or "").lower()
    path = urllib.parse.unquote(parsed.path or "").lstrip("/")
    if host in ("doi.org", "www.doi.org", "dx.doi.org"):
        if re.match(r"^10\.\d{4,9}/\S+", path):
            return path
    if host in ("nature.com", "www.nature.com") and path.startswith("articles/"):
        slug = path[len("articles/") :].split("/")[0].split("?")[0]
        if slug and re.match(r"^[A-Za-z0-9._-]+$", slug):
            return f"10.1038/{slug}"
    m_emb = re.search(r"/(10\.\d{4,9}/[^\s?#]+)", "/" + path)
    if m_emb and any(
        dom in host
        for dom in ("aps.org", "science.org", "wiley.com", "acs.org", "tandfonline.com", "springer.com", "sagepub.com", "iop.org", "oup.com")
    ):
        return m_emb.group(1)
    return None


def _canonical_key(raw: str) -> str:
    s = _strip_trailing_punct(raw)
    doi = _extract_doi_from_uri(s)
    if doi:
        return "doi:" + doi.lower()
    parsed = urllib.parse.urlparse(s)
    scheme = (parsed.scheme or "https").lower()
    host = (parsed.hostname or "").lower()
    port = f":{parsed.port}" if parsed.port else ""
    path = parsed.path.rstrip("/")
    query = f"?{parsed.query}" if parsed.query else ""
    return f"{scheme}://{host}{port}{path}{query}"


def _validate_uri_syntax(uri: str, *, allow_localhost: bool = False) -> str | None:
    """Return error reason string if URI is malformed or uses a placeholder/local host, else None."""
    if not uri or any(ch.isspace() for ch in uri):
        return "INVALID_URI_WHITESPACE_OR_EMPTY"
    parsed = urllib.parse.urlparse(uri)
    scheme = (parsed.scheme or "").lower()
    if scheme not in ("http", "https"):
        return f"DISALLOWED_SCHEME:{scheme or 'none'}"
    host = (parsed.hostname or "").lower()
    if not host:
        return "MISSING_HOST"
    if host in LOCAL_HOSTS:
        return None if allow_localhost else "LOCALHOST_URI_DISALLOWED"
    if host in PLACEHOLDER_HOSTS or any(host.endswith(tld) for tld in PLACEHOLDER_TLDS):
        return f"PLACEHOLDER_HOST:{host}"
    if "." not in host:
        return f"INVALID_HOST_NO_DOT:{host}"
    low_full = uri.lower()
    for bad in PLACEHOLDER_TOKENS:
        if bad in host or f"/{bad}" in low_full:
            return f"PLACEHOLDER_URI:{bad}"
    return None


def _extract_html_title_and_h1(body: str) -> tuple[str, str]:
    tm = TITLE_RE.search(body)
    hm = H1_RE.search(body)
    title = html.unescape(" ".join(TAG_STRIP_RE.sub(" ", tm.group(1)).split())) if tm else ""
    h1 = html.unescape(" ".join(TAG_STRIP_RE.sub(" ", hm.group(1)).split())) if hm else ""
    return title[:140], h1[:140]


def _classify_soft_404_or_challenge(title: str, h1: str, body_sample: str) -> str | None:
    tl = title.lower()
    hl = h1.lower()
    bl = body_sample[:4096].lower()
    for pat in BOT_CHALLENGE_PATTERNS:
        if pat in tl or pat in hl:
            return f"BOT_CHALLENGE_UNVERIFIED:{title or h1}"
    if "cf-browser-verification" in bl or "challenge-platform" in bl or "window._cf_chl_opt" in bl:
        return f"BOT_CHALLENGE_UNVERIFIED:{title or 'cloudflare'}"
    for pat in SOFT_404_PATTERNS:
        if pat in tl or pat in hl:
            return f"SOFT_404_HALLUCINATED:{title or h1}"
    return None


def _http_get_text(url: str, timeout: float = 10.0, max_bytes: int = 65536) -> tuple[int, str, str, str | None]:
    """Return `(http_status, final_url, body_prefix, error_msg)`."""
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": USER_AGENT,
            "Accept": "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            status = int(getattr(resp, "status", 200))
            final_url = resp.geturl()
            raw = resp.read(max_bytes)
            body = raw.decode("utf-8", errors="ignore")
            return status, final_url, body, None
    except urllib.error.HTTPError as e:
        try:
            body = e.read(4096).decode("utf-8", errors="ignore")
        except Exception:
            body = ""
        return int(e.code), url, body, f"HTTP_{e.code}"
    except Exception as e:
        return -1, url, "", f"UNREACHABLE_OR_HALLUCINATED:{type(e).__name__}:{str(e)[:80]}"


def _verify_live_uri(uri: str, timeout: float = 10.0) -> dict[str, Any]:
    """Verify a single URI live via DOI Handle Registry, open-science API, or direct HTTP GET."""
    # 1. Authoritative DOI Handle Registry check (defeats publisher Cloudflare walls & HTTP-200 fake articles)
    doi = _extract_doi_from_uri(uri)
    if doi:
        handle_url = f"https://doi.org/api/handles/{urllib.parse.quote(doi, safe='/')}"
        st, _, body, err = _http_get_text(handle_url, timeout=timeout, max_bytes=32768)
        if st == 200:
            try:
                data = json.loads(body)
            except ValueError:
                data = {}
            if data.get("responseCode") == 1:
                target = next(
                    (
                        v.get("data", {}).get("value")
                        for v in data.get("values", [])
                        if isinstance(v, dict) and v.get("type") == "URL" and isinstance(v.get("data"), dict)
                    ),
                    uri,
                )
                return {
                    "uri": uri,
                    "method": "doi_handle_api",
                    "status": 200,
                    "final_url": str(target or uri),
                    "title": f"DOI {doi}",
                    "verdict": "VERIFIED_DOI",
                    "passed": True,
                }
            return {
                "uri": uri,
                "method": "doi_handle_api",
                "status": st,
                "final_url": handle_url,
                "title": "",
                "verdict": f"HALLUCINATED_DOI:responseCode={data.get('responseCode')}",
                "passed": False,
            }
        if st == 404:
            return {
                "uri": uri,
                "method": "doi_handle_api",
                "status": 404,
                "final_url": handle_url,
                "title": "",
                "verdict": "HALLUCINATED_DOI:handle_not_found_404",
                "passed": False,
            }
        # Only if handle API itself had a transient non-404 error, fall through to direct HTTP check below

    # 2. Authoritative Open-Science API verification for WAF-fronted portals (GBIF / iNaturalist)
    parsed = urllib.parse.urlparse(uri)
    host = (parsed.hostname or "").lower()
    m_gbif = re.match(r"^/species/(\d+)/?$", parsed.path or "")
    if host in ("gbif.org", "www.gbif.org") and m_gbif:
        sp_id = m_gbif.group(1)
        api_url = f"https://api.gbif.org/v1/species/{sp_id}"
        st, final_u, body, err = _http_get_text(api_url, timeout=timeout, max_bytes=16384)
        if st == 200:
            try:
                d = json.loads(body)
                sci = str(d.get("scientificName") or d.get("canonicalName") or f"GBIF:{sp_id}")
                return {
                    "uri": uri,
                    "method": "gbif_api",
                    "status": 200,
                    "final_url": final_u,
                    "title": sci,
                    "verdict": "VERIFIED_API",
                    "passed": True,
                }
            except ValueError:
                pass
        return {
            "uri": uri,
            "method": "gbif_api",
            "status": st,
            "final_url": api_url,
            "title": "",
            "verdict": err or f"HALLUCINATED_GBIF_TAXON:HTTP_{st}",
            "passed": False,
        }

    m_inat = re.match(r"^/taxa/(\d+)(?:-[^/]*)?/?$", parsed.path or "")
    if host in ("inaturalist.org", "www.inaturalist.org") and m_inat:
        tx_id = m_inat.group(1)
        api_url = f"https://api.inaturalist.org/v1/taxa/{tx_id}"
        st, final_u, body, err = _http_get_text(api_url, timeout=timeout, max_bytes=16384)
        if st == 200:
            try:
                d = json.loads(body)
                if d.get("total_results", 0) >= 1:
                    nm = str(d["results"][0].get("name", f"iNat:{tx_id}"))
                    return {
                        "uri": uri,
                        "method": "inat_api",
                        "status": 200,
                        "final_url": final_u,
                        "title": nm,
                        "verdict": "VERIFIED_API",
                        "passed": True,
                    }
            except ValueError:
                pass
        return {
            "uri": uri,
            "method": "inat_api",
            "status": st,
            "final_url": api_url,
            "title": "",
            "verdict": err or f"HALLUCINATED_INAT_TAXON:HTTP_{st}",
            "passed": False,
        }

    # 3. Direct live HTTP GET verification with Soft-404 & Bot-Challenge rejection
    st, final_u, body, err = _http_get_text(uri, timeout=timeout, max_bytes=65536)
    title, h1 = _extract_html_title_and_h1(body)
    if err or not (200 <= st <= 299):
        return {
            "uri": uri,
            "method": "http_get",
            "status": st,
            "final_url": final_u,
            "title": title,
            "verdict": err or f"HTTP_{st}",
            "passed": False,
        }
    trap = _classify_soft_404_or_challenge(title, h1, body)
    if trap is not None:
        return {
            "uri": uri,
            "method": "http_get",
            "status": st,
            "final_url": final_u,
            "title": title or h1,
            "verdict": trap,
            "passed": False,
        }
    return {
        "uri": uri,
        "method": "http_get",
        "status": st,
        "final_url": final_u,
        "title": title or h1 or "(verified 200 OK)",
        "verdict": "VERIFIED_HTTP",
        "passed": True,
    }


def _collect_declared_urls(obj: Any, out: list[str]) -> None:
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k in ("doi_or_url", "source_url", "url", "href") and isinstance(v, str):
                s = _strip_trailing_punct(v)
                if s.startswith(("http://", "https://")) or re.match(r"^(?:doi:\s*)?10\.\d{4,9}/", s, re.I):
                    out.append(s)
            else:
                _collect_declared_urls(v, out)
    elif isinstance(obj, list):
        for item in obj:
            _collect_declared_urls(item, out)


def audit_links(
    pdf_path: Path | str,
    citations_path: Path | str | None = None,
    ledger_path: Path | str | None = None,
    *,
    min_links: int = 1,
    live: bool = True,
    timeout: float = 10.0,
    allow_localhost: bool = False,
) -> dict[str, Any]:
    """Rule 11: Verify every resource in the compiled PDF is clickable and resolves live (anti-hallucination)."""
    pdf_path = Path(pdf_path)
    doc = fitz.open(pdf_path)
    page_count = len(doc)

    clickable_links: list[dict[str, Any]] = []
    text_resources: list[dict[str, Any]] = []
    failures: list[dict[str, Any]] = []

    for idx, page in enumerate(doc, start=1):
        pr = page.rect
        # 1. Extract all clickable /Subtype /Link /URI annotations
        for lnk in page.get_links():
            uri_raw = lnk.get("uri")
            if not uri_raw:
                continue
            uri = str(uri_raw).strip()
            rect = lnk.get("from", fitz.Rect(0, 0, 0, 0))
            rw = abs(float(rect.x1) - float(rect.x0))
            rh = abs(float(rect.y1) - float(rect.y0))
            on_page = (
                float(rect.x1) > 0.0
                and float(rect.y1) > 0.0
                and float(rect.x0) < float(pr.width)
                and float(rect.y0) < float(pr.height)
            )
            entry = {
                "page": idx,
                "uri": uri,
                "canonical": _canonical_key(uri),
                "rect": [round(float(rect.x0), 1), round(float(rect.y0), 1), round(float(rect.x1), 1), round(float(rect.y1), 1)],
            }
            clickable_links.append(entry)
            if rw < 2.0 or rh < 2.0 or not on_page:
                failures.append(
                    {
                        "page": idx,
                        "kind": "DEGENERATE_OR_HIDDEN_LINK_RECT",
                        "uri": uri,
                        "detail": f"Clickable rect {entry['rect']} is degenerate (<2x2 pt) or off-page",
                    }
                )
            syn_err = _validate_uri_syntax(uri, allow_localhost=allow_localhost)
            if syn_err:
                failures.append({"page": idx, "kind": syn_err, "uri": uri, "detail": f"Invalid/placeholder clickable link: {uri}"})

        # 2. Extract all printed plain-text URLs & DOIs on the page (must be backed by clickable PDF links!)
        # Join hyphen-split/newline-wrapped tokens conservatively without merging unrelated lines
        page_txt = page.get_text("text").replace("\u00ad", "")
        seen_on_page: set[str] = set()
        for m in TEXT_URL_RE.finditer(page_txt):
            u = _strip_trailing_punct(m.group(0))
            ck = _canonical_key(u)
            if ck not in seen_on_page:
                seen_on_page.add(ck)
                text_resources.append({"page": idx, "raw": u, "canonical": ck})
        for m in TEXT_DOI_RE.finditer(page_txt):
            d = _strip_trailing_punct(m.group(1))
            ck = _canonical_key(d)
            if ck not in seen_on_page:
                seen_on_page.add(ck)
                text_resources.append({"page": idx, "raw": d, "canonical": ck})

    doc.close()

    clickable_keys = {c["canonical"] for c in clickable_links}

    # Check minimum clickable resource links
    if len(clickable_links) < min_links:
        failures.append(
            {
                "page": 0,
                "kind": "INSUFFICIENT_CLICKABLE_LINKS",
                "uri": "",
                "detail": f"Found {len(clickable_links)} clickable external link(s), minimum required is {min_links}",
            }
        )

    # Rule 11A: Every URL or DOI printed in PDF text MUST have a clickable PDF /URI annotation
    for tr in text_resources:
        ck = tr["canonical"]
        # Allow prefix match when a printed URL wrapped across a line break (e.g. `https://doi.org/10.1016/j.` -> full clickable URI)
        matched = ck in clickable_keys or any(k.startswith(ck) for k in clickable_keys)
        if not matched:
            failures.append(
                {
                    "page": tr["page"],
                    "kind": "UNLINKED_TEXT_RESOURCE",
                    "uri": tr["raw"],
                    "detail": f"Printed URL/DOI '{tr['raw']}' has no clickable PDF /URI annotation",
                }
            )

    # Rule 11B: Every resource URL/DOI declared in background_citations.json / provenance_ledger.json MUST be clickable in PDF
    declared_urls: list[str] = []
    for p_opt in (citations_path, ledger_path):
        if p_opt:
            p = Path(p_opt)
            if p.exists():
                _collect_declared_urls(json.loads(p.read_text(encoding="utf-8")), declared_urls)

    seen_decl: set[str] = set()
    for du in declared_urls:
        ck = _canonical_key(du)
        if ck in seen_decl:
            continue
        seen_decl.add(ck)
        syn_err = _validate_uri_syntax(du if "://" in du else f"https://doi.org/{du}", allow_localhost=allow_localhost)
        if syn_err:
            failures.append({"page": 0, "kind": syn_err, "uri": du, "detail": f"Declared citation/ledger URI invalid: {du}"})
            continue
        if ck not in clickable_keys:
            failures.append(
                {
                    "page": 0,
                    "kind": "DECLARED_RESOURCE_NOT_CLICKABLE",
                    "uri": du,
                    "detail": f"Resource '{du}' declared in citations/ledger is missing a clickable link in the PDF",
                }
            )

    # Rule 11C: Live Anti-Hallucination Resolution of every unique valid clickable URI
    live_results: list[dict[str, Any]] = []
    unique_valid_uris: list[str] = []
    seen_probe: set[str] = set()
    for c in clickable_links:
        u = c["uri"]
        if u not in seen_probe and _validate_uri_syntax(u, allow_localhost=allow_localhost) is None:
            seen_probe.add(u)
            unique_valid_uris.append(u)

    if live and unique_valid_uris:
        with ThreadPoolExecutor(max_workers=min(6, len(unique_valid_uris))) as ex:
            live_results = list(ex.map(lambda u: _verify_live_uri(u, timeout=timeout), unique_valid_uris))
        uri_to_page = {}
        for c in clickable_links:
            uri_to_page.setdefault(c["uri"], c["page"])
        for lr in live_results:
            if not lr["passed"]:
                failures.append(
                    {
                        "page": uri_to_page.get(lr["uri"], 0),
                        "kind": lr["verdict"],
                        "uri": lr["uri"],
                        "detail": f"Live check failed ({lr['method']}, status={lr['status']}): {lr['verdict']}",
                    }
                )

    passed = len(failures) == 0
    return {
        "gate": "rule11_links",
        "pdf": pdf_path.name,
        "pages": page_count,
        "clickable_links": len(clickable_links),
        "unique_uris": len(unique_valid_uris),
        "text_resources_found": len(text_resources),
        "declared_resources_checked": len(seen_decl),
        "live_checked": live,
        "live_results": live_results,
        "failures": failures,
        "passed": passed,
    }
