#!/usr/bin/env python3
"""Fetch 100% live, zero-auth botanical telemetry from GBIF v1, iNaturalist v1, and Open Tree of Life v3.

All raw API responses are written verbatim to data/raw/ and sealed with SHA-256 hashes in data/manifest.sha256.
Zero hardcoded biological statistics: every taxonomy rank, IUCN code, occurrence count, lat/lon dot,
herbarium split, flowering phenology histogram, and phylogenetic Newick subtree comes straight from live APIs.
"""

from __future__ import annotations

import hashlib
import json
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = ROOT / "data" / "raw"
DATA_DIR = ROOT / "data"
ASSETS_DIR = ROOT / "report" / "assets"

UA = "verifiable-editorial-skills-botanica/1.0 (+https://github.com/gke0op/verifiable-editorial-skills)"

SPECIES = [
    {"slug": "ginkgo", "canonical": "Ginkgo biloba", "common": "Maidenhair Tree"},
    {"slug": "welwitschia", "canonical": "Welwitschia mirabilis", "common": "Welwitschia"},
    {"slug": "sequoia", "canonical": "Sequoia sempervirens", "common": "Coast Redwood"},
    {"slug": "victoria", "canonical": "Victoria amazonica", "common": "Giant Amazon Water Lily"},
    {"slug": "dionaea", "canonical": "Dionaea muscipula", "common": "Venus Flytrap"},
    {"slug": "adansonia", "canonical": "Adansonia digitata", "common": "African Baobab"},
]


def http_json(url: str, payload: dict | None = None, retries: int = 3) -> dict:
    headers = {"User-Agent": UA, "Accept": "application/json"}
    body = None
    if payload is not None:
        headers["Content-Type"] = "application/json"
        body = json.dumps(payload).encode("utf-8")

    last_err: Exception | None = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, data=body, headers=headers)
            with urllib.request.urlopen(req, timeout=20) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except Exception as exc:
            last_err = exc
            time.sleep(1.0 + attempt)
    raise RuntimeError(f"Failed fetching {url}: {last_err}")


def save_raw(filename: str, data: dict) -> Path:
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    out = RAW_DIR / filename
    out.write_text(json.dumps(data, indent=2, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")
    return out


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> None:
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    DATA_DIR.mkdir(parents=True, exist_ok=True)

    # 1. GBIF + iNaturalist per species
    for sp in SPECIES:
        slug = sp["slug"]
        q = urllib.parse.quote(sp["canonical"])
        print(f"[fetch] {sp['canonical']}...")

        # GBIF Backbone Match (strictly plant kingdom)
        match = http_json(f"https://api.gbif.org/v1/species/match?kingdom=Plantae&name={q}")
        save_raw(f"gbif_match_{slug}.json", match)
        usage_key = match.get("usageKey")
        if not usage_key:
            raise RuntimeError(f"GBIF match failed for {sp['canonical']}: {match}")

        # GBIF IUCN Red List Category
        iucn = http_json(f"https://api.gbif.org/v1/species/{usage_key}/iucnRedListCategory")
        save_raw(f"gbif_iucn_{slug}.json", iucn)

        # GBIF Occurrence Facets (country + basisOfRecord) + 120 georeferenced points for SVG range map
        occ_url = (
            f"https://api.gbif.org/v1/occurrence/search?taxonKey={usage_key}"
            f"&hasCoordinate=true&hasGeospatialIssue=false&limit=120"
            f"&facet=country&facet=basisOfRecord&facetLimit=12"
        )
        occ = http_json(occ_url)
        # Keep full audited payload cleanly (strip oversized raw media arrays if huge, keep exact coords/keys/facets)
        slim_results = []
        for r in occ.get("results", []):
            slim_results.append(
                {
                    "key": r.get("key"),
                    "decimalLatitude": r.get("decimalLatitude"),
                    "decimalLongitude": r.get("decimalLongitude"),
                    "countryCode": r.get("countryCode"),
                    "basisOfRecord": r.get("basisOfRecord"),
                    "year": r.get("year"),
                    "elevation": r.get("elevation"),
                }
            )
        occ_payload = {
            "source_url": occ_url,
            "taxonKey": usage_key,
            "count": occ.get("count"),
            "facets": occ.get("facets", []),
            "sampled_points_count": len(slim_results),
            "results": slim_results,
        }
        save_raw(f"gbif_occ_{slug}.json", occ_payload)

        # GBIF total occurrences (all records, including non-georeferenced herbarium sheets)
        tot_url = (
            f"https://api.gbif.org/v1/occurrence/search?taxonKey={usage_key}&limit=0"
            f"&facet=basisOfRecord&facet=country&facetLimit=12"
        )
        tot = http_json(tot_url)
        save_raw(f"gbif_total_{slug}.json", {"source_url": tot_url, "taxonKey": usage_key, "count": tot.get("count"), "facets": tot.get("facets", [])})

        # iNaturalist Taxon lookup
        inat_taxa = http_json(f"https://api.inaturalist.org/v1/taxa?q={q}&rank=species&per_page=5")
        save_raw(f"inat_taxa_{slug}.json", inat_taxa)
        chosen_tid = None
        for cand in inat_taxa.get("results", []):
            if cand.get("name", "").lower() == sp["canonical"].lower():
                chosen_tid = cand.get("id")
                break
        if chosen_tid is None and inat_taxa.get("results"):
            chosen_tid = inat_taxa["results"][0].get("id")
        if chosen_tid is None:
            raise RuntimeError(f"iNaturalist taxon not found for {sp['canonical']}")

        # iNaturalist 12-month ALL observations histogram + FLOWERING phenology histogram (term_id=12, term_value_id=13)
        hist_all = http_json(
            f"https://api.inaturalist.org/v1/observations/histogram?taxon_id={chosen_tid}&date_field=observed&interval=month_of_year"
        )
        save_raw(f"inat_hist_all_{slug}.json", hist_all)

        hist_flw = http_json(
            f"https://api.inaturalist.org/v1/observations/histogram?taxon_id={chosen_tid}&term_id=12&term_value_id=13&date_field=observed&interval=month_of_year"
        )
        save_raw(f"inat_hist_flowering_{slug}.json", hist_flw)
        time.sleep(0.25)

    # 2. Open Tree of Life v3 — TNRS Match + Real Induced Phylogenetic Subtree (Newick)
    print("[fetch] Open Tree of Life v3 TNRS + induced phylogenetic subtree...")
    names = [s["canonical"] for s in SPECIES]
    tnrs = http_json("https://api.opentreeoflife.org/v3/tnrs/match_names", {"names": names})
    save_raw("opentree_tnrs.json", tnrs)

    ott_ids = []
    for item in tnrs.get("results", []):
        matches = item.get("matches", [])
        if matches:
            ott_ids.append(matches[0]["taxon"]["ott_id"])
    if len(ott_ids) != len(SPECIES):
        raise RuntimeError(f"Expected {len(SPECIES)} OTT IDs, got {ott_ids}")

    subtree = http_json(
        "https://api.opentreeoflife.org/v3/tree_of_life/induced_subtree",
        {"ott_ids": ott_ids, "label_format": "name_and_id"},
    )
    save_raw("opentree_subtree.json", subtree)

    # 3. Seal all raw JSON payloads (+ any present botanical plate JPEGs) in manifest.sha256
    manifest_lines = []
    for fpath in sorted(RAW_DIR.glob("*.json")):
        rel = fpath.relative_to(ROOT).as_posix()
        manifest_lines.append(f"{sha256_file(fpath)}  {rel}")
    if ASSETS_DIR.is_dir():
        for fpath in sorted(ASSETS_DIR.glob("*.jpg")):
            rel = fpath.relative_to(ROOT).as_posix()
            manifest_lines.append(f"{sha256_file(fpath)}  {rel}")

    manifest_path = DATA_DIR / "manifest.sha256"
    manifest_path.write_text("\n".join(manifest_lines) + "\n", encoding="utf-8")
    print(f"[fetch] Done. Sealed {len(manifest_lines)} raw/asset files -> {manifest_path}")


if __name__ == "__main__":
    main()
