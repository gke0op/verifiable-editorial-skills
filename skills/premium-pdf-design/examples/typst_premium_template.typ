// Verifiable Editorial — Pure Typst 0.15.1 Dual-Polarity Starter (`typst_premium_template.typ`)
// Compile: typst compile --pdf-standard ua-1 --font-path ~/.cache/verifiable-editorial/fonts typst_premium_template.typ out.pdf
// Zero boxes, subtle opposite-corner brackets (┌ ... ┘), matte OLED bold grey (#B6C0CE), 2-line bottom bar.

#let mode = sys.inputs.at("mode", default: "dark") // "dark" (OLED void) or "light" (Swiss ivory)
#let is-dark = mode == "dark"

#let bg-col     = if is-dark { rgb("#07090F") } else { rgb("#FAF8F4") }
#let ink-title  = if is-dark { rgb("#E2E7EF") } else { rgb("#0F2942") }
#let ink-body   = if is-dark { rgb("#D6DCE6") } else { rgb("#2A3440") }
#let ink-bold   = if is-dark { rgb("#B6C0CE") } else { rgb("#0F2942") }
#let ink-muted  = if is-dark { rgb("#9AA8BC") } else { rgb("#52606E") }
#let acc-main   = if is-dark { rgb("#E8C078") } else { rgb("#035E9E") }
#let acc-link   = if is-dark { rgb("#8CC8F0") } else { rgb("#035E9E") }
#let reticle    = if is-dark { rgb("#2B384E") } else { rgb("#C8C2B6") }

#set document(
  title: "Verifiable Editorial Starter Template",
  author: "Verifiable Editorial Skills (Zig 0.17 + Typst PDF/UA-1)",
)

#set text(font: "Inter", size: 10.6pt, fill: ink-body, lang: "en", hyphenate: false)
#show strong: set text(weight: "semibold", fill: ink-bold)
#set par(leading: 0.66em, spacing: 0.85em, justify: false)

#set page(
  width: 360pt,
  height: 640pt,
  margin: (top: 28pt, bottom: 28pt, left: 28pt, right: 28pt),
  fill: bg-col,
  footer: context {
    let p = counter(page).get().first()
    let tot = counter(page).final().first()
    grid(
      columns: (1fr, auto),
      text(font: "IBM Plex Mono", size: 7.0pt, fill: ink-muted)[VERIFIABLE EDITORIAL],
      text(font: "IBM Plex Mono", size: 7.0pt, fill: ink-muted)[#p / #tot],
    )
  },
)

#let corner-frame(body, arm-x: 42pt, arm-y: 26pt, stroke-color: reticle) = {
  context layout(avail => {
    let inner = block(width: avail.width - 26pt, body)
    let m = measure(inner)
    let h = m.height + 20pt
    let vy = calc.min(arm-y, h * 0.62)
    block(width: 100%, height: h, breakable: false, {
      place(top + left, line(length: arm-x, stroke: 0.58pt + stroke-color))
      place(top + left, line(angle: 90deg, length: vy, stroke: 0.58pt + stroke-color))
      place(bottom + right, line(length: arm-x, stroke: 0.58pt + stroke-color))
      place(bottom + right, line(angle: 90deg, length: vy, stroke: 0.58pt + stroke-color))
      place(top + left, dx: 13pt, dy: 10pt, inner)
    })
  })
}

#let bare-link(url, label) = link(url)[
  #box(inset: (x: 2pt, y: 4.5pt))[
    #underline(offset: 2.5pt, stroke: 0.45pt + reticle)[
      #text(font: "IBM Plex Mono", size: 7.3pt, fill: acc-link)[#label ↗]
    ]
  ]
]

#text(font: "IBM Plex Mono", size: 7.4pt, fill: acc-main, tracking: 0.12em)[ZERO-PYTHON · ZIG 0.17 + TYPST PDF/UA-1]
#v(4pt)
#text(font: "Source Serif 4", size: 20pt, weight: "semibold", fill: ink-title, number-type: "lining")[
  Zero-Box Minimalist Editorial Starter
]
#v(10pt)

Every figure loads natively via `#json(...)` from a SHA-256 sealed pipeline and clears the *6-gate Zig court* before release.

#v(10pt)
#corner-frame[
  #text(font: "IBM Plex Mono", size: 7.0pt, weight: "semibold", fill: acc-main, tracking: 0.08em)[OPEN ARCHITECTURAL FRAME]
  #v(4pt)
  Opposite-corner brackets hold structured equations, notes, and provenance receipts with *zero heavy boxes* and *zero glare*.
]

#v(1fr)
#line(length: 100%, stroke: 0.45pt + reticle)
#v(2pt)
#grid(
  columns: (auto, 1fr),
  column-gutter: 10pt,
  align: (left + horizon, left + horizon),
  text(font: "IBM Plex Mono", size: 6.4pt, fill: ink-muted, tracking: 0.1em)[SOURCES],
  bare-link("https://github.com/gke0op/verifiable-editorial-skills", "VES Repository"),
)
