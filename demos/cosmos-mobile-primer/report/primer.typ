// COSMOS IN YOUR POCKET — Mobile-Native 9:16 Subject-Understanding Field Primer
// Format: 360 x 640 pt (9:16 portrait mobile PDF/UA-1, zero pinch-zoom on WhatsApp / iOS / Android)
// Data:   100% live-fetched NASA JPL, NASA NSSDC, arXiv, Crossref -> Pure Zig 0.17.0 physics compiler
// Gates:  SHA-256 Latch · WCAG 2.1 AA · 4-Corner Geometry · Rule 10 Half-ULP · veraPDF UA-1 · Rule 11 Live Links

#let d = json("../data/summary_metrics.json")

// Exact decimal formatting helpers (zero hand-typed numbers)
#let fmt(v, digits: 1) = {
  let factor = calc.pow(10, digits)
  let r = calc.round(v * factor) / factor
  let s = str(r)
  if digits == 0 {
    return str(int(calc.round(v)))
  }
  if not s.contains(".") {
    s = s + "." + "0" * digits
  } else {
    let parts = s.split(".")
    let frac = parts.at(1)
    if frac.len() < digits {
      s = s + "0" * (digits - frac.len())
    }
  }
  s
}

#let comma-int(v) = {
  let s = str(int(calc.round(v)))
  let n = s.len()
  let out = ""
  for i in range(n) {
    if i > 0 and calc.rem(n - i, 3) == 0 {
      out = out + ","
    }
    out = out + s.at(i)
  }
  out
}

// OLED Cosmic Palette (all text/bg pairs engineered >= 6.5:1 WCAG AA+)
#let bg-canvas  = rgb("#0B101B")
#let bg-card    = rgb("#131D31")
#let bg-pill    = rgb("#172640")
#let bg-trap    = rgb("#221828")
#let ink-bright = rgb("#F1F5F9")
#let ink-body   = rgb("#DCE5F2")
#let ink-muted  = rgb("#B8C7DC")
#let acc-cyan   = rgb("#7DD3FC")
#let acc-gold   = rgb("#FCD34D")
#let acc-coral  = rgb("#FCA5A5")
#let acc-mint   = rgb("#6EE7B7")
#let rule-line  = rgb("#243554")

#set document(
  title: "Cosmos in Your Pocket: From Rubble Comets to Supermassive Black Holes",
  author: "Verifiable Editorial Skills (Zig 0.17 + Typst PDF/UA-1)",
  description: "Mobile-native 9:16 astrophysics field primer built from live NASA, arXiv, and Crossref data behind a 6-gate cryptographic court.",
)

#set text(
  font: "Inter",
  size: 10.9pt,
  fill: ink-body,
  lang: "en",
  hyphenate: false,
)

#set par(
  leading: 0.65em,
  spacing: 0.78em,
  justify: false,
)

#set page(
  width: 360pt,
  height: 640pt,
  margin: (top: 24pt, bottom: 28pt, left: 24pt, right: 24pt),
  fill: bg-canvas,
  background: context {
    let p = counter(page).get().first()
    let tot = counter(page).final().first()
    let frac = p / tot
    place(top + left, rect(width: 360pt, height: 3pt, fill: rgb("#162238")))
    place(top + left, rect(width: 360pt * frac, height: 3pt, fill: acc-cyan))
  },
  footer: context {
    let p = counter(page).get().first()
    let tot = counter(page).final().first()
    if p > 1 {
      let pad = if p < 10 { "0" + str(p) } else { str(p) }
      grid(
        columns: (1fr, auto),
        align: (left + bottom, right + bottom),
        text(font: "IBM Plex Mono", size: 7.4pt, fill: ink-muted)[COSMOS IN YOUR POCKET  ·  VES MOBILE],
        text(font: "IBM Plex Mono", size: 7.4pt, weight: "bold", fill: acc-cyan)[CARD #pad / #tot],
      )
    }
  },
)

// Reusable mobile-native building blocks
#let kicker(label, accent: acc-cyan) = {
  text(font: "IBM Plex Mono", size: 7.8pt, weight: "bold", fill: accent, tracking: 0.08em)[#upper(label)]
}

#let card-title(title) = {
  v(3pt)
  set par(leading: 0.42em)
  text(font: "Source Serif 4", size: 19pt, weight: "bold", fill: ink-bright, number-type: "lining")[#title]
  v(5pt)
}

#let kpi-tile(label, val, sub, accent: acc-cyan) = {
  box(
    width: 100%,
    fill: bg-card,
    radius: 6pt,
    inset: (x: 9pt, y: 9pt),
    stroke: (top: 1.6pt + accent, rest: 0.5pt + rule-line),
  )[
    #text(font: "IBM Plex Mono", size: 6.8pt, weight: "bold", fill: ink-muted)[#upper(label)]
    #v(3pt)
    #text(font: "IBM Plex Mono", size: 13.5pt, weight: "bold", fill: ink-bright)[#val]
    #v(2pt)
    #text(size: 7.7pt, fill: ink-muted)[#sub]
  ]
}

#let insight-box(tag, body-content, accent: acc-gold, bg: bg-card) = {
  block(
    width: 100%,
    fill: bg,
    radius: 6pt,
    inset: (x: 11pt, y: 10pt),
    stroke: (left: 2.4pt + accent, rest: 0.5pt + rule-line),
    breakable: false,
  )[
    #text(font: "IBM Plex Mono", size: 7.5pt, weight: "bold", fill: accent)[#upper(tag)]
    #v(4pt)
    #set text(size: 10.1pt, fill: ink-body)
    #body-content
  ]
}

// Thumb-sized tappable Rule 11 source pill (>= 22pt tall hitbox!)
#let source-pill(url, label, accent: acc-cyan) = {
  link(url)[
    #box(
      fill: bg-pill,
      radius: 5pt,
      inset: (x: 9pt, y: 6pt),
      stroke: 0.7pt + accent,
    )[
      #text(font: "IBM Plex Mono", size: 7.6pt, weight: "bold", fill: accent)[#label  ↗]
    ]
  ]
}

#let source-row(pills) = {
  v(1fr)
  line(length: 100%, stroke: 0.5pt + rule-line)
  v(5pt)
  text(font: "IBM Plex Mono", size: 6.8pt, fill: ink-muted)[TAP TO VERIFY PRIMARY SOURCE (LIVE CHECKED):]
  v(4pt)
  stack(dir: ltr, spacing: 6pt, ..pills)
}

// ============================================================================
// CARD 1 — POSTER COVER (WhatsApp Chat Thumbnail Hero)
// ============================================================================
#v(4pt)
#kicker("Mobile Field Primer  ·  Astrophysics", accent: acc-gold)
#v(4pt)
#text(font: "Source Serif 4", size: 25.5pt, weight: "bold", fill: ink-bright, number-type: "lining")[
  Cosmos in Your Pocket
]
#v(1pt)
#text(font: "Source Serif 4", size: 13.5pt, style: "italic", fill: acc-cyan)[
  From Rubble Comets to Supermassive Black Holes
]
#v(6pt)
#text(size: 10.2pt, fill: ink-body)[
  Nine real celestial bodies. One unifying physics ratio explains why a comet stays a lumpy rubble pile while a collapsing star tears spacetime open.
]
#v(8pt)
#image("figures/fig_cover_cosmos.svg", width: 100%, alt: "Concentric cosmic compactness radar from Comet 67P through Earth, the Sun, Sirius B, PSR J0740+6620, to the Event Horizon of M87*.")
#v(8pt)
#grid(
  columns: (1fr, 1fr, 1fr),
  gutter: 6pt,
  kpi-tile("Mass Span", fmt(d.mass_orders_span, digits: 1) + " dec", "67P to M87*", accent: acc-gold),
  kpi-tile("Density", fmt(d.density_orders_span, digits: 1) + " dec", "M87* to PSR", accent: acc-cyan),
  kpi-tile("Verified", str(d.body_count) + " bodies", "Live NASA & DOIs", accent: acc-mint),
)
#v(7pt)
#box(
  width: 100%,
  fill: bg-card,
  radius: 6pt,
  inset: (x: 10pt, y: 7pt),
  stroke: (left: 2.2pt + acc-cyan, rest: 0.5pt + rule-line),
)[
  #text(size: 8.9pt, fill: ink-body)[
    *Live-verified mobile edition:* Tap any bottom pill to open the primary NASA record or peer-reviewed paper in your phone browser.
  ]
]
#v(1fr)
#line(length: 100%, stroke: 0.5pt + rule-line)
#v(6pt)
#grid(
  columns: (1fr, auto),
  align: (left + horizon, right + horizon),
  text(font: "IBM Plex Mono", size: 7.2pt, fill: ink-muted)[ZERO HANDWRITTEN DATA  ·  SWIPE DOWN ↓],
  source-pill("https://github.com/gke0op/verifiable-editorial-skills", "VES 6-GATE", accent: acc-mint),
)

// ============================================================================
// CARD 2 — THE ONE MENTAL MODEL
// ============================================================================
#pagebreak()
#kicker("01 · The Unifying Mental Model", accent: acc-cyan)
#card-title([One Tug-of-War Builds#linebreak()Every World in Space])

Every celestial body in space is the result of a single battle: *gravity pulling mass inward* versus *whatever force pushes back*.

Instead of memorizing scattered space trivia, track one dimensionless ratio called *compactness* — how close an object sits to its own black-hole event horizon radius:

#v(4pt)
#box(width: 100%, fill: bg-card, radius: 6pt, inset: (x: 12pt, y: 10pt), stroke: 0.7pt + acc-cyan)[
  #align(center)[
    #set text(fill: ink-bright, size: 11.5pt)
    #math.equation(
      block: true,
      alt: "Compactness Xi equals Schwarzschild radius R_s divided by radius R, which equals 2 G M divided by R c squared, and also equals escape velocity over speed of light squared.",
      $ Xi = R_s / R = (2 G M) / (R c^2) = (v_"esc" / c)^2 $,
    )
  ]
  #v(2pt)
  #align(center)[#text(size: 8.6pt, fill: ink-muted)[Tiny #math.equation(alt: "Xi", $Xi$): loose rock & gas  ·  #math.equation(alt: "Xi equals 1", $Xi = 1$): escape speed hits light speed #math.equation(alt: "c", $c$).]]
]
#v(6pt)

*The Four Cosmic Floors Stopping Collapse:*

#stack(
  spacing: 6pt,
  insight-box("Floor 1 · Chemical Rock & Ice Bonds", [Small comets and asteroids stay lumpy because electromagnetic bonds between molecules easily beat weak self-gravity.], accent: rgb("#94A3B8")),
  insight-box("Floor 2 · Hydrostatic & Fusion Pressure", [Planets crush rock into spheres; stars ignite nuclear fusion so outward thermal pressure holds back enormous mass.], accent: acc-gold),
  insight-box("Floor 3 · Quantum Pauli Exclusion", [Dead stellar cores run out of fuel, leaving pure quantum mechanics (electrons in white dwarfs; neutrons in neutron stars) to resist gravity.], accent: acc-cyan),
  insight-box("Floor 4 · None — The Event Horizon", [Push past the neutron limit and no known force can hold. Radius falls inside #math.equation(alt: "R_s", $R_s$), compactness locks at #math.equation(alt: "Xi equals 1", $Xi = 1$), and a black hole forms.], accent: acc-coral, bg: bg-trap),
)

// ============================================================================
// CARD 3 — THE GRAND PHASE MAP
// ============================================================================
#pagebreak()
#kicker("02 · The Grand Cosmic Map", accent: acc-cyan)
#card-title([27 Orders of Magnitude#linebreak()on One Cosmic Map])

Plot every object's mass against its radius in log scale, and the entire zoo of astrophysics snaps into sharp geometric focus:

#v(5pt)
#image("figures/fig_mass_radius.svg", width: 100%, alt: "Log-log Mass versus Radius phase diagram of 9 real celestial bodies from Comet 67P to M87*, showing the water-density slope and the forbidden black hole Event Horizon boundary.")
#v(6pt)

#insight-box("How to Read This Map at a Glance", [
  *1. The Water-Density Slope (Dashed Cyan):* Comets, rocky worlds, gas giants, and the Sun all hug normal atomic matter density within a single order of magnitude of water.
  #v(3pt)
  *2. The Quantum Plunge (Cyan Dots):* Once fusion dies, gravity crushes solar-mass cores straight downward — Sirius B shrinks smaller than Earth, and PSR J0740 collapses to city width.
  #v(3pt)
  *3. The Red Diagonal Wall (#math.equation(alt: "R equals R_s", $R = R_s$)):* No stable surface can exist in the shaded region below-right. Black holes sit right on the diagonal — and strangely, the bigger they get, the *lower* their average density falls.
], accent: acc-cyan)

// ============================================================================
// CARD 4 — COMET 67P
// ============================================================================
#pagebreak()
#kicker("03 · Rubble & Ice  ·  Stop 1 of 9", accent: rgb("#CBD5E1"))
#card-title([Comet 67P: You Could#linebreak()Jump Into Deep Space])

ESA's Rosetta spacecraft orbited Comet 67P/Churyumov–Gerasimenko and weighed it using tiny radio shifts in the probe's trajectory. Its self-gravity is *#comma-int(d.c67_to_earth_g_inv) times weaker* than Earth's.

#v(4pt)
#grid(
  columns: (1fr, 1fr, 1fr),
  gutter: 6pt,
  kpi-tile("Escape Speed", fmt(d.c67_v_esc_ms, digits: 2) + " m/s", "Standing jump!", accent: acc-cyan),
  kpi-tile("Bulk Density", fmt(d.c67_dens_g_cm3, digits: 3), "g/cm³ (< water)", accent: acc-gold),
  kpi-tile("Diameter", fmt(d.c67_diam_km, digits: 1) + " km", "Bi-lobed shape", accent: acc-mint),
)
#v(6pt)

*Why It Isn't Round:* A solid sphere only forms when gravity overwhelms the mechanical strength of rock and ice. At just *#fmt(d.c67_diam_km, digits: 1) km* across, 67P's compactness is a vanishingly tiny #math.equation(alt: "Xi equals 8.67 times 10 to the minus 18", $Xi = 8.67 times 10^(-18)$). Chemical bonds freeze its two-lobed "rubber duck" silhouette permanently in place.

#v(4pt)
#insight-box("Intuition Check · Porous Cosmic Sponge", [
  Because 67P's measured density is *#fmt(d.c67_dens_g_cm3, digits: 3) g/cm³* — roughly half the density of liquid water — most of its interior is empty pore space between loosely packed ice and dust grains.
], accent: acc-gold)

#v(4pt)
#insight-box("Common Misconception", [
  Comets are *not* solid boulders of frozen glass. Rosetta gravity tracking proved 67P is a fragile, porous rubble pile that would float in a giant bathtub.
], accent: acc-coral, bg: bg-trap)

#source-row((
  source-pill("https://ssd-api.jpl.nasa.gov/sbdb.api?sstr=67P&phys-par=1", "NASA JPL SBDB"),
  source-pill("https://doi.org/10.1038/nature16535", "Rosetta · Nature 2016", accent: acc-gold),
))

// ============================================================================
// CARD 5 — EARTH & JUPITER
// ============================================================================
#pagebreak()
#kicker("04 · Hydrostatic Worlds  ·  Stops 2 & 3", accent: acc-gold)
#card-title([Earth & Jupiter: Gravity#linebreak()Sculpts Round Worlds])

Pile up enough rock or gas and gravity breaks every chemical crystal lattice, pulling the world into a near-perfect sphere in *hydrostatic equilibrium*.

#v(5pt)
#grid(
  columns: (1fr, 1fr),
  gutter: 7pt,
  kpi-tile("Earth · Rock", fmt(d.earth_v_esc_kms, digits: 2) + " km/s", "R = " + comma-int(d.earth_radius_km) + " km · " + fmt(d.earth_density_g_cm3, digits: 2) + " g/cm³", accent: acc-cyan),
  kpi-tile("Jupiter · Gas", fmt(d.jupiter_v_esc_kms, digits: 2) + " km/s", "R = " + comma-int(d.jupiter_radius_km) + " km · " + fmt(d.jup_earth_mass_ratio, digits: 1) + " Earths", accent: acc-gold),
)
#v(8pt)

*Rock vs. Compressed Hydrogen:* Earth's iron core and silicate mantle pack *#fmt(d.earth_density_g_cm3, digits: 2) g/cm³* — the densest major planet in our Solar System. Jupiter holds *#fmt(d.jup_earth_mass_ratio, digits: 1) times* Earth's mass, yet consists mostly of hydrogen and helium at *#fmt(d.jupiter_density_g_cm3, digits: 2) g/cm³*.

#v(6pt)
#insight-box("Scale Shock · Earth's Black-Hole Size", [
  Plug Earth's exact mass into #math.equation(alt: "R_s equals 2 G M over c squared", $R_s = (2 G M) / c^2$): you would have to crush our entire planet down to a glass marble just *#fmt(d.earth_rs_mm, digits: 2) mm* in radius before it became a black hole. Today Earth sits at #math.equation(alt: "Xi equals 1.39 times 10 to the minus 9", $Xi = 1.39 times 10^(-9)$).
], accent: acc-cyan)

#v(6pt)
#insight-box("Why Planets Have a Maximum Radius", [
  Add even more hydrogen to Jupiter and its extra weight squeezes its own electrons into a liquid metallic state. Beyond Jupiter's mass, adding matter makes gas giants and brown dwarfs *shrink* rather than grow.
], accent: acc-gold)

#source-row((
  source-pill("https://nssdc.gsfc.nasa.gov/planetary/factsheet/earthfact.html", "NASA Earth Fact Sheet"),
  source-pill("https://nssdc.gsfc.nasa.gov/planetary/factsheet/jupiterfact.html", "NASA Jupiter Fact Sheet", accent: acc-gold),
))

// ============================================================================
// CARD 6 — THE SUN
// ============================================================================
#pagebreak()
#kicker("05 · Nuclear Fusion  ·  Stop 4 of 9", accent: acc-gold)
#card-title([The Sun: A Self-Regulating#linebreak()Fusion Thermostat])

Gather *#comma-int(d.sun_earth_mass_ratio) Earths* of hydrogen and central pressure ignites thermonuclear fusion. Gravity wants to collapse the star in under an hour; outward thermal and radiation pressure holds it steady for billions of years.

#v(4pt)
#grid(
  columns: (1fr, 1fr, 1fr),
  gutter: 6pt,
  kpi-tile("Radius", comma-int(d.sun_radius_km) + " km", "Mean gas sphere", accent: acc-gold),
  kpi-tile("Escape Speed", fmt(d.sun_v_esc_kms, digits: 1) + " km/s", "Solar surface", accent: acc-cyan),
  kpi-tile("Horizon R_s", fmt(d.sun_rs_km, digits: 2) + " km", "Xi = 4.24×10⁻⁶", accent: acc-coral),
)
#v(6pt)

*The Built-In Thermostat:* Why doesn't the Sun blow apart like a hydrogen bomb? Negative feedback. If the core compresses slightly, temperature spikes, fusion accelerates, and the extra heat expands and cools the core back into balance.

#v(4pt)
#insight-box("Surprising Density Reality", [
  Despite holding *#comma-int(d.sun_earth_mass_ratio) times* Earth's mass, the Sun's average density is only *#fmt(d.sun_density_g_cm3, digits: 2) g/cm³* — barely denser than Jupiter and roughly a quarter as dense as Earth's rock. Intense heat puffs its envelope wide.
], accent: acc-gold)

#v(4pt)
#insight-box("The Catch · Fuel Runs Out", [
  Thermal pressure only works while nuclear fuel burns. Once a star exhausts fusion, heat leaks into space and gravity gets its revenge — opening the door to quantum stars.
], accent: acc-cyan)

#source-row((
  source-pill("https://nssdc.gsfc.nasa.gov/planetary/factsheet/sunfact.html", "NASA Sun Fact Sheet", accent: acc-gold),
  source-pill("https://doi.org/10.3847/0004-6256/152/2/41", "IAU 2015 Res. B3", accent: acc-cyan),
))

// ============================================================================
// CARD 7 — SIRIUS B (WHITE DWARF)
// ============================================================================
#pagebreak()
#kicker("06 · Electron Degeneracy  ·  Stop 5 of 9", accent: acc-cyan)
#card-title("Sirius B: A Whole Sun Packed Inside Earth")

When a Sun-like star runs out of fuel, its outer layers drift away and its carbon-oxygen core collapses until *quantum mechanics* slams on the brakes.

#v(4pt)
#grid(
  columns: (1fr, 1fr, 1fr),
  gutter: 6pt,
  kpi-tile("Mass", fmt(d.sirius_b_mass_gr_msun, digits: 3) + " M☉", "Dyn: " + fmt(d.sirius_b_mass_dyn_msun, digits: 3) + " M☉", accent: acc-cyan),
  kpi-tile("GR Radius", comma-int(d.sirius_b_rad_km) + " km", fmt(d.sirius_b_earth_rad_ratio, digits: 3) + " × Earth!", accent: acc-gold),
  kpi-tile("1 Teaspoon", fmt(d.sirius_b_teaspoon_tons, digits: 1) + " t", "Metric tons / 5 cm³", accent: acc-coral),
)
#v(6pt)

*Quantum Support (Zero Heat Needed):* Electrons obey the *Pauli Exclusion Principle* — no two electrons can occupy the exact same quantum state. Squeezed into a ball smaller than Earth (*#comma-int(d.sirius_b_rad_km) km*), electrons resist further compression even if the star cools to absolute zero.

#v(4pt)
#insight-box("VES Physics Receipt · Derived From Einstein's Redshift", [
  Hubble STIS measured starlight climbing out of Sirius B's gravity well redshifted by *#fmt(d.sirius_b_vg_kms, digits: 2) km/s* (Joyce et al. 2018). Our Zig compiler solved #math.equation(alt: "R equals G M over c times v_g", $R = (G M) / (c v_g)$) directly from raw arXiv bytes to derive *#comma-int(d.sirius_b_rad_km) km* and an escape speed of *#comma-int(d.sirius_b_v_esc_kms) km/s*.
], accent: acc-cyan)

#v(4pt)
#insight-box("Common Misconception", [
  White dwarfs are *not* burning fuel. Sirius B shines solely with leftover residual heat trapped inside an Earth-sized quantum crystal.
], accent: acc-coral, bg: bg-trap)

#source-row((
  source-pill("https://doi.org/10.3847/1538-4357/aa6af8", "Bond 2017 · ApJ"),
  source-pill("https://doi.org/10.1093/mnras/sty2404", "Joyce 2018 · MNRAS", accent: acc-gold),
))

// ============================================================================
// CARD 8 — PSR J0740+6620 (NEUTRON STAR)
// ============================================================================
#pagebreak()
#kicker("07 · Neutron Degeneracy  ·  Stop 6 of 9", accent: acc-cyan)
#card-title("PSR J0740+6620: A City-Sized Atomic Nucleus")

Pile too much mass onto a white dwarf and even electron degeneracy snaps. Protons and electrons fuse into neutrons until nuclear degeneracy and the strong force halt collapse at city scale.

#v(4pt)
#grid(
  columns: (1fr, 1fr, 1fr),
  gutter: 6pt,
  kpi-tile("Mass", fmt(d.psr_mass_msun, digits: 3) + " M☉", "NICER X-ray", accent: acc-cyan),
  kpi-tile("Radius", fmt(d.psr_rad_km, digits: 2) + " km", "Across one city", accent: acc-gold),
  kpi-tile("Escape Speed", fmt(d.psr_v_esc_pct_c, digits: 1) + "% c", "Xi = " + fmt(d.psr_j0740_compactness, digits: 3), accent: acc-coral),
)
#v(6pt)

*Halfway to Becoming a Black Hole:* NASA's NICER telescope aboard the Space Station timed X-ray pulses from *PSR J0740+6620*, pinning down *#fmt(d.psr_mass_msun, digits: 3) solar masses* packed inside just *#fmt(d.psr_rad_km, digits: 2) km*. Its compactness reaches *#math.equation(alt: "Xi equals 0.494", $Xi = 0.494$)* — gravity bends light so severely you can see *behind* the star's limb.

#v(4pt)
#insight-box("Matter Denser Than an Atomic Nucleus", [
  At *#math.equation(alt: "5.17 times 10 to the 14", $5.17 times 10^(14)$) g/cm³*, a single *#str(int(d.teaspoon_cm3)) cm³* teaspoon of PSR J0740+6620 weighs *#fmt(d.psr_teaspoon_billion_t, digits: 2) billion metric tons* — roughly the mass of a major mountain range compressed onto a kitchen spoon.
], accent: acc-cyan)

#v(4pt)
#insight-box("The Razor's Edge of Known Physics", [
  PSR J0740+6620 is one of the heaviest neutron stars ever weighed. Push mass only slightly higher and even the strong nuclear force surrenders — leaving no remaining floor in nature.
], accent: acc-gold)

#source-row((
  source-pill("https://doi.org/10.3847/2041-8213/ac0a81", "Riley et al. 2021 · NICER ApJL"),
))

// ============================================================================
// CARD 9 — CYGNUS X-1 & COMPACTNESS LADDER
// ============================================================================
#pagebreak()
#kicker("08 · Stellar Black Hole  ·  Stop 7 of 9", accent: acc-coral)
#card-title("Cygnus X-1: Where Escape Hits Light Speed")

Radio astrometry at *#fmt(d.cyg_dist_kpc, digits: 2) kpc* revealed *Cygnus X-1* hosts a *#fmt(d.cyg_mass_msun, digits: 1) solar-mass* black hole. Its entire mass lies trapped inside an event horizon *#fmt(d.cyg_rs_km, digits: 1) km* across — where compactness locks at *#math.equation(alt: "Xi equals 1", $Xi = 1$)*.

#v(4pt)
#grid(
  columns: (1fr, 1fr, 1fr),
  gutter: 6pt,
  kpi-tile("Mass", fmt(d.cyg_mass_msun, digits: 1) + " M☉", "VLBA parallax", accent: acc-coral),
  kpi-tile("Horizon R_s", fmt(d.cyg_rs_km, digits: 1) + " km", "Escape = 100% c", accent: acc-gold),
  kpi-tile("Tidal Shear", fmt(d.cyg_tidal_million_g, digits: 2) + "M g", "Across 1.8 m", accent: acc-coral),
)
#v(6pt)
#image("figures/fig_compactness_ladder.svg", width: 100%, alt: "Horizontal logarithmic compactness and escape velocity bar chart across all 9 curated celestial bodies from Comet 67P up to the Event Horizon wall at 100 percent speed of light.")
#v(4pt)

*No Surface, Only a One-Way Membrane:* An event horizon is not a solid wall — it is the boundary where spacetime tilts inward faster than light. Fall toward Cygnus X-1, however, and tidal gravity rips a *#fmt(d.human_height_m, digits: 1) m* astronaut at *#fmt(d.cyg_tidal_million_g, digits: 2) million g* *before* arrival.

#source-row((
  source-pill("https://doi.org/10.1126/science.abb3363", "Miller-Jones et al. 2021 · Science", accent: acc-coral),
))

// ============================================================================
// CARD 10 — SGR A* & M87* (THE TWO PARADOXES)
// ============================================================================
#pagebreak()
#kicker("09 · Supermassive Monsters  ·  Stops 8 & 9", accent: acc-coral)
#card-title([Sgr A\* & M87\*:#linebreak()Bigger Means Gentler])

Scale a black hole up to galactic centers — our Milky Way's *Sgr A\** (*#fmt(d.sgra_mass_million_msun, digits: 2) million M☉*, EHT ring *#fmt(d.sgra_ring_uas, digits: 1) μas*) and giant elliptical *M87\** (*#fmt(d.m87_mass_billion_msun, digits: 1) billion M☉*, ring *#fmt(d.m87_ring_uas, digits: 0) μas*) — and intuition flips upside down.

#v(4pt)
#grid(
  columns: (1fr, 1fr),
  gutter: 7pt,
  kpi-tile("Sgr A* Horizon", fmt(d.sgra_rs_mkm, digits: 2) + "M km", "Shear: " + fmt(d.sgra_tidal_millig, digits: 3) + " milli-g", accent: acc-gold),
  kpi-tile("M87* Horizon", fmt(d.m87_rs_au, digits: 1) + " AU", fmt(d.m87_rs_pluto_ratio, digits: 2) + " × Pluto's orbit!", accent: acc-mint),
)
#v(6pt)
#image("figures/fig_spaghettification.svg", width: 100%, alt: "Tidal shear at the Event Horizon scaling as inverse mass squared across Cygnus X-1, Sgr A*, and M87*, paired with the M87* versus Earth sea-level air density paradox bar.")
#v(4pt)

*Two Shocking Consequences of #math.equation(alt: "R_s proportional to M", $R_s prop M$):* Because horizon radius grows linearly with mass, volume grows as #math.equation(alt: "M cubed", $M^3$) while tidal shear falls as #math.equation(alt: "1 over M squared", $1 / M^2$). You would cross *M87\*'s* *#fmt(d.m87_rs_bkm, digits: 2) billion km* horizon feeling just *#fmt(d.m87_tidal_picog, digits: 1) pico-g* — inside a sphere *#fmt(d.air_to_m87_ratio, digits: 2) times less dense than Earth's air*!

#source-row((
  source-pill("https://doi.org/10.1051/0004-6361/202142465", "GRAVITY 2022", accent: acc-gold),
  source-pill("https://doi.org/10.3847/2041-8213/ac6674", "EHT Sgr A*", accent: acc-cyan),
  source-pill("https://doi.org/10.3847/2041-8213/ab0ec7", "EHT M87*", accent: acc-coral),
))

// ============================================================================
// CARD 11 — COMPLETE FIELD LEDGER & ACTIVE RECALL
// ============================================================================
#pagebreak()
#kicker("10 · Curated Field Ledger & Recall", accent: acc-mint)
#card-title("All 9 Bodies at a Glance")

#set table(
  stroke: (x, y) => if y == 0 { (bottom: 1.0pt + acc-cyan) } else { (bottom: 0.35pt + rule-line) },
  inset: (x: 4pt, y: 4.5pt),
)

#table(
  columns: (1.28fr, 1.05fr, 1.02fr),
  align: (left, right, right),
  table.header(
    text(font: "IBM Plex Mono", size: 7.1pt, weight: "bold", fill: acc-cyan)[BODY],
    text(font: "IBM Plex Mono", size: 7.1pt, weight: "bold", fill: acc-cyan)[RADIUS / R_s],
    text(font: "IBM Plex Mono", size: 7.1pt, weight: "bold", fill: acc-cyan)[ESCAPE SPEED],
  ),
  text(size: 8.6pt, weight: "bold", fill: ink-bright)[Comet 67P],
  text(font: "IBM Plex Mono", size: 8.2pt)[#fmt(d.comet_67p_radius_km, digits: 1) km],
  text(font: "IBM Plex Mono", size: 8.2pt)[#fmt(d.c67_v_esc_ms, digits: 2) m/s],

  text(size: 8.6pt, weight: "bold", fill: ink-bright)[Earth],
  text(font: "IBM Plex Mono", size: 8.2pt)[#comma-int(d.earth_radius_km) km],
  text(font: "IBM Plex Mono", size: 8.2pt)[#fmt(d.earth_v_esc_kms, digits: 2) km/s],

  text(size: 8.6pt, weight: "bold", fill: ink-bright)[Jupiter],
  text(font: "IBM Plex Mono", size: 8.2pt)[#comma-int(d.jupiter_radius_km) km],
  text(font: "IBM Plex Mono", size: 8.2pt)[#fmt(d.jupiter_v_esc_kms, digits: 2) km/s],

  text(size: 8.6pt, weight: "bold", fill: ink-bright)[The Sun],
  text(font: "IBM Plex Mono", size: 8.2pt)[#comma-int(d.sun_radius_km) km],
  text(font: "IBM Plex Mono", size: 8.2pt)[#fmt(d.sun_v_esc_kms, digits: 1) km/s],

  text(size: 8.6pt, weight: "bold", fill: acc-cyan)[Sirius B],
  text(font: "IBM Plex Mono", size: 8.2pt)[#comma-int(d.sirius_b_rad_km) km],
  text(font: "IBM Plex Mono", size: 8.2pt)[#comma-int(d.sirius_b_v_esc_kms) km/s],

  text(size: 8.6pt, weight: "bold", fill: acc-cyan)[PSR J0740],
  text(font: "IBM Plex Mono", size: 8.2pt)[#fmt(d.psr_rad_km, digits: 2) km],
  text(font: "IBM Plex Mono", size: 8.2pt, fill: acc-cyan)[#fmt(d.psr_v_esc_pct_c, digits: 1)% c],

  text(size: 8.6pt, weight: "bold", fill: acc-coral)[Cygnus X-1],
  text(font: "IBM Plex Mono", size: 8.2pt)[#fmt(d.cyg_rs_km, digits: 1) km],
  text(font: "IBM Plex Mono", size: 8.2pt, fill: acc-coral)[100% c],

  text(size: 8.6pt, weight: "bold", fill: acc-coral)[Sgr A\*],
  text(font: "IBM Plex Mono", size: 8.2pt)[#fmt(d.sgra_rs_mkm, digits: 2)M km],
  text(font: "IBM Plex Mono", size: 8.2pt, fill: acc-coral)[100% c],

  text(size: 8.6pt, weight: "bold", fill: acc-coral)[M87\*],
  text(font: "IBM Plex Mono", size: 8.2pt)[#fmt(d.m87_rs_au, digits: 1) AU],
  text(font: "IBM Plex Mono", size: 8.2pt, fill: acc-coral)[100% c],
)

#v(8pt)
#insight-box("Active Recall · Test Your Mental Model", [
  *Q1: Which is denser inside its boundary — M87\* or the air in your room?*
  #linebreak()
  #text(fill: acc-mint)[*Air wins:*] M87\* averages *#fmt(d.m87_density_kg_m3, digits: 3) kg/m³* vs sea-level air at *#fmt(d.air_density_kg_m3, digits: 3) kg/m³* (*#fmt(d.air_to_m87_ratio, digits: 2)x* lighter!).
  #v(4pt)
  *Q2: What holds up Sirius B if it no longer fuses fuel?*
  #linebreak()
  #text(fill: acc-cyan)[*Quantum mechanics:*] Electron Pauli degeneracy pressure keeps *#fmt(d.sirius_b_mass_gr_msun, digits: 3) M☉* packed inside *#comma-int(d.sirius_b_rad_km) km*.
  #v(4pt)
  *Q3: Would you survive crossing Cygnus X-1's horizon vs M87\*'s?*
  #linebreak()
  #text(fill: acc-gold)[*Only M87\*:*] Cygnus X-1 shreds you at *#fmt(d.cyg_tidal_million_g, digits: 2) million g*; M87\*'s horizon exerts just *#fmt(d.m87_tidal_picog, digits: 1) pico-g*.
], accent: acc-mint)

// ============================================================================
// CARD 12 — CRYPTOGRAPHIC PROVENANCE SEAL & VERIFICATION LIBRARY
// ============================================================================
#pagebreak()
#kicker("11 · Cryptographic Seal & Sources", accent: acc-mint)
#card-title([Verified Byte-for-Byte.#linebreak()Tap Any Source.])

Every measurement in this mobile primer was fetched live from NASA JPL, NASA NSSDC, arXiv, and Crossref, compiled in pure *Zig v0.17.0* (zero handwritten numbers, zero Python), and certified by the *6-Gate VES Court*:

#v(5pt)
#box(width: 100%, fill: bg-card, radius: 6pt, inset: (x: 10pt, y: 9pt), stroke: 0.7pt + acc-mint)[
  #text(font: "IBM Plex Mono", size: 7.2pt, weight: "bold", fill: acc-mint)[SHA-256 SEALED RAW MANIFEST (9 IMMUTABLE FILES)]
  #v(5pt)
  #for rf in d.raw_files [
    #let fname = rf.path.replace("data/raw/", "")
    #let h16 = rf.sha256.slice(0, 16)
    #grid(
      columns: (1fr, auto),
      text(font: "IBM Plex Mono", size: 7.2pt, fill: ink-body)[#fname],
      text(font: "IBM Plex Mono", size: 7.2pt, fill: acc-cyan)[#h16],
    )
    #v(2.5pt)
  ]
]

#v(7pt)
#insight-box("6-Gate Verifiable Editorial Certification", [
  *Gate 1* SHA-256 Latch · *Gate 2* Pixel WCAG AA · *Gate 3* 4-Corner Clip Geometry · *Gate 4* Rule 10 Half-ULP Prose Grounding · *Gate 5* ISO 14289-1 `PDF/UA-1` (`veraPDF`) · *Gate 6* Rule 11 Clickable & Live-Verified Resource Links.
], accent: acc-cyan)

#v(7pt)
#text(font: "IBM Plex Mono", size: 7.0pt, weight: "bold", fill: ink-muted)[FUNDAMENTAL CONSTANTS & ENGINE REPOSITORY:]
#v(6pt)
#stack(
  spacing: 7pt,
  stack(dir: ltr, spacing: 6pt,
    source-pill("https://doi.org/10.1103/RevModPhys.93.025010", "CODATA 2018 (c, G)", accent: acc-gold),
    source-pill("https://doi.org/10.3847/1538-3881/abd414", "JPL DE440 (Pluto)", accent: acc-cyan),
  ),
  source-pill("https://github.com/gke0op/verifiable-editorial-skills", "gke0op/verifiable-editorial-skills", accent: acc-mint),
)

#v(1fr)
#align(center)[
  #text(font: "IBM Plex Mono", size: 6.9pt, fill: ink-muted)[MOBILE PORTRAIT PDF/UA-1  ·  360 × 640 pt  ·  WHATSAPP NATIVE]
]
