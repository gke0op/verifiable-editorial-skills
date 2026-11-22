#!/usr/bin/env python3
"""Seal all Nano Banana editorial photographs with SHA-256 digests and verified metadata."""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ASSETS_DIR = ROOT / "report" / "assets"
DATA_DIR = ROOT / "data"

IDENTITY_CORE = (
    "Shot on Leica M11, 50mm f/1.4 Summilux, Kodak Portra 400 analog color grade, "
    "natural window and ambient sunlight, subtle organic 35mm film grain, "
    "zero text, zero watermarks, zero borders."
)

PLATES = [
    {
        "plate": "01",
        "file": "photo_01_cover_istanbul.jpg",
        "page": 1,
        "location": "Istanbul, Turkey",
        "district": "Bosphorus Balustrade",
        "coords": "41°01′N 28°59′E",
        "aspect": "3:4",
        "caption": "A calico watches the evening ferry crossing between Europe and Asia from a weathered limestone parapet.",
        "subject": "Calico street cat at golden hour overlooking the Bosphorus and Ottoman domes",
    },
    {
        "plate": "02",
        "file": "photo_02_istanbul_cafe.jpg",
        "page": 2,
        "location": "Istanbul, Turkey",
        "district": "Cihangir",
        "coords": "41°01′N 28°59′E",
        "aspect": "4:3",
        "caption": "Midday stillness on a cedar pavement table beside a tulip glass of black tea in Cihangir.",
        "subject": "Marmalade tabby sleeping beside a Turkish tea glass on a cobblestone alley table",
    },
    {
        "plate": "03",
        "file": "photo_03_kyoto_shrine.jpg",
        "page": 3,
        "location": "Kyoto, Japan",
        "district": "Higashiyama Cedar Shrines",
        "coords": "35°00′N 135°46′E",
        "aspect": "3:4",
        "caption": "A Japanese Bobtail keeps watch on rain-darkened granite steps between vermilion torii pillars.",
        "subject": "White-and-tortoiseshell Japanese Bobtail on mossy Kyoto shrine steps in morning mist",
    },
    {
        "plate": "04",
        "file": "photo_04_chefchaouen_stairs.jpg",
        "page": 4,
        "location": "Chefchaouen, Morocco",
        "district": "Rif Medina",
        "coords": "35°10′N 05°16′W",
        "aspect": "3:4",
        "caption": "Warm ginger fur cuts across limewashed cobalt steps lined with terracotta geraniums in the Rif Mountains.",
        "subject": "Ginger cat pausing mid-stride on cobalt-blue plaster stairs in Chefchaouen",
    },
    {
        "plate": "05",
        "file": "photo_05_santorini_caldera.jpg",
        "page": 5,
        "location": "Santorini, Greece",
        "district": "Oia Caldera Rim",
        "coords": "36°27′N 25°22′E",
        "aspect": "16:9",
        "caption": "High above the flooded volcanic basin, a black-and-white tuxedo cat claims the warm afternoon parapet.",
        "subject": "Tuxedo cat perched on whitewashed Oia wall overlooking the Aegean caldera",
    },
    {
        "plate": "06",
        "file": "photo_06_santorini_shutters.jpg",
        "page": 5,
        "location": "Santorini, Greece",
        "district": "Cycladic Courtyard",
        "coords": "36°27′N 25°22′E",
        "aspect": "3:4",
        "caption": "Afternoon heat softens into limestone shade beneath salt-weathered cobalt shutters.",
        "subject": "Silver-cream tabby asleep on stone wall against peeling blue wooden shutters",
    },
    {
        "plate": "07",
        "file": "photo_07_reykjavik_winter.jpg",
        "page": 6,
        "location": "Reykjavík, Iceland",
        "district": "Þingholt Timber Quarter",
        "coords": "64°08′N 21°56′W",
        "aspect": "4:3",
        "caption": "Snowflakes catch in a double winter coat outside a glowing Nordic window during blue hour.",
        "subject": "Silver-grey longhaired forest cat on frost-dusted basalt steps in snowfall",
    },
    {
        "plate": "08",
        "file": "photo_08_rome_ruins.jpg",
        "page": 7,
        "location": "Rome, Italy",
        "district": "Largo di Torre Argentina",
        "coords": "41°53′N 12°28′E",
        "aspect": "3:4",
        "caption": "Sovereign of Republican stone: a black cat settles onto a sun-warmed fluted travertine column.",
        "subject": "Jet-black Roman cat reclining atop a fluted travertine marble ruin column",
    },
    {
        "plate": "09",
        "file": "photo_09_tokyo_yanaka.jpg",
        "page": 7,
        "location": "Tokyo, Japan",
        "district": "Yanaka Ginza",
        "coords": "35°43′N 139°45′E",
        "aspect": "4:3",
        "caption": "At dusk along Yanaka's wooden storefronts, a tortoiseshell inspects the evening foot traffic.",
        "subject": "Tortoiseshell cat on weathered hinoki counter beneath a warm cream lantern",
    },
    {
        "plate": "10",
        "file": "photo_10_lima_kennedy.jpg",
        "page": 7,
        "location": "Lima, Peru",
        "district": "Parque Kennedy, Miraflores",
        "coords": "12°07′S 77°01′W",
        "aspect": "4:3",
        "caption": "Framed by broad monstera fronds, a Miraflores resident pauses along the terracotta garden walk.",
        "subject": "Striped brown tabby seated on sunlit terracotta brick path in Parque Kennedy",
    },
    {
        "plate": "11",
        "file": "photo_11_closing_dusk.jpg",
        "page": 8,
        "location": "Mediterranean Basin",
        "district": "Twilight Study",
        "coords": "36°N · COASTAL LIMESTONE",
        "aspect": "3:4",
        "caption": "Blue hour over an open sea window, warm lamplight catching whiskers against carved coastal stone.",
        "subject": "Curled tabby on weathered Mediterranean limestone sill gazing toward dusk sea",
    },
]


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    records = []
    manifest_lines = []

    for meta in PLATES:
        img_path = ASSETS_DIR / meta["file"]
        if not img_path.exists():
            raise FileNotFoundError(f"Missing editorial plate: {img_path}")
        digest = sha256_file(img_path)
        with Image.open(img_path) as im:
            w, h = im.size
        rec = {
            **meta,
            "width_px": w,
            "height_px": h,
            "bytes": img_path.stat().st_size,
            "sha256": digest,
            "sha256_short": digest[:12],
            "credit": "Nano Banana Studio (AI Editorial Photography)",
        }
        records.append(rec)
        manifest_lines.append(f"{digest}  report/assets/{meta['file']}")

    manifest_path = DATA_DIR / "manifest.sha256"
    manifest_path.write_text("\n".join(sorted(manifest_lines)) + "\n", encoding="utf-8")

    ledger = {
        "publication": "FELIS MUNDI — Cats Around the World",
        "issue": "Issue 01 · Autumn 2026",
        "generated_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "identity_core": IDENTITY_CORE,
        "plate_count": len(records),
        "plates": records,
    }
    credits_path = DATA_DIR / "photo_credits.json"
    credits_path.write_text(json.dumps(ledger, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"[seal_assets] Sealed {len(records)} plates -> {manifest_path.name} & {credits_path.name}")


if __name__ == "__main__":
    main()
