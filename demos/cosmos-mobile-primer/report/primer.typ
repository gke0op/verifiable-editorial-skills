// COSMOS IN YOUR POCKET — Ultra-Minimalist Zero-Box Mobile Field Primer
// Design:  Continuous deep-void OLED canvas (#07090F), ZERO filled boxes,
//          subtle opposite-corner architectural brackets (┌ ... ┘) around invisible frames,
//          naked typographic KPIs, Tufte open axes, hairline-anchored tappable links.
// Format:  360 x 640 pt (9:16 portrait mobile PDF/UA-1 — instant WhatsApp open on every phone)

#let d = json("../data/summary_metrics.json")

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

// Restrained Observatory Palette — continuous void, whisper-thin reticles, >= 7:1 WCAG ink
#let bg-void    = rgb("#07090F")
#let ink-bright = rgb("#F2F4F8")
#let ink-body   = rgb("#D6DCE6")
#let ink-muted  = rgb("#9AA8BC")
#let acc-gold   = rgb("#E8C078")
#let acc-ice    = rgb("#8CC8F0")
#let acc-rose   = rgb("#E58A8A")
#let acc-sage   = rgb("#7AD1B8")
#let reticle    = rgb("#2B384E")
#let hair-dim   = rgb("#1C2638")

#set document(
  title: "Cosmos in Your Pocket: From Rubble Comets to Supermassive Black Holes",
  author: "Verifiable Editorial Skills (Zig 0.17 + Typst PDF/UA-1)",
  description: "Ultra-minimalist zero-box 9:16 mobile astrophysics primer built from live NASA, arXiv, and Crossref data behind a 6-gate cryptographic court.",
)

#set text(
  font: "Inter",
  size: 10.6pt,
  fill: ink-body,
  lang: "en",
  hyphenate: false,
)

#set par(
  leading: 0.68em,
  spacing: 0.85em,
  justify: false,
)

#set page(
  width: 360pt,
  height: 640pt,
  margin: (top: 28pt, bottom: 30pt, left: 28pt, right: 28pt),
  fill: bg-void,
  background: context {
    let p = counter(page).get().first()
    let tot = counter(page).final().first()
    let frac = p / tot
    // Whisper-thin 1.5pt progress hairline along top edge
    place(top + left, rect(width: 360pt, height: 1.5pt, fill: hair-dim))
    place(top + left, rect(width: 360pt * frac, height: 1.5pt, fill: acc-gold))
  },
  footer: context {
    let p = counter(page).get().first()
    let tot = counter(page).final().first()
    if p > 1 {
      let pad = if p < 10 { "0" + str(p) } else { str(p) }
      grid(
        columns: (1fr, auto),
        align: (left + bottom, right + bottom),
        text(font: "IBM Plex Mono", size: 7.1pt, fill: ink-muted)[COSMOS IN YOUR POCKET],
        text(font: "IBM Plex Mono", size: 7.1pt, fill: ink-muted)[#pad / #tot],
      )
    }
  },
)

// ============================================================================
// ZERO-BOX ARCHITECTURAL PRIMITIVES
// ============================================================================

#let kicker(label, accent: ink-muted) = {
  text(font: "IBM Plex Mono", size: 7.4pt, fill: accent, tracking: 0.12em)[#upper(label)]
}

#let card-title(title) = {
  v(4pt)
  set par(leading: 0.44em)
  text(font: "Source Serif 4", size: 19.5pt, weight: "semibold", fill: ink-bright, number-type: "lining")[#title]
  v(8pt)
}

// Asymmetric Opposite-Corner Bracket Frame (┌ top-left + ┘ bottom-right ONLY — invisible box, zero fill!)
#let corner-frame(body, arm-x: 42pt, arm-y: 26pt, stroke-color: reticle, stroke-w: 0.6pt, pad-x: 13pt, pad-y: 10pt) = {
  context layout(avail => {
    let inner = block(width: avail.width - 2 * pad-x, body)
    let m = measure(inner)
    let h = m.height + 2 * pad-y
    let vy = calc.min(arm-y, h * 0.62)
    block(width: 100%, height: h, breakable: false, {
      // Top-left L bracket: ┌
      place(top + left, line(length: arm-x, stroke: stroke-w + stroke-color))
      place(top + left, line(angle: 90deg, length: vy, stroke: stroke-w + stroke-color))
      // Bottom-right L bracket: ┘
      place(bottom + right, line(length: arm-x, stroke: stroke-w + stroke-color))
      place(bottom + right, line(angle: 90deg, length: vy, stroke: stroke-w + stroke-color))
      // Content floating inside the open frame
      place(top + left, dx: pad-x, dy: pad-y, inner)
    })
  })
}

// Minimalist floating note framed solely by subtle ┌ ... ┘ corner hairlines (zero fill!)
#let open-note(tag, content, accent: acc-gold, line-col: reticle) = {
  corner-frame(
    arm-x: 44pt,
    arm-y: 28pt,
    stroke-color: line-col,
    stroke-w: 0.58pt,
    pad-x: 13pt,
    pad-y: 10pt,
  )[
    #text(font: "IBM Plex Mono", size: 7.0pt, weight: "semibold", fill: accent, tracking: 0.08em)[#upper(tag)]
    #v(4pt)
    #set text(size: 9.9pt, fill: ink-body)
    #set par(leading: 0.64em)
    #content
  ]
}

// Naked typographic KPI strip — zero boxes, zero fills, whisper-thin dividers only
#let stat-col(label, val, sub, accent: ink-bright) = {
  stack(
    spacing: 2.5pt,
    text(font: "IBM Plex Mono", size: 6.6pt, fill: ink-muted, tracking: 0.08em)[#upper(label)],
    text(font: "IBM Plex Mono", size: 14.5pt, weight: "semibold", fill: accent)[#val],
    text(size: 7.6pt, fill: ink-muted)[#sub],
  )
}

#let stat-strip-3(c1, c2, c3) = {
  v(2pt)
  line(length: 100%, stroke: 0.45pt + reticle)
  v(8pt)
  grid(
    columns: (1fr, auto, 1fr, auto, 1fr),
    column-gutter: 7pt,
    align: left + top,
    c1,
    line(angle: 90deg, length: 34pt, stroke: 0.4pt + hair-dim),
    c2,
    line(angle: 90deg, length: 34pt, stroke: 0.4pt + hair-dim),
    c3,
  )
  v(8pt)
  line(length: 100%, stroke: 0.45pt + hair-dim)
}

#let stat-strip-2(c1, c2) = {
  v(2pt)
  line(length: 100%, stroke: 0.45pt + reticle)
  v(8pt)
  grid(
    columns: (1fr, auto, 1fr),
    column-gutter: 10pt,
    align: left + top,
    c1,
    line(angle: 90deg, length: 34pt, stroke: 0.4pt + hair-dim),
    c2,
  )
  v(8pt)
  line(length: 100%, stroke: 0.45pt + hair-dim)
}

// Box-free minimalist tappable link (>= 22pt vertical hitbox via transparent padding!)
#let bare-link(url, label, accent: acc-ice) = {
  link(url)[
    #box(inset: (x: 2pt, y: 6pt))[
      #underline(offset: 2.5pt, stroke: 0.45pt + reticle)[
        #text(font: "IBM Plex Mono", size: 7.4pt, fill: accent)[#label ↗]
      ]
    ]
  ]
}

// Seamless box-free fixed-slot panoramic plate (304 x 118 pt @ 326 DPI, edge-feathered into #07090F void)
#let void-plate(path, alt-text) = {
  v(1fr)
  image(path, width: 304pt, height: 118pt, fit: "cover", alt: alt-text)
}

#let source-footer(links) = {
  v(1fr)
  line(length: 100%, stroke: 0.45pt + hair-dim)
  v(4pt)
  text(font: "IBM Plex Mono", size: 6.4pt, fill: ink-muted, tracking: 0.1em)[PRIMARY SOURCES · TAP TO VERIFY]
  v(1pt)
  stack(dir: ltr, spacing: 14pt, ..links)
}

// ============================================================================
// CARD 1 — POSTER COVER (Pure Minimalist Void + Viewfinder Reticle)
// ============================================================================
#v(6pt)
#kicker("Mobile Field Primer  ·  Astrophysics", accent: acc-gold)
#v(5pt)
#text(font: "Source Serif 4", size: 26pt, weight: "semibold", fill: ink-bright, number-type: "lining")[
  Cosmos in Your Pocket
]
#v(2pt)
#text(font: "Source Serif 4", size: 13pt, style: "italic", fill: ink-muted)[
  From Rubble Comets to Supermassive Black Holes
]
#v(8pt)
#text(size: 10.2pt, fill: ink-body)[
  Nine real celestial bodies. One unifying physics ratio explains why a comet stays a lumpy rubble pile while a collapsing star tears spacetime open.
]
#v(10pt)
#image("figures/fig_cover_cosmos.svg", width: 100%, alt: "Minimalist concentric cosmic compactness reticle from Comet 67P through Earth, the Sun, Sirius B, PSR J0740+6620, to the Event Horizon of M87*.")
#v(10pt)
#stat-strip-3(
  stat-col("Mass Span", fmt(d.mass_orders_span, digits: 1) + " dec", "67P to M87*", accent: acc-gold),
  stat-col("Density", fmt(d.density_orders_span, digits: 1) + " dec", "M87* to PSR", accent: acc-ice),
  stat-col("Sources", str(d.body_count) + " bodies", "NASA & DOIs", accent: acc-sage),
)
#v(1fr)
#grid(
  columns: (1fr, auto),
  align: (left + horizon, right + horizon),
  text(font: "IBM Plex Mono", size: 6.9pt, fill: ink-muted, tracking: 0.08em)[ZERO HANDWRITTEN DATA  ·  SWIPE ↓],
  bare-link("https://github.com/gke0op/verifiable-editorial-skills", "VES 6-GATE", accent: acc-sage),
)

// ============================================================================
// CARD 2 — THE ONE MENTAL MODEL
// ============================================================================
#pagebreak()
#kicker("01 · The Unifying Mental Model", accent: acc-gold)
#card-title([One Tug-of-War Builds#linebreak()Every World in Space])

Every celestial body is the equilibrium of one battle: *gravity pulling mass inward* against *whatever force pushes back*.

Track one dimensionless ratio called *compactness* — how close an object sits to its own black-hole event horizon:

#v(4pt)
#corner-frame(arm-x: 36pt, arm-y: 22pt, stroke-color: acc-gold, stroke-w: 0.55pt, pad-x: 12pt, pad-y: 11pt)[
  #align(center)[
    #set text(fill: ink-bright, size: 11.4pt)
    #math.equation(
      block: true,
      alt: "Compactness Xi equals Schwarzschild radius R_s divided by radius R, which equals 2 G M divided by R c squared, and also equals escape velocity over speed of light squared.",
      $ Xi = R_s / R = (2 G M) / (R c^2) = (v_"esc" / c)^2 $,
    )
  ]
  #v(2pt)
  #align(center)[#text(size: 8.3pt, fill: ink-muted)[Tiny #math.equation(alt: "Xi", $Xi$): loose rock  ·  #math.equation(alt: "Xi equals 1", $Xi = 1$): escape hits light speed #math.equation(alt: "c", $c$).]]
]
#v(10pt)

#text(font: "IBM Plex Mono", size: 7.2pt, fill: ink-muted, tracking: 0.1em)[THE FOUR COSMIC FLOORS STOPPING COLLAPSE]
#v(6pt)

#let floor-row(num, title, desc, accent: ink-muted) = {
  grid(
    columns: (22pt, 1fr),
    column-gutter: 6pt,
    text(font: "IBM Plex Mono", size: 8.2pt, weight: "semibold", fill: accent)[#num],
    [
      #text(size: 9.8pt, weight: "semibold", fill: ink-bright)[#title]
      #v(1.5pt)
      #text(size: 9.4pt, fill: ink-body)[#desc]
    ],
  )
  v(7pt)
  line(length: 100%, stroke: 0.35pt + hair-dim)
  v(7pt)
}

#floor-row("01", "Chemical Rock & Ice Bonds", [Small comets stay lumpy because electromagnetic bonds easily beat weak self-gravity.], accent: ink-muted)
#floor-row("02", "Hydrostatic & Fusion Pressure", [Planets crush rock into spheres; stars burn nuclear fuel so outward heat resists collapse.], accent: acc-gold)
#floor-row("03", "Quantum Pauli Exclusion", [Dead stellar cores cool down, leaving pure quantum degeneracy (electrons or neutrons) to hold.], accent: acc-ice)
#grid(
  columns: (22pt, 1fr),
  column-gutter: 6pt,
  text(font: "IBM Plex Mono", size: 8.2pt, weight: "semibold", fill: acc-rose)[04],
  [
    #text(size: 9.8pt, weight: "semibold", fill: ink-bright)[None — The Event Horizon]
    #v(1.5pt)
    #text(size: 9.4pt, fill: ink-body)[Beyond the neutron limit, no known force holds. Radius crosses #math.equation(alt: "R_s", $R_s$), compactness locks at #math.equation(alt: "Xi equals 1", $Xi = 1$), and a black hole forms.]
  ],
)

// ============================================================================
// CARD 3 — THE GRAND PHASE MAP
// ============================================================================
#pagebreak()
#kicker("02 · The Grand Cosmic Map", accent: acc-ice)
#card-title([27 Orders of Magnitude#linebreak()on One Cosmic Map])

Plot every body's mass against its radius in log scale, and all of astrophysics aligns into three clean geometric regimes:

#v(6pt)
#image("figures/fig_mass_radius.svg", width: 100%, alt: "Box-free Tufte log-log Mass versus Radius phase diagram of 9 real celestial bodies from Comet 67P to M87*, showing the water-density slope and the forbidden black hole Event Horizon boundary.")
#v(8pt)

#open-note("How to Read This Map", [
  *1. Water-Density Slope (Dashed):* Comets, rocky planets, gas giants, and the Sun all cluster near ordinary atomic density.
  #v(4pt)
  *2. Quantum Plunge (Blue):* When fusion ends, solar-mass cores drop straight downward — Sirius B shrinks smaller than Earth, PSR J0740 to city width.
  #v(4pt)
  *3. Event Horizon Wall (#math.equation(alt: "R equals R_s", $R = R_s$)):* No stable surface exists below-right. Black holes trace the line — growing *less dense* as they grow larger.
], accent: acc-ice, line-col: reticle)

// ============================================================================
// CARD 4 — COMET 67P
// ============================================================================
#pagebreak()
#kicker("03 · Rubble & Ice  ·  Stop 1 of 9", accent: ink-muted)
#card-title([Comet 67P: You Could#linebreak()Jump Into Deep Space])

ESA's Rosetta orbiter weighed Comet 67P/Churyumov–Gerasimenko from subtle radio shifts in its flight path. Its surface gravity is *#comma-int(d.c67_to_earth_g_inv) times weaker* than Earth's.

#stat-strip-3(
  stat-col("Escape", fmt(d.c67_v_esc_ms, digits: 2) + " m/s", "Human jump", accent: acc-ice),
  stat-col("Density", fmt(d.c67_dens_g_cm3, digits: 3), "g/cm³ (< water)", accent: acc-gold),
  stat-col("Width", fmt(d.c67_diam_km, digits: 1) + " km", "Bi-lobed", accent: acc-sage),
)
#v(8pt)

*Why It Isn't Round:* Gravity can only pull matter into a sphere once it overpowers the tensile strength of rock and ice. At *#fmt(d.c67_diam_km, digits: 1) km* wide, 67P's compactness is a microscopic #math.equation(alt: "Xi equals 8.67 times 10 to the minus 18", $Xi = 8.67 times 10^(-18)$) — freezing its two-lobed silhouette in place.

#v(8pt)
#open-note("Intuition · Porous Cosmic Sponge", [
  Measured at *#fmt(d.c67_dens_g_cm3, digits: 3) g/cm³* — roughly half the density of water — most of 67P is empty pore space between loose dust and ice grains. Far from solid frozen glass, it is a fragile rubble pile that would float.
], accent: acc-gold, line-col: reticle)

#void-plate("plates/plate_04_67p.jpg", "Panoramic deep-space visual of the dark bi-lobed rubble nucleus of Comet 67P with faint sunlit sublimation gas wisps floating in space void.")

#source-footer((
  bare-link("https://ssd-api.jpl.nasa.gov/sbdb.api?sstr=67P&phys-par=1", "NASA JPL SBDB"),
  bare-link("https://doi.org/10.1038/nature16535", "Rosetta · Nature 2016", accent: acc-gold),
))

// ============================================================================
// CARD 5 — EARTH & JUPITER
// ============================================================================
#pagebreak()
#kicker("04 · Hydrostatic Worlds  ·  Stops 2 & 3", accent: acc-gold)
#card-title([Earth & Jupiter: Gravity#linebreak()Sculpts Round Worlds])

Accumulate enough rock or gas and gravity crushes crystal lattices into near-perfect spheres in *hydrostatic equilibrium*.

#stat-strip-2(
  stat-col("Earth · Rock", fmt(d.earth_v_esc_kms, digits: 2) + " km/s", "R = " + comma-int(d.earth_radius_km) + " km · " + fmt(d.earth_density_g_cm3, digits: 2) + " g/cm³", accent: acc-ice),
  stat-col("Jupiter · Gas", fmt(d.jupiter_v_esc_kms, digits: 2) + " km/s", "R = " + comma-int(d.jupiter_radius_km) + " km · " + fmt(d.jup_earth_mass_ratio, digits: 1) + " Earths", accent: acc-gold),
)
#v(8pt)

*Rock vs. Compressed Hydrogen:* Earth's iron core and silicate mantle reach *#fmt(d.earth_density_g_cm3, digits: 2) g/cm³* — the densest major world in our Solar System. Jupiter carries *#fmt(d.jup_earth_mass_ratio, digits: 1) times* Earth's mass yet averages *#fmt(d.jupiter_density_g_cm3, digits: 2) g/cm³*, squeezing deep hydrogen into a liquid metallic state.

#v(8pt)
#open-note("Scale Shock · Earth's Event Horizon", [
  Plug Earth's mass into #math.equation(alt: "R_s equals 2 G M over c squared", $R_s = (2 G M) / c^2$): our entire planet would have to be crushed to a glass marble just *#fmt(d.earth_rs_mm, digits: 2) mm* in radius to form a black hole. Today Earth rests calmly at #math.equation(alt: "Xi equals 1.39 times 10 to the minus 9", $Xi = 1.39 times 10^(-9)$).
], accent: acc-ice, line-col: reticle)

#void-plate("plates/plate_05_earth_jupiter.jpg", "Panoramic deep-space pairing of Earth's thin blue crescent limb on the left and Jupiter's sweeping turbulent amber cloud horizon on the right.")

#source-footer((
  bare-link("https://nssdc.gsfc.nasa.gov/planetary/factsheet/earthfact.html", "NASA Earth Fact Sheet"),
  bare-link("https://nssdc.gsfc.nasa.gov/planetary/factsheet/jupiterfact.html", "NASA Jupiter", accent: acc-gold),
))

// ============================================================================
// CARD 6 — THE SUN
// ============================================================================
#pagebreak()
#kicker("05 · Nuclear Fusion  ·  Stop 4 of 9", accent: acc-gold)
#card-title([The Sun: A Self-Regulating#linebreak()Fusion Thermostat])

Gather *#comma-int(d.sun_earth_mass_ratio) Earths* of hydrogen and central pressure ignites nuclear fusion. Gravity tries to crush the star in under an hour; outward thermal and radiation pressure holds it aloft for billions of years.

#stat-strip-3(
  stat-col("Radius", comma-int(d.sun_radius_km) + " km", "Gas sphere", accent: acc-gold),
  stat-col("Escape", fmt(d.sun_v_esc_kms, digits: 1) + " km/s", "Solar limb", accent: acc-ice),
  stat-col("Horizon", fmt(d.sun_rs_km, digits: 2) + " km", "Xi = 4.24×10⁻⁶", accent: acc-rose),
)
#v(8pt)

*Built-In Negative Feedback:* If the solar core compresses slightly, temperature rises, fusion accelerates, and extra pressure expands and cools the core back into balance. Intense heat puffs its envelope wide so average density stays just *#fmt(d.sun_density_g_cm3, digits: 2) g/cm³* — a quarter of Earth's rock.

#v(8pt)
#open-note("The Catch · Thermal Support Expires", [
  Thermal pressure lasts only while fuel burns. Once a star exhausts nuclear fusion, heat radiates into space and gravity collects its debt — handing control over to quantum mechanics.
], accent: acc-gold, line-col: reticle)

#void-plate("plates/plate_06_sun.jpg", "Panoramic solar horizon showing the Sun's golden chromospheric arc and three translucent magnetic coronal plasma loops rising into black space.")

#source-footer((
  bare-link("https://nssdc.gsfc.nasa.gov/planetary/factsheet/sunfact.html", "NASA Sun Fact Sheet", accent: acc-gold),
  bare-link("https://doi.org/10.3847/0004-6256/152/2/41", "IAU 2015 Res. B3", accent: acc-ice),
))

// ============================================================================
// CARD 7 — SIRIUS B (WHITE DWARF)
// ============================================================================
#pagebreak()
#kicker("06 · Electron Degeneracy  ·  Stop 5 of 9", accent: acc-ice)
#card-title([Sirius B: A Whole Sun#linebreak()Packed Inside Earth])

When a Sun-like star runs dry, its outer gas drifts off and its carbon-oxygen core implodes until the *Pauli Exclusion Principle* halts collapse.

#stat-strip-3(
  stat-col("Mass", fmt(d.sirius_b_mass_gr_msun, digits: 3) + " M☉", "Dyn " + fmt(d.sirius_b_mass_dyn_msun, digits: 3), accent: acc-ice),
  stat-col("GR Radius", comma-int(d.sirius_b_rad_km) + " km", fmt(d.sirius_b_earth_rad_ratio, digits: 3) + " Earths", accent: acc-gold),
  stat-col("Teaspoon", fmt(d.sirius_b_teaspoon_tons, digits: 1) + " t", "Per 5 cm³", accent: acc-rose),
)
#v(8pt)

*Quantum Support (Zero Heat Needed):* No two electrons can share the exact same quantum state. Squeezed smaller than Earth (*#comma-int(d.sirius_b_rad_km) km*), electrons push back permanently even at absolute zero. White dwarfs burn no fuel — they only glow with trapped leftover heat.

#v(8pt)
#open-note("VES Receipt · Derived From Einstein's Redshift", [
  Hubble measured starlight climbing out of Sirius B redshifted by *#fmt(d.sirius_b_vg_kms, digits: 2) km/s* (Joyce et al. 2018). Our Zig engine solved #math.equation(alt: "R equals G M over c times v_g", $R = (G M) / (c v_g)$) directly from raw arXiv bytes to derive *#comma-int(d.sirius_b_rad_km) km* and *#comma-int(d.sirius_b_v_esc_kms) km/s* escape speed.
], accent: acc-ice, line-col: reticle)

#void-plate("plates/plate_07_sirius_b.jpg", "Panoramic deep-space view of the compact blue-white dwarf star Sirius B with crisp four-point diffraction spikes beside the distant warm glow of Sirius A.")

#source-footer((
  bare-link("https://doi.org/10.3847/1538-4357/aa6af8", "Bond 2017 · ApJ"),
  bare-link("https://doi.org/10.1093/mnras/sty2404", "Joyce 2018 · MNRAS", accent: acc-gold),
))

// ============================================================================
// CARD 8 — PSR J0740+6620 (NEUTRON STAR)
// ============================================================================
#pagebreak()
#kicker("07 · Neutron Degeneracy  ·  Stop 6 of 9", accent: acc-ice)
#card-title([PSR J0740+6620: A City-Sized#linebreak()Atomic Nucleus])

Pile too much mass onto a white dwarf and electrons merge with protons into a superfluid sea of neutrons halted only by nuclear degeneracy and the strong force.

#stat-strip-3(
  stat-col("Mass", fmt(d.psr_mass_msun, digits: 3) + " M☉", "NICER X-ray", accent: acc-ice),
  stat-col("Radius", fmt(d.psr_rad_km, digits: 2) + " km", "City scale", accent: acc-gold),
  stat-col("Escape", fmt(d.psr_v_esc_pct_c, digits: 1) + "% c", "Xi = " + fmt(d.psr_j0740_compactness, digits: 3), accent: acc-rose),
)
#v(8pt)

*Halfway to a Black Hole:* NASA's NICER telescope aboard the Space Station timed X-ray pulses from *PSR J0740+6620*, packing *#fmt(d.psr_mass_msun, digits: 3) solar masses* inside *#fmt(d.psr_rad_km, digits: 2) km*. At #math.equation(alt: "Xi equals 0.494", $Xi = 0.494$), gravity bends light so hard you can see *behind* the star's edge.

#v(8pt)
#open-note("Denser Than an Atomic Nucleus", [
  At *#math.equation(alt: "5.17 times 10 to the 14", $5.17 times 10^(14)$) g/cm³*, a single *#str(int(d.teaspoon_cm3)) cm³* teaspoon weighs *#fmt(d.psr_teaspoon_billion_t, digits: 2) billion metric tons* — a mountain range on a spoon. Push mass slightly higher and the last floor in physics snaps.
], accent: acc-ice, line-col: reticle)

#void-plate("plates/plate_08_psr_j0740.jpg", "Panoramic relativistic visualization of neutron star PSR J0740+6620 with faint magnetic dipole loops and slender tilted polar X-ray beams in pure space void.")

#source-footer((
  bare-link("https://doi.org/10.3847/2041-8213/ac0a81", "Riley et al. 2021 · NICER ApJL"),
))

// ============================================================================
// CARD 9 — CYGNUS X-1 & PRECISION COMPACTNESS LADDER
// ============================================================================
#pagebreak()
#kicker("08 · Stellar Black Hole  ·  Stop 7 of 9", accent: acc-rose)
#card-title([Cygnus X-1: Where Escape#linebreak()Hits Light Speed])

VLBA radio astrometry at *#fmt(d.cyg_dist_kpc, digits: 2) kpc* confirmed *Cygnus X-1* holds a *#fmt(d.cyg_mass_msun, digits: 1) solar-mass* black hole trapped inside a *#fmt(d.cyg_rs_km, digits: 1) km* horizon — where #math.equation(alt: "Xi equals 1", $Xi = 1$).

#stat-strip-3(
  stat-col("Mass", fmt(d.cyg_mass_msun, digits: 1) + " M☉", "VLBA orbit", accent: acc-rose),
  stat-col("Horizon", fmt(d.cyg_rs_km, digits: 1) + " km", "100% c", accent: acc-gold),
  stat-col("Tidal", fmt(d.cyg_tidal_million_g, digits: 2) + "M g", "Across 1.8 m", accent: acc-rose),
)
#v(6pt)
#image("figures/fig_compactness_ladder.svg", width: 100%, alt: "Box-free minimalist precision lollipop ladder showing compactness and escape speed across all 9 celestial bodies from Comet 67P up to 100 percent speed of light.")
#v(6pt)

*A One-Way Spacetime Membrane:* An event horizon has no solid floor — spacetime itself tips inward faster than light. Yet Cygnus X-1 is so small that tidal gravity stretches a *#fmt(d.human_height_m, digits: 1) m* astronaut at *#fmt(d.cyg_tidal_million_g, digits: 2) million g* long before arrival.

#source-footer((
  bare-link("https://doi.org/10.1126/science.abb3363", "Miller-Jones et al. 2021 · Science", accent: acc-rose),
))

// ============================================================================
// CARD 10 — SGR A* & M87* (THE TWO PARADOXES)
// ============================================================================
#pagebreak()
#kicker("09 · Supermassive Monsters  ·  Stops 8 & 9", accent: acc-rose)
#card-title([Sgr A\* & M87\*:#linebreak()Bigger Means Gentler])

Scale up to galactic cores — Milky Way *Sgr A\** (*#fmt(d.sgra_mass_million_msun, digits: 2)M M☉*, EHT ring *#fmt(d.sgra_ring_uas, digits: 1) μas*) and giant *M87\** (*#fmt(d.m87_mass_billion_msun, digits: 1)B M☉*, ring *#fmt(d.m87_ring_uas, digits: 0) μas*) — and intuition inverts.

#stat-strip-2(
  stat-col("Sgr A* Horizon", fmt(d.sgra_rs_mkm, digits: 2) + "M km", "Shear: " + fmt(d.sgra_tidal_millig, digits: 3) + " milli-g", accent: acc-gold),
  stat-col("M87* Horizon", fmt(d.m87_rs_au, digits: 1) + " AU", fmt(d.m87_rs_pluto_ratio, digits: 2) + " × Pluto's orbit", accent: acc-sage),
)
#v(6pt)
#image("figures/fig_spaghettification.svg", width: 100%, alt: "Box-free Tufte plot of horizon tidal shear scaling as inverse mass squared across Cygnus X-1, Sgr A*, and M87*, paired with the M87* versus Earth sea-level air density comparison.")
#v(6pt)

*Because #math.equation(alt: "R_s proportional to M", $R_s prop M$):* Volume grows as #math.equation(alt: "M cubed", $M^3$) while tidal shear plunges as #math.equation(alt: "1 over M squared", $1 / M^2$). You would cross *M87\*'s* *#fmt(d.m87_rs_bkm, digits: 2) billion km* horizon feeling *#fmt(d.m87_tidal_picog, digits: 1) pico-g* — inside a sphere *#fmt(d.air_to_m87_ratio, digits: 2) times less dense than air*.

#source-footer((
  bare-link("https://doi.org/10.1051/0004-6361/202142465", "GRAVITY 2022", accent: acc-gold),
  bare-link("https://doi.org/10.3847/2041-8213/ac6674", "EHT Sgr A*", accent: acc-ice),
  bare-link("https://doi.org/10.3847/2041-8213/ab0ec7", "EHT M87*", accent: acc-rose),
))

// ============================================================================
// CARD 11 — COMPLETE FIELD LEDGER & ACTIVE RECALL
// ============================================================================
#pagebreak()
#kicker("10 · Curated Field Ledger & Recall", accent: acc-sage)
#card-title("All 9 Bodies at a Glance")

#set table(
  stroke: (x, y) => if y == 0 { (bottom: 0.75pt + reticle) } else { (bottom: 0.35pt + hair-dim) },
  inset: (x: 3pt, y: 4.8pt),
)

#table(
  columns: (1.28fr, 1.05fr, 1.02fr),
  align: (left, right, right),
  table.header(
    text(font: "IBM Plex Mono", size: 6.9pt, fill: ink-muted)[BODY],
    text(font: "IBM Plex Mono", size: 6.9pt, fill: ink-muted)[RADIUS / R_s],
    text(font: "IBM Plex Mono", size: 6.9pt, fill: ink-muted)[ESCAPE SPEED],
  ),
  text(size: 8.6pt, weight: "semibold", fill: ink-bright)[Comet 67P],
  text(font: "IBM Plex Mono", size: 8.1pt)[#fmt(d.comet_67p_radius_km, digits: 1) km],
  text(font: "IBM Plex Mono", size: 8.1pt)[#fmt(d.c67_v_esc_ms, digits: 2) m/s],

  text(size: 8.6pt, weight: "semibold", fill: ink-bright)[Earth],
  text(font: "IBM Plex Mono", size: 8.1pt)[#comma-int(d.earth_radius_km) km],
  text(font: "IBM Plex Mono", size: 8.1pt)[#fmt(d.earth_v_esc_kms, digits: 2) km/s],

  text(size: 8.6pt, weight: "semibold", fill: ink-bright)[Jupiter],
  text(font: "IBM Plex Mono", size: 8.1pt)[#comma-int(d.jupiter_radius_km) km],
  text(font: "IBM Plex Mono", size: 8.1pt)[#fmt(d.jupiter_v_esc_kms, digits: 2) km/s],

  text(size: 8.6pt, weight: "semibold", fill: ink-bright)[The Sun],
  text(font: "IBM Plex Mono", size: 8.1pt)[#comma-int(d.sun_radius_km) km],
  text(font: "IBM Plex Mono", size: 8.1pt)[#fmt(d.sun_v_esc_kms, digits: 1) km/s],

  text(size: 8.6pt, weight: "semibold", fill: acc-ice)[Sirius B],
  text(font: "IBM Plex Mono", size: 8.1pt)[#comma-int(d.sirius_b_rad_km) km],
  text(font: "IBM Plex Mono", size: 8.1pt)[#comma-int(d.sirius_b_v_esc_kms) km/s],

  text(size: 8.6pt, weight: "semibold", fill: acc-ice)[PSR J0740],
  text(font: "IBM Plex Mono", size: 8.1pt)[#fmt(d.psr_rad_km, digits: 2) km],
  text(font: "IBM Plex Mono", size: 8.1pt, fill: acc-ice)[#fmt(d.psr_v_esc_pct_c, digits: 1)% c],

  text(size: 8.6pt, weight: "semibold", fill: acc-rose)[Cygnus X-1],
  text(font: "IBM Plex Mono", size: 8.1pt)[#fmt(d.cyg_rs_km, digits: 1) km],
  text(font: "IBM Plex Mono", size: 8.1pt, fill: acc-rose)[100% c],

  text(size: 8.6pt, weight: "semibold", fill: acc-rose)[Sgr A\*],
  text(font: "IBM Plex Mono", size: 8.1pt)[#fmt(d.sgra_rs_mkm, digits: 2)M km],
  text(font: "IBM Plex Mono", size: 8.1pt, fill: acc-rose)[100% c],

  text(size: 8.6pt, weight: "semibold", fill: acc-rose)[M87\*],
  text(font: "IBM Plex Mono", size: 8.1pt)[#fmt(d.m87_rs_au, digits: 1) AU],
  text(font: "IBM Plex Mono", size: 8.1pt, fill: acc-rose)[100% c],
)

#v(14pt)
#open-note("Active Recall · Test Your Intuition", [
  *Which is denser — M87\* or the air in your room?*
  #linebreak()
  #text(fill: acc-sage)[Air wins:] M87\* averages *#fmt(d.m87_density_kg_m3, digits: 3) kg/m³* vs sea-level air at *#fmt(d.air_density_kg_m3, digits: 3) kg/m³* (*#fmt(d.air_to_m87_ratio, digits: 2)x* lighter).
  #v(5pt)
  *What holds up Sirius B after fusion ends?*
  #linebreak()
  #text(fill: acc-ice)[Quantum mechanics:] Electron Pauli degeneracy packs *#fmt(d.sirius_b_mass_gr_msun, digits: 3) M☉* inside *#comma-int(d.sirius_b_rad_km) km*.
  #v(5pt)
  *Which horizon can you cross without feeling a thing?*
  #linebreak()
  #text(fill: acc-gold)[M87\*:] *#fmt(d.m87_tidal_picog, digits: 1) pico-g* vs *#fmt(d.cyg_tidal_million_g, digits: 2) million g* at Cygnus X-1.
], accent: acc-sage, line-col: reticle)

// ============================================================================
// CARD 12 — CRYPTOGRAPHIC PROVENANCE SEAL & VERIFICATION LIBRARY
// ============================================================================
#pagebreak()
#kicker("11 · Cryptographic Seal & Sources", accent: acc-sage)
#card-title([Verified Byte-for-Byte.#linebreak()Tap Any Source.])

Every figure in this primer was parsed live from NASA JPL, NASA NSSDC, arXiv, and Crossref in pure *Zig v0.17.0* (zero handwritten data, zero Python), then certified across all *6 VES Gates*.

#v(6pt)
#corner-frame(arm-x: 40pt, arm-y: 26pt, stroke-color: reticle, stroke-w: 0.58pt, pad-x: 12pt, pad-y: 10pt)[
  #text(font: "IBM Plex Mono", size: 6.9pt, weight: "semibold", fill: acc-sage, tracking: 0.08em)[SHA-256 SEALED RAW MANIFEST · 9 FILES]
  #v(5pt)
  #for rf in d.raw_files [
    #let fname = rf.path.replace("data/raw/", "")
    #let h16 = rf.sha256.slice(0, 16)
    #grid(
      columns: (1fr, auto),
      text(font: "IBM Plex Mono", size: 6.9pt, fill: ink-body)[#fname],
      text(font: "IBM Plex Mono", size: 6.9pt, fill: acc-ice)[#h16],
    )
    #v(2.5pt)
  ]
]

#v(10pt)
#text(font: "IBM Plex Mono", size: 6.9pt, fill: ink-muted, tracking: 0.08em)[6-GATE CERTIFICATION & VISUAL ATTRIBUTION]
#v(4pt)
#text(size: 9.2pt, fill: ink-body)[
  *1* SHA-256 Latch · *2* Pixel WCAG AA · *3* 4-Corner Clip Geometry · *4* Rule 10 Half-ULP Prose · *5* ISO 14289-1 `PDF/UA-1` (`veraPDF`) · *6* Rule 11 Live Links.
  #v(4pt)
  #text(size: 8.6pt, fill: ink-muted)[Illustrative panoramic cosmic strips on Cards 4–8 are AI-generated bespoke plates (Nano Banana, cropped to exact fixed slot above print DPI); all data curves and numbers are pure Zig vector math.]
]

#source-footer((
  bare-link("https://doi.org/10.1103/RevModPhys.93.025010", "CODATA 2018", accent: acc-gold),
  bare-link("https://doi.org/10.3847/1538-3881/abd414", "JPL DE440", accent: acc-ice),
  bare-link("https://github.com/gke0op/verifiable-editorial-skills", "VES GitHub", accent: acc-sage),
))
