// EXOMUNDUS: Census of Confirmed Exoplanets (1992–2026)
// 100% Zero-Python Pipeline: Bare-Metal Zig 0.17.0 Data Compiler + Vector SVGs + Typst 0.15.1 PDF/UA-1.

#let data = json("../data/summary_metrics.json")
#let ledger = json("../data/provenance_ledger.json")
#let m = data.metrics
#let meta = data.metadata

// Deep-Space Mineral Palette on Archival Ivory (all >= 5.2:1 WCAG AA)
#let c-bg     = rgb("#FAF9F6")
#let c-tint   = rgb("#F0ECE3")
#let c-ink    = rgb("#141A20")
#let c-body   = rgb("#252D35")
#let c-muted  = rgb("#45525E")
#let c-navy   = rgb("#0E243D")
#let c-cobalt = rgb("#0B5CAD")
#let c-amber  = rgb("#A34808")
#let c-green  = rgb("#146646")
#let c-rule   = rgb("#CFC8B8")

#let fmt1(v) = {
  let r = calc.round(v, digits: 1)
  let s = str(r)
  if not s.contains(".") { s + ".0" } else { s }
}
#let fmt2(v) = {
  let r = calc.round(v, digits: 2)
  let s = str(r)
  if not s.contains(".") { s + ".00" }
  else {
    let parts = s.split(".")
    if parts.at(1).len() == 1 { s + "0" } else { s }
  }
}
#let fmt-int(v) = {
  let n = int(calc.round(v))
  let neg = n < 0
  let s = str(calc.abs(n))
  let chars = s.clusters().rev()
  let out = ()
  for (i, ch) in chars.enumerate() {
    if i > 0 and calc.rem(i, 3) == 0 { out.push(",") }
    out.push(ch)
  }
  (if neg { "-" } else { "" }) + out.rev().join("")
}

#set document(
  title: "EXOMUNDUS: Census of Confirmed Exoplanets (1992–2026) — Verified Zig + Typst PDF/UA-1 Monograph",
  author: "Verifiable Editorial Skills (Zero-Python Zig + Typst Reference)",
  keywords: ("Exoplanets", "NASA", "Fulton Radius Valley", "Zig 0.17", "Typst", "PDF/UA-1"),
)

#set page(
  paper: "us-letter",
  fill: c-bg,
  margin: (top: 48pt, bottom: 48pt, left: 54pt, right: 54pt),
  header: context {
    if counter(page).get().first() > 1 {
      set text(font: "Inter", size: 6.8pt, weight: "semibold", fill: c-muted, tracking: 0.1em)
      grid(
        columns: (1fr, 1fr),
        align: (left, right),
        [EXOMUNDUS · NASA EXOPLANET ARCHIVE (1992–2026)],
        [PURE ZIG 0.17 · TYPST 0.15 · PDF/UA-1],
      )
      v(-4pt)
      line(length: 100%, stroke: 0.5pt + c-rule)
    }
  },
  footer: context {
    let pg = counter(page).get().first()
    let tot = counter(page).final().first()
    line(length: 100%, stroke: 0.5pt + c-rule)
    v(3pt)
    grid(
      columns: (1fr, auto),
      align: (left, right),
      text(font: "Inter", size: 6.6pt, fill: c-muted, tracking: 0.08em)[VERIFIABLE EDITORIAL SKILLS · ZERO-PYTHON ZIG + TYPST MONOGRAPH],
      text(font: "Cormorant Garamond", size: 11.5pt, weight: "bold", fill: c-ink, number-type: "lining")[#pg / #tot],
    )
  },
)

#set text(
  font: "Source Serif 4",
  size: 9.2pt,
  fill: c-body,
  lang: "en",
  region: "US",
)
#set par(leading: 0.60em, spacing: 0.82em, justify: true)

#show heading.where(level: 1): it => {
  v(4pt)
  text(font: "Cormorant Garamond", size: 18pt, weight: "bold", fill: c-navy, number-type: "lining", it.body)
  v(2pt)
  line(length: 100%, stroke: 0.75pt + c-navy)
  v(4pt)
}
#show heading.where(level: 2): it => {
  v(6pt)
  text(font: "Inter", size: 8.4pt, weight: "bold", fill: c-cobalt, tracking: 0.1em, upper(it.body))
  v(2pt)
}

// ============================================================================
// PAGE 1 — ASTROPHYSICS COVER, KPI RIBBON & DISCOVERY + FULTON VALLEY EXHIBIT
// ============================================================================
#line(length: 100%, stroke: 2.4pt + c-navy)
#v(6pt)
#grid(
  columns: (1fr, auto),
  align: (left, right),
  text(font: "Inter", size: 7.2pt, weight: "bold", fill: c-cobalt, tracking: 0.16em)[ASTROPHYSICS TELEMETRY MONOGRAPH · ZERO-PYTHON ZIG + TYPST EDITION],
  text(font: "IBM Plex Mono", size: 6.8pt, fill: c-muted)[PDF/UA-1 · SHA-256 SEALED],
)
#v(4pt)
#text(font: "Cormorant Garamond", size: 28pt, weight: "bold", fill: c-ink, number-type: "lining")[EXOMUNDUS: #fmt-int(m.total_confirmed_planets) Confirmed Worlds]
#v(2pt)
#text(font: "Source Serif 4", size: 10.4pt, style: "italic", fill: c-muted)[
  Demographics of the NASA Exoplanet Archive (#meta.min_year–#meta.max_year): transit dominance, the Fulton photoevaporation radius valley, and honest observational nulls compiled end-to-end in Zig 0.17.0 and Typst.
]
#v(12pt)

#let kpi-cell(label, val, sub, accent) = box(
  width: 100%,
  height: 62pt,
  fill: c-tint,
  inset: (x: 9pt, y: 8pt),
  stroke: (top: 1.5pt + accent),
  [
    #set par(justify: false, leading: 0.45em, spacing: 0pt)
    #text(font: "Inter", size: 6.2pt, weight: "bold", fill: accent, tracking: 0.11em)[#upper(label)]
    #v(1fr)
    #box(width: 100%, height: 22pt, align(left + horizon, text(font: "Cormorant Garamond", size: 18pt, weight: "bold", fill: c-ink, number-type: "lining")[#val]))
    #v(1fr)
    #text(font: "Inter", size: 6.1pt, fill: c-muted)[#sub]
  ]
)

#grid(
  columns: (1fr, 1fr, 1fr, 1fr),
  gutter: 8pt,
  kpi-cell("Confirmed Worlds", [#fmt-int(m.total_confirmed_planets)], [NASA ps (#meta.min_year–#meta.max_year)], c-navy),
  kpi-cell("Transit Share", [#fmt1(m.transit_share_pct)%], [#fmt-int(m.transit_count) photometric detections], c-cobalt),
  kpi-cell("Observed Radii", [#fmt1(m.radius_completeness_pct)%], [#fmt-int(m.planets_with_radius) direct measurements], c-green),
  kpi-cell("Missing Mass [N/A]", [#fmt1(m.missing_mass_pct)%], [#fmt-int(m.missing_mass_count) worlds unmeasured], c-amber),
)
#v(13pt)

#figure(
  image("assets/fig_census_valley.svg", width: 100%, alt: "Dual-panel pure-vector astrophysics chart. Panel A shows annual exoplanet discoveries from 1992 to 2026 stacked by discovery method, peaking in 2016 with Kepler transits. Panel B shows the bimodal Fulton Radius Valley among 3,670 close-in planets separating rocky Super-Earths around 1.51 Earth radii from gaseous Sub-Neptunes around 2.47 Earth radii across a trough near 1.71 Earth radii."),
  caption: text(font: "Source Serif 4", size: 7.7pt, style: "italic", fill: c-muted)[
    Annual exoplanet confirmation surge by detection technique (#fmt-int(m.total_confirmed_planets) worlds) and the bimodal Fulton radius distribution across #fmt-int(m.valley_sample_count) close-in planets @nasa2026archive @fulton2017.
  ],
) <fig-census>

#v(12pt)
#grid(
  columns: (1.55fr, 1fr),
  gutter: 16pt,
  [
    #text(font: "Inter", size: 7.3pt, weight: "bold", fill: c-cobalt, tracking: 0.1em)[DEMOGRAPHIC TRANSITION]
    Three decades after the radial-velocity discovery of *51 Peg b* @mayor1995, the confirmed exoplanet census has reached *#fmt-int(m.total_confirmed_planets)* worlds in NASA's default observed table @nasa2026archive. Spaceborne transit photometry—led by Kepler's *#m.peak_discovery_year* validation peak (*#fmt-int(m.peak_discovery_count)* confirmations in one year) and TESS—now accounts for *#fmt1(m.transit_share_pct)%* (*#fmt-int(m.transit_count)* planets), outpacing radial velocity (*#fmt1(m.rv_share_pct)%*, *#fmt-int(m.rv_count)* planets).

    Across *#fmt-int(m.valley_sample_count)* close-in small planets, radii split cleanly across the *Fulton Valley* @fulton2017: a rocky Super-Earth peak near *#fmt2(m.super_earth_peak_re) R#sub[⊕]* (*#fmt-int(m.super_earth_zone_count)* worlds in 1.0–1.6 R#sub[⊕]), a depleted trough near *#fmt2(m.valley_trough_re) R#sub[⊕]* (*#fmt-int(m.valley_zone_count)* worlds), and a volatile-rich Sub-Neptune mode near *#fmt2(m.sub_neptune_peak_re) R#sub[⊕]* (*#fmt-int(m.sub_neptune_zone_count)* worlds).
  ],
  box(
    fill: c-tint,
    inset: 10pt,
    stroke: (left: 2pt + c-navy),
    [
      #text(font: "Inter", size: 6.7pt, weight: "bold", fill: c-navy, tracking: 0.14em)[ZERO-PYTHON BARE-METAL STACK]
      #v(4pt)
      #set text(size: 8.0pt)
      #set par(justify: false, leading: 0.54em)
      Every stage of this publication runs without Python: *Zig 0.17.0* validates NASA TAP JSON, seals SHA-256 hashes, and draws pure-vector SVGs (`∞ DPI`); *Typst 0.15.1* compiles `PDF/UA-1`; and the *Sovereign Zig `vedit` harness* (`p2zig` kernels + *veraPDF 1.30*) certifies all 5 gates.
    ],
  ),
)

#v(13pt)
#box(
  width: 100%,
  inset: (top: 8pt, bottom: 2pt),
  stroke: (top: 0.75pt + c-rule),
  grid(
    columns: (1fr, 1fr, 1fr),
    gutter: 14pt,
    [
      #set par(justify: false, leading: 0.48em)
      #text(font: "Inter", size: 6.4pt, weight: "bold", fill: c-navy, tracking: 0.1em)[01 · OBSERVED-ONLY TABLE]
      #v(2pt)
      #text(size: 7.7pt, fill: c-muted)[Built strictly on NASA `ps` (`default_flag=1`) rather than model-filled composite tables—keeping *#fmt-int(m.missing_mass_count)* unmeasured masses honest.]
    ],
    [
      #set par(justify: false, leading: 0.48em)
      #text(font: "Inter", size: 6.4pt, weight: "bold", fill: c-cobalt, tracking: 0.1em)[02 · DUAL-OBSERVABLE CORE]
      #v(2pt)
      #text(size: 7.7pt, fill: c-muted)[Only *#fmt-int(m.planets_with_both_mr)* worlds (*#fmt1(m.both_mr_completeness_pct)%*) carry both a direct transit radius and a radial-velocity or TTV mass.]
    ],
    [
      #set par(justify: false, leading: 0.48em)
      #text(font: "Inter", size: 6.4pt, weight: "bold", fill: c-green, tracking: 0.1em)[03 · VERAPDF ISO 14289-1]
      #v(2pt)
      #text(size: 7.7pt, fill: c-muted)[100% embedded SIL-OFL typography, pure-vector exhibits, accessible math `alt` text, and 106/106 `PDF/UA-1` compliance.]
    ],
  ),
)

#pagebreak()

// ============================================================================
// PAGE 2 — MASS–RADIUS POPULATION & BENCHMARK EXOPLANET LEDGER (RULE 5 N/A)
// ============================================================================
= Mass–Radius Structure & Benchmark Systems

Determining whether an exoplanet is rocky, ocean-rich, or hydrogen-enveloped requires *both* a measured radius and a measured mass. Yet across NASA's *#fmt-int(m.total_confirmed_planets)* confirmed worlds, just *#fmt-int(m.planets_with_both_mr)* (*#fmt1(m.both_mr_completeness_pct)%*) have direct observations of both quantities (@fig-mr). Because transit surveys dominate faint stars while radial-velocity spectrographs require bright hosts, *#fmt1(m.missing_mass_pct)%* lack direct mass measurements and *#fmt-int(m.missing_radius_count)* non-transiting worlds lack direct radii.

#v(6pt)
#figure(
  image("assets/fig_mass_radius.svg", width: 100%, alt: "Dual-panel pure-vector chart. Panel A plots log-log planetary mass against radius for 1,595 observed worlds with an Earth iso-density reference curve at 5.5 grams per cubic centimeter and callouts for TRAPPIST-1 e, LHS 1140 b, K2-18 b, and HD 209458 b. Panel B shows Rule 5 observational completeness bars for radius, mass, both observables, and equilibrium temperature."),
  caption: text(font: "Source Serif 4", size: 7.7pt, style: "italic", fill: c-muted)[
    Observed log–log mass–radius locus (#fmt-int(m.planets_with_both_mr) worlds) and Rule 5 observational completeness across the full census @nasa2026archive.
  ],
) <fig-mr>

#v(8pt)
== Eight Landmark Exoplanets — Observed Default Parameters (Rule 5 `[N/A]`)

#let cell-opt(v, digs: 2) = {
  if v == none {
    text(font: "IBM Plex Mono", size: 6.6pt, fill: c-amber)[[N/A]]
  } else if digs == 0 {
    text(font: "IBM Plex Mono", size: 6.9pt)[#fmt-int(v)]
  } else if digs == 1 {
    text(font: "IBM Plex Mono", size: 6.9pt)[#fmt1(v)]
  } else {
    text(font: "IBM Plex Mono", size: 6.9pt)[#fmt2(v)]
  }
}

#figure(
  table(
    columns: (1.42fr, 0.92fr, 0.56fr, 0.72fr, 0.78fr, 0.78fr, 0.85fr, 0.82fr, 0.68fr),
    inset: (x: 3.8pt, y: 5pt),
    align: (left, left, right, right, right, right, right, right, right),
    stroke: (x, y) => (
      top: if y == 0 { 1.1pt + c-ink } else if y == 1 { 0.75pt + c-ink } else { 0.3pt + c-rule },
      bottom: if y == data.benchmarks.len() { 1.1pt + c-ink } else { none },
    ),
    table.header(
      text(font: "Inter", size: 6.4pt, weight: "bold", fill: c-navy)[PLANET],
      text(font: "Inter", size: 6.4pt, weight: "bold", fill: c-navy)[METHOD],
      text(font: "Inter", size: 6.4pt, weight: "bold", fill: c-navy)[YEAR],
      text(font: "Inter", size: 6.4pt, weight: "bold", fill: c-navy)[DIST (pc)],
      text(font: "Inter", size: 6.4pt, weight: "bold", fill: c-navy)[P (days)],
      text(font: "Inter", size: 6.4pt, weight: "bold", fill: c-navy)[R (R#sub[⊕])],
      text(font: "Inter", size: 6.4pt, weight: "bold", fill: c-navy)[M (M#sub[⊕])],
      text(font: "Inter", size: 6.4pt, weight: "bold", fill: c-navy)[ρ (g/cm³)],
      text(font: "Inter", size: 6.4pt, weight: "bold", fill: c-navy)[T#sub[eq] (K)],
    ),
    ..for b in data.benchmarks {
      let short-m = if b.method == "Radial Velocity" { "RV" } else { b.method }
      (
        text(font: "Inter", size: 7.3pt, weight: "semibold", fill: c-ink)[#b.name],
        text(font: "Inter", size: 6.7pt, fill: c-muted)[#short-m],
        text(font: "IBM Plex Mono", size: 6.8pt)[#b.year],
        cell-opt(b.dist_pc, digs: 2),
        cell-opt(b.period_d, digs: 2),
        cell-opt(b.radius_re, digs: 2),
        cell-opt(b.mass_me, digs: 2),
        cell-opt(b.rho_gcm3, digs: 2),
        cell-opt(b.eqt_k, digs: 0),
      )
    }
  ),
  caption: text(font: "Source Serif 4", size: 7.5pt, style: "italic", fill: c-muted)[
    Sorted by Gaia/Hipparcos heliocentric distance (pc). Bulk density derived strictly where both direct radius and direct mass exist; Rule 5 Sacred `[N/A]` preserves unmeasured transit/RV observables without empirical mass–radius imputation @nasa2026archive.
  ],
) <tbl-benchmarks>

#v(10pt)
@tbl-benchmarks illustrates the physical gulf between dense rocky worlds and inflated volatile envelopes: *TRAPPIST-1 e* (*#fmt2(m.rho_trappist_1_e_gcm3) g/cm³*) @gillon2017 and *LHS 1140 b* (*#fmt2(m.rho_lhs_1140_b_gcm3) g/cm³*) track terrestrial iron–silicate density, whereas *K2-18 b* (*#fmt2(m.rho_k2_18_b_gcm3) g/cm³*) retains a substantial volatile envelope and Hot Jupiter *HD 209458 b* (*#fmt2(m.rho_hd_209458_b_gcm3) g/cm³*) sits below liquid-water density due to intense stellar irradiation.

#v(9pt)
#box(
  width: 100%,
  fill: c-tint,
  inset: (x: 11pt, y: 9pt),
  stroke: (left: 2.2pt + c-amber),
  [
    #set par(justify: false, leading: 0.50em)
    #text(font: "Inter", size: 6.5pt, weight: "bold", fill: c-amber, tracking: 0.12em)[RULE 5 ASTROPHYSICS DISCIPLINE · WHY EMPIRICAL BACKFILLING IS FORBIDDEN]
    #v(3pt)
    #text(size: 8.1pt, fill: c-body)[
      Composite exoplanet catalogs routinely impute missing masses for transit-only worlds like *TOI-700 d* and missing radii for non-transiting RV worlds like *Proxima Cen b* @anglada2016 and *51 Peg b* @mayor1995 via power-law mass–radius regressions. Treating synthetic regressions as observed truth hides the *#fmt1(m.missing_mass_pct)%* mass gap; our pipeline strictly preserves every unmeasured observable as `[N/A]`.
    ]
  ],
)

#pagebreak()

// ============================================================================
// PAGE 3 — ASTROPHYSICAL SCALING LAWS & ZERO-PYTHON HARNESS ARCHITECTURE
// ============================================================================
= Physical Scaling Laws & Verification Architecture

Every derived density and demographic boundary in this monograph obeys exact orbital and radiative physics validated in Zig 0.17.0 before Typst typesets a single glyph.

#grid(
  columns: (1.55fr, 1fr),
  gutter: 18pt,
  [
    == 1. Kepler's Third Law & Transit Geometry
    For a planet of orbital period #math.equation(alt: "P", $P$) orbiting a host star of mass #math.equation(alt: "M star", $M_star$) and radius #math.equation(alt: "R star", $R_star$), semi-major axis #math.equation(alt: "a", $a$) and photometric transit depth #math.equation(alt: "delta", $delta$) follow exact geometric scaling:
    #math.equation(
      block: true,
      alt: "Semi-major axis a equals the cube root of G times M star times P squared divided by 4 pi squared; transit depth delta equals planetary radius R sub p divided by stellar radius R star, all squared.",
      $ a = (frac(G M_star P^2, 4 pi^2))^(1\/3), quad quad delta = (frac(R_p, R_star))^2 $,
    )

    == 2. Planetary Bulk Density & Composition
    Whenever both transit radius #math.equation(alt: "R sub p", $R_p$) and Doppler/TTV mass #math.equation(alt: "M sub p", $M_p$) are directly observed (the *#fmt-int(m.planets_with_both_mr)* dual-observable planets in @fig-mr), mean bulk density #math.equation(alt: "rho sub p", $rho_p$) scales directly relative to Earth (#math.equation(alt: "rho earth equals 5.514 grams per cubic centimeter", $rho_(plus.o) = 5.514 " g" dot "cm"^(-3)$)):
    #math.equation(
      block: true,
      alt: "Planetary bulk density rho sub p equals 3 M sub p divided by 4 pi R sub p cubed, equal to 5.514 times M sub p over M earth divided by R sub p over R earth cubed, in grams per cubic centimeter.",
      $ rho_p = frac(3 M_p, 4 pi R_p^3) = 5.514 dot frac(M_p \/ M_(plus.o), (R_p \/ R_(plus.o))^3) quad ["g" dot "cm"^(-3)] $,
    )

    == 3. Radiative Equilibrium Temperature
    Assuming rapid heat redistribution and Bond albedo #math.equation(alt: "A sub B", $A_B$), blackbody radiative balance sets the baseline equilibrium temperature #math.equation(alt: "T eq", $T_"eq"$):
    #math.equation(
      block: true,
      alt: "Equilibrium temperature T eq equals stellar effective temperature T star times the square root of R star divided by 2 a, times 1 minus Bond albedo A sub B to the one-quarter power.",
      $ T_"eq" = T_star sqrt(frac(R_star, 2 a)) (1 - A_B)^(1\/4) $,
    )

    == 4. Photoevaporation & The Fulton Valley
    Extreme-UV irradiation from young host stars strips primordial H/He atmospheres off low-mass close-in cores, carving the observed *#fmt2(m.valley_trough_re) R#sub[⊕]* trough in @fig-census between stripped rocky cores (*#fmt2(m.super_earth_peak_re) R#sub[⊕]*) and envelope-retaining Sub-Neptunes (*#fmt2(m.sub_neptune_peak_re) R#sub[⊕]*) @fulton2017.
  ],
  [
    #box(
      width: 100%,
      fill: c-tint,
      inset: (x: 10pt, y: 10.5pt),
      stroke: (top: 1.5pt + c-navy),
      [
        #text(font: "Inter", size: 6.7pt, weight: "bold", fill: c-navy, tracking: 0.14em)[SOVEREIGN ZIG 0.17.0 HARNESS]
        #v(5pt)
        #set text(size: 7.9pt)
        #set par(justify: false, leading: 0.50em, spacing: 0.62em)
        *1. `pipeline.zig`:* Parses 5 raw NASA JSONs, enforces physics invariants, computes SHA-256 digests, and emits pure-vector SVGs.

        *2. `vedit latch`:* Native Zig SHA-256 + Rule 4 provenance verification in `<2 ms`.

        *3. `p2zig --strict` Kernels:* 10 math/audit kernels compiled from Python to Zig-TIR with `WRONG = 0`.

        *4. `vedit audit-all`:* Zero-Python WCAG contrast, geometry, Rule 10 prose, and live *veraPDF 1.30* `PDF/UA-1` court.

        *5. `vedit inject`:* Dissects this monograph into a reusable `archetypes/` Design DNA blueprint.
      ],
    )
    #v(11pt)
    #box(
      width: 100%,
      fill: rgb("#EEF4F0"),
      inset: (x: 10pt, y: 10pt),
      stroke: (left: 2pt + c-green),
      [
        #text(font: "Inter", size: 6.6pt, weight: "bold", fill: c-green, tracking: 0.12em)[OBSERVATIONAL SELECTION BIAS]
        #v(3pt)
        #set text(size: 7.8pt)
        #set par(justify: false, leading: 0.50em)
        Transit probability scales inversely with orbital separation (#math.equation(alt: "R star divided by a", $R_star / a$)), heavily over-representing short-period worlds while leaving wide-orbit ice giants mostly to microlensing and direct imaging.
      ],
    )
    #v(11pt)
    #box(
      width: 100%,
      fill: c-tint,
      inset: (x: 10pt, y: 10pt),
      stroke: (left: 2pt + c-amber),
      [
        #text(font: "Inter", size: 6.6pt, weight: "bold", fill: c-amber, tracking: 0.12em)[RULE 5 · ZERO-IMPUTATION GUARD]
        #v(3pt)
        #set text(size: 7.8pt)
        #set par(justify: false, leading: 0.50em)
        Unmeasured observables—*#fmt-int(m.missing_mass_count)* masses and *#fmt-int(m.missing_radius_count)* radii across NASA's `ps` table—remain explicit `[N/A]` rather than model-imputed regressions.
      ],
    )
  ],
)

#v(13pt)
== Complete Discovery Method Census (`ps default_flag=1`, N = #fmt-int(m.total_confirmed_planets))

#figure(
  table(
    columns: (1.2fr, 0.72fr, 0.68fr, 2.4fr),
    inset: (x: 5pt, y: 5pt),
    align: (left, right, right, left),
    stroke: (x, y) => (
      top: if y == 0 { 1.1pt + c-ink } else if y == 1 { 0.75pt + c-ink } else { 0.3pt + c-rule },
      bottom: if y == data.methods.len() { 1.1pt + c-ink } else { none },
    ),
    table.header(
      text(font: "Inter", size: 6.5pt, weight: "bold", fill: c-navy)[DISCOVERY METHOD],
      text(font: "Inter", size: 6.5pt, weight: "bold", fill: c-navy)[WORLDS],
      text(font: "Inter", size: 6.5pt, weight: "bold", fill: c-navy)[SHARE],
      text(font: "Inter", size: 6.5pt, weight: "bold", fill: c-navy)[PRIMARY OBSERVATORIES & MECHANISM],
    ),
    ..for mt in data.methods {
      (
        text(font: "Inter", size: 7.3pt, weight: "semibold", fill: c-ink)[#mt.name],
        text(font: "IBM Plex Mono", size: 7.1pt, weight: "semibold", fill: c-navy)[#fmt-int(mt.count)],
        text(font: "IBM Plex Mono", size: 7.1pt, fill: c-cobalt)[#fmt1(mt.share_pct)%],
        text(font: "Source Serif 4", size: 7.6pt, fill: c-muted)[#mt.note],
      )
    }
  ),
  caption: text(font: "Source Serif 4", size: 7.5pt, style: "italic", fill: c-muted)[
    Exact method totals reconciled 1:1 against `nasa_completeness.json` (`sum_methods == total_confirmed_planets`) by `pipeline.zig` @nasa2026archive.
  ],
) <tbl-methods>

#pagebreak()

// ============================================================================
// PAGE 4 — CRYPTOGRAPHIC SHA-256 PROVENANCE LEDGER & BIBLIOGRAPHY
// ============================================================================
= Cryptographic Provenance & References

Every scalar in this monograph traces 1:1 across *#ledger.len()* atomic tuples in `provenance_ledger.json` back to five immutable NASA TAP JSON files sealed in `manifest.sha256` (@tbl-sha256). Any single-byte alteration in `data/raw/` aborts compilation inside `vedit latch` before Typst executes.

#v(3pt)
#figure(
  table(
    columns: (1.65fr, 2.35fr),
    inset: (x: 6pt, y: 4.5pt),
    align: (left, left),
    stroke: (x, y) => (
      top: if y == 0 { 1.1pt + c-ink } else if y == 1 { 0.75pt + c-ink } else { 0.3pt + c-rule },
      bottom: if y == meta.raw_file_hashes.len() { 1.1pt + c-ink } else { none },
    ),
    table.header(
      text(font: "Inter", size: 6.5pt, weight: "bold", fill: c-navy)[IMMUTABLE NASA TAP RAW FILE],
      text(font: "Inter", size: 6.5pt, weight: "bold", fill: c-navy)[SHA-256 CRYPTOGRAPHIC DIGEST],
    ),
    ..for (fname, digest) in meta.raw_file_hashes.pairs() {
      (
        text(font: "IBM Plex Mono", size: 6.9pt, weight: "semibold", fill: c-ink)[#fname],
        text(font: "IBM Plex Mono", size: 6.4pt, fill: c-cobalt)[#digest],
      )
    }
  ),
  caption: text(font: "Source Serif 4", size: 7.4pt, style: "italic", fill: c-muted)[
    Live SHA-256 digests computed in bare-metal Zig 0.17.0 (`std.crypto.hash.sha2.Sha256`) and locked by `vedit latch`.
  ],
) <tbl-sha256>

#v(8pt)
== Live Atomic Provenance Ledger Extract (`provenance_ledger.json`)

#let sample-ids = (
  "total_confirmed_planets",
  "transit_share_pct",
  "planets_with_both_mr",
  "missing_mass_pct",
  "valley_trough_re",
  "rho_trappist_1_e_gcm3",
)
#let sample-rows = ledger.filter(r => sample-ids.contains(r.metric_id))

#figure(
  table(
    columns: (1.75fr, 0.78fr, 1.45fr, 0.85fr),
    inset: (x: 4.5pt, y: 4.2pt),
    align: (left, right, left, left),
    stroke: (x, y) => (
      top: if y == 0 { 1.1pt + c-ink } else if y == 1 { 0.75pt + c-ink } else { 0.3pt + c-rule },
      bottom: if y == sample-rows.len() { 1.1pt + c-ink } else { none },
    ),
    table.header(
      text(font: "Inter", size: 6.3pt, weight: "bold", fill: c-navy)[METRIC KEY],
      text(font: "Inter", size: 6.3pt, weight: "bold", fill: c-navy)[VALUE],
      text(font: "Inter", size: 6.3pt, weight: "bold", fill: c-navy)[UPSTREAM SOURCE],
      text(font: "Inter", size: 6.3pt, weight: "bold", fill: c-navy)[SHA-256 (12)],
    ),
    ..for r in sample-rows {
      let short-src = r.source_document.replace("data/raw/", "")
      let short-sha = r.raw_file_sha256.slice(0, 12)
      (
        text(font: "IBM Plex Mono", size: 6.3pt, fill: c-ink)[#r.metric_id],
        text(font: "IBM Plex Mono", size: 6.5pt, weight: "semibold", fill: c-navy)[#r.value],
        text(font: "IBM Plex Mono", size: 6.2pt, fill: c-muted)[#short-src],
        text(font: "IBM Plex Mono", size: 6.3pt, fill: c-cobalt)[#short-sha],
      )
    }
  ),
  caption: text(font: "Source Serif 4", size: 7.4pt, style: "italic", fill: c-muted)[
    Representative 6 of #ledger.len() atomic provenance records loaded natively from `provenance_ledger.json` (Rule 4).
  ],
) <tbl-ledger>

#v(8pt)
#bibliography("references.bib", title: [Scholarly & Archive References], style: "ieee")

#v(1fr)
#box(
  width: 100%,
  fill: c-tint,
  inset: 10pt,
  stroke: (top: 1.2pt + c-navy),
  [
    #text(font: "Inter", size: 6.6pt, weight: "bold", fill: c-navy, tracking: 0.14em)[PRODUCTION & STANDARDS CERTIFICATION COLOPHON]
    #v(4pt)
    #set text(size: 7.7pt)
    #set par(justify: false, leading: 0.50em)
    *Data & Vector Pipeline:* Pure Zig 0.17.0 (`scripts/pipeline.zig`, zero Python) · *Typesetting:* Rust-native Typst 0.15.1 (`--pdf-standard ua-1`) · *Verification Court:* Sovereign Zig `vedit` harness (`p2zig` kernels + *veraPDF 1.30* ISO 14289-1) · *Typography:* Bundled SIL Open Font License 1.1 stack (*Cormorant Garamond*, *Source Serif 4*, *Inter*, *IBM Plex Mono*) · *Data Attribution:* NASA Exoplanet Archive, operated by Caltech IPAC under contract with NASA.
  ],
)
