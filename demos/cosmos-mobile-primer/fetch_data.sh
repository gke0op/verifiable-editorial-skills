#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
RAW="$ROOT/data/raw"
mkdir -p "$RAW"

UA="verifiable-editorial/0.5 (https://github.com/gke0op/verifiable-editorial-skills)"

echo "[1/7] NASA JPL Small-Body Database: 67P/Churyumov-Gerasimenko..."
curl -fsSL -A "$UA" "https://ssd-api.jpl.nasa.gov/sbdb.api?sstr=67P&phys-par=1" -o "$RAW/jpl_sbdb_67p.json"

echo "[2/7] NASA NSSDC Planetary Fact Sheets (Earth, Jupiter, Sun)..."
curl -fsSL -A "$UA" "https://nssdc.gsfc.nasa.gov/planetary/factsheet/earthfact.html" -o "$RAW/nasa_earth_fact.html"
curl -fsSL -A "$UA" "https://nssdc.gsfc.nasa.gov/planetary/factsheet/jupiterfact.html" -o "$RAW/nasa_jupiter_fact.html"
curl -fsSL -A "$UA" "https://nssdc.gsfc.nasa.gov/planetary/factsheet/sunfact.html" -o "$RAW/nasa_sun_fact.html"

echo "[3/7] arXiv primary abstracts (Bond 2017 Sirius B, Joyce 2018 Sirius B redshift, Miller-Jones 2021 Cyg X-1, GRAVITY 2022 Sgr A*)..."
curl -fsSL -A "$UA" "https://export.arxiv.org/api/query?id_list=1703.10625,1809.01240,2102.09091,2112.07478" -o "$RAW/arxiv_abstracts.xml"

echo "[4/7] Crossref peer-reviewed metadata: NICER PSR J0740+6620 (Riley 2021)..."
curl -fsSL -A "$UA" "https://api.crossref.org/works/10.3847/2041-8213/ac0a81" -o "$RAW/crossref_nicer_riley2021.json"

echo "[5/7] Crossref peer-reviewed metadata: EHT M87* (2019)..."
curl -fsSL -A "$UA" "https://api.crossref.org/works/10.3847/2041-8213/ab0ec7" -o "$RAW/crossref_eht_m87_2019.json"

echo "[6/7] Crossref peer-reviewed metadata: EHT Sgr A* (2022) & Rosetta 67P (Patzold 2016)..."
curl -fsSL -A "$UA" "https://api.crossref.org/works/10.3847/2041-8213/ac6674" -o "$RAW/crossref_eht_sgra_2022.json"
curl -fsSL -A "$UA" "https://api.crossref.org/works/10.1038/nature16535" -o "$RAW/crossref_rosetta_patzold2016.json"

echo "[7/7] Sealing SHA-256 manifest (data/manifest.sha256)..."
(cd "$ROOT" && shasum -a 256 data/raw/* | LC_ALL=C sort -k2 > data/manifest.sha256)
cat "$ROOT/data/manifest.sha256"
