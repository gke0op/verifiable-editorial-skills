// GitHub Social Preview (OpenGraph 1280x640 px @ 144 DPI = 640pt x 320pt) + README Hero Banner
// Zero-Python pure Typst 0.15.1 composition built directly from verified repository publications.

#let c-bg      = rgb("#070B12")
#let c-panel   = rgb("#0F172A")
#let c-border  = rgb("#243247")
#let c-frame   = rgb("#1A2538")
#let c-white   = rgb("#F8FAFC")
#let c-silver  = rgb("#CBD5E1")
#let c-muted   = rgb("#94A3B8")
#let c-cyan    = rgb("#38BDF8")
#let c-orange  = rgb("#E07A2F")
#let c-emerald = rgb("#34D399")
#let c-gold    = rgb("#FBBF24")

#set page(
  width: 640pt,
  height: 320pt,
  margin: 0pt,
  fill: c-bg,
)

#set text(font: "Inter", fill: c-white, lang: "en")

// Ambient studio backdrop: deep slate-cobalt radial sheen behind the fanned publications
#place(
  top + left,
  dx: 220pt,
  dy: -40pt,
  circle(
    radius: 230pt,
    fill: gradient.radial(
      rgb("#13345C").transparentize(48%),
      rgb("#0B1B32").transparentize(72%),
      c-bg.transparentize(100%),
    ),
  ),
)
#place(
  top + left,
  dx: 420pt,
  dy: 90pt,
  circle(
    radius: 155pt,
    fill: gradient.radial(
      rgb("#7C2D12").transparentize(78%),
      c-bg.transparentize(100%),
    ),
  ),
)

// Subtle architectural blueprint grid hairlines
#for gx in range(1, 16) {
  place(
    top + left,
    dx: gx * 40pt,
    dy: 0pt,
    line(start: (0pt, 0pt), end: (0pt, 320pt), stroke: 0.35pt + rgb("#94A3B8").transparentize(93%)),
  )
}
#for gy in range(1, 8) {
  place(
    top + left,
    dx: 0pt,
    dy: gy * 40pt,
    line(start: (0pt, 0pt), end: (640pt, 0pt), stroke: 0.35pt + rgb("#94A3B8").transparentize(93%)),
  )
}

// Outer museum hairline border
#place(
  top + left,
  dx: 14pt,
  dy: 14pt,
  rect(
    width: 612pt,
    height: 292pt,
    radius: 6pt,
    stroke: 0.65pt + c-frame,
    fill: none,
  ),
)

// Helper: Floating physical print card with soft multi-layer studio shadow & crisp specular rim
#let print-card(img-path, w, angle: 0deg, rim: rgb("#FFFFFF").transparentize(74%)) = {
  rotate(
    angle,
    reflow: false,
    box[
      // Wide soft ambient shadow
      #place(
        top + left,
        dx: 6pt,
        dy: 10pt,
        box(
          width: w,
          radius: 4pt,
          fill: rgb("#010308").transparentize(58%),
          outset: 3pt,
          hide(image(img-path, width: w)),
        ),
      )
      // Mid penumbra shadow
      #place(
        top + left,
        dx: 3.5pt,
        dy: 6pt,
        box(
          width: w,
          radius: 3pt,
          fill: rgb("#010308").transparentize(48%),
          outset: 1pt,
          hide(image(img-path, width: w)),
        ),
      )
      // Crisp framed print sheet
      #box(
        width: w,
        radius: 2.5pt,
        clip: true,
        stroke: 0.75pt + rim,
        image(img-path, width: w),
      )
    ],
  )
}

// ============================================================================
// RIGHT EXHIBITION TABLE — 5 REAL VERIFIED PUBLICATIONS (BACK TO FRONT)
// ============================================================================

// 1. Back-left: BOTANICA VERIDICA (dark botanical monograph cover)
#place(
  top + left,
  dx: 280pt,
  dy: 22pt,
  print-card("../demos/botanica-veridica/previews/page_01.png", 112pt, angle: -5.5deg),
)

// 2. Back-right: FELIS MUNDI (golden-hour Bosphorus print magazine cover — full cat visible!)
#place(
  top + left,
  dx: 498pt,
  dy: 18pt,
  print-card("../demos/felis-mundi-magazine/previews/mag_page_01.png", 114pt, angle: 5deg),
)

// 3. Center-left hero: EXOMUNDUS (Swiss Ivory NASA monograph cover — sharp contrast anchor)
#place(
  top + left,
  dx: 368pt,
  dy: 28pt,
  print-card("../demos/exomundus-nasa-telemetry/previews/exo_page_01.png", 118pt, angle: -1.6deg, rim: rgb("#FFFFFF").transparentize(52%)),
)

// 4. Lower-right: Elsevier CAIE two-column academic journal
#place(
  top + left,
  dx: 468pt,
  dy: 126pt,
  print-card("../demos/caie-flowshop-journal/previews/caie_page_01.png", 114pt, angle: 3.2deg, rim: rgb("#FFFFFF").transparentize(52%)),
)

// 5. Front-bottom: 16:9 Flagship Executive Deck (electric orbital sphere)
#place(
  top + left,
  dx: 290pt,
  dy: 198pt,
  print-card("../demos/consulting-flagship/previews/flagship_slide_01.png", 160pt, angle: -2.2deg, rim: c-cyan.transparentize(40%)),
)

// ============================================================================
// LEFT SWISS EDITORIAL IDENTITY BLOCK (SAFE INSIDE x: 34..266pt)
// ============================================================================
#place(
  top + left,
  dx: 34pt,
  dy: 32pt,
  box(width: 230pt, [
    #set par(spacing: 0pt)
    // Dual accent bar (Zig cyan + CAIE amber)
    #stack(
      dir: ltr,
      spacing: 4pt,
      rect(width: 30pt, height: 2.2pt, fill: c-cyan, radius: 1pt),
      rect(width: 12pt, height: 2.2pt, fill: c-orange, radius: 1pt),
    )
    #v(11pt)
    #text(font: "IBM Plex Mono", size: 6.7pt, weight: "bold", fill: c-cyan, tracking: 0.1em)[
      ZIG 0.17 · TYPST PDF/UA-1 · AGENT SKILLS
    ]
    #v(10pt)
    #par(leading: 0.42em)[
      #text(font: "Cormorant Garamond", size: 36pt, weight: "bold", fill: c-white)[Verifiable]
      #linebreak()
      #text(font: "Cormorant Garamond", size: 36pt, weight: "bold", fill: c-white)[Editorial]
    ]
    #v(13pt)
    #par(leading: 0.58em)[
      #text(font: "Inter", size: 9.2pt, fill: c-silver)[
        Zero-mock monographs, academic journals, magazines & executive decks behind a #text(fill: c-white, weight: "semibold")[5-gate cryptographic court].
      ]
    ]
    #v(18pt)

    // 2x2 capability pills (factual metrics, zero fluff)
    #let pill(dot-col, label) = box(
      width: 100%,
      fill: c-panel,
      stroke: 0.6pt + c-border,
      radius: 3.5pt,
      inset: (x: 7pt, y: 5.5pt),
      align(left + horizon, stack(
        dir: ltr,
        spacing: 5pt,
        box(baseline: -1.2pt, circle(radius: 2.2pt, fill: dot-col)),
        text(font: "IBM Plex Mono", size: 6.2pt, weight: "semibold", fill: c-white)[#label],
      )),
    )

    #grid(
      columns: (1fr, 1fr),
      column-gutter: 6pt,
      row-gutter: 6pt,
      pill(c-cyan, "5-GATE ZIG COURT"),
      pill(c-emerald, "VERAPDF 106/106"),
      pill(c-orange, "PDF SAMPLE INJECT"),
      pill(c-gold, "8 ARCHETYPES"),
    )

    #v(18pt)
    #line(length: 100%, stroke: 0.5pt + c-border)
    #v(8pt)
    #text(font: "IBM Plex Mono", size: 6.9pt, fill: c-muted)[
      github.com/gke0op/verifiable-editorial-skills
    ]
  ]),
)
