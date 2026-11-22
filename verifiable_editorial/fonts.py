"""Cross-platform SIL-OFL open-source editorial font bundle fetcher (`vedit fetch-fonts`).

Downloads open-source publication fonts (Cormorant Garamond, Source Serif 4 / Newsreader, Inter,
IBM Plex Mono) from official GitHub releases/mirrors into a deterministic local directory so
Typst (`--font-path`) and WeasyPrint (`@font-face`) render byte-identically on Linux CI and macOS.
"""

from __future__ import annotations

import hashlib
import json
import urllib.request
from pathlib import Path

DEFAULT_CACHE_DIR = Path.home() / ".cache" / "verifiable-editorial" / "fonts"
UA = "verifiable-editorial-font-fetcher/0.2 (+https://github.com/gke0op/verifiable-editorial-skills)"

# Official SIL Open Font License (OFL-1.1) raw font sources from google/fonts on GitHub
FONT_SPECS: list[dict[str, str]] = [
    # Cormorant Garamond (High-contrast Didone/Garamond editorial display serif)
    {
        "file": "CormorantGaramond-Regular.ttf",
        "family": "Cormorant Garamond",
        "url": "https://raw.githubusercontent.com/google/fonts/main/ofl/cormorantgaramond/CormorantGaramond%5Bwght%5D.ttf",
    },
    {
        "file": "CormorantGaramond-Italic.ttf",
        "family": "Cormorant Garamond",
        "url": "https://raw.githubusercontent.com/google/fonts/main/ofl/cormorantgaramond/CormorantGaramond-Italic%5Bwght%5D.ttf",
    },
    # Source Serif 4 (Adobe open-source book & scientific monograph serif)
    {
        "file": "SourceSerif4-Regular.ttf",
        "family": "Source Serif 4",
        "url": "https://raw.githubusercontent.com/google/fonts/main/ofl/sourceserif4/SourceSerif4%5Bopsz%2Cwght%5D.ttf",
    },
    {
        "file": "SourceSerif4-Italic.ttf",
        "family": "Source Serif 4",
        "url": "https://raw.githubusercontent.com/google/fonts/main/ofl/sourceserif4/SourceSerif4-Italic%5Bopsz%2Cwght%5D.ttf",
    },
    # Inter (Clean geometric data-viz & micro-label sans)
    {
        "file": "Inter-Variable.ttf",
        "family": "Inter",
        "url": "https://raw.githubusercontent.com/google/fonts/main/ofl/inter/Inter%5Bopsz%2Cwght%5D.ttf",
    },
    {
        "file": "Inter-Italic-Variable.ttf",
        "family": "Inter",
        "url": "https://raw.githubusercontent.com/google/fonts/main/ofl/inter/Inter-Italic%5Bopsz%2Cwght%5D.ttf",
    },
    # IBM Plex Mono (Crisp tabular monospace for SHA-256 hashes & scientific IDs)
    {
        "file": "IBMPlexMono-Regular.ttf",
        "family": "IBM Plex Mono",
        "url": "https://raw.githubusercontent.com/google/fonts/main/ofl/ibmplexmono/IBMPlexMono-Regular.ttf",
    },
    {
        "file": "IBMPlexMono-SemiBold.ttf",
        "family": "IBM Plex Mono",
        "url": "https://raw.githubusercontent.com/google/fonts/main/ofl/ibmplexmono/IBMPlexMono-SemiBold.ttf",
    },
]


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def fetch_fonts(target_dir: Path | str | None = None, force: bool = False) -> dict:
    """Download SIL-OFL editorial font stack into target_dir (idempotent cache) and write manifest."""
    out_dir = Path(target_dir) if target_dir else DEFAULT_CACHE_DIR
    out_dir.mkdir(parents=True, exist_ok=True)

    results = []
    for spec in FONT_SPECS:
        dest = out_dir / spec["file"]
        if dest.exists() and dest.stat().st_size > 10_000 and not force:
            digest = _sha256(dest.read_bytes())
            results.append({"file": spec["file"], "family": spec["family"], "status": "cached", "bytes": dest.stat().st_size, "sha256": digest})
            continue
        req = urllib.request.Request(spec["url"], headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=25) as resp:
            data = resp.read()
        if len(data) < 10_000:
            raise RuntimeError(f"Downloaded font too small ({len(data)} bytes): {spec['url']}")
        dest.write_bytes(data)
        digest = _sha256(data)
        results.append({"file": spec["file"], "family": spec["family"], "status": "downloaded", "bytes": len(data), "sha256": digest})

    manifest = {"license": "SIL Open Font License 1.1", "font_dir": str(out_dir), "fonts": results}
    (out_dir / "fonts_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest
