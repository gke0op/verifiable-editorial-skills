// Auto-dissected Typst 0.15.1 PDF/UA-1 Archetype Skeleton
// Source Sample: COSMOS_MOBILE_PRIMER_UA1.pdf (SHA-256: 9a032663b6923c07)
// Archetype Slug: mobile-primer (mobile_portrait_9x16, dark polarity)

#let data = json("../data/summary_metrics.json")
#let ledger = json("../data/provenance_ledger.json")
#let m = data.metrics

#let c-bg     = rgb("#000808")
#let c-tint   = rgb("#0e1a20")
#let c-ink    = rgb("#d0d8e0")
#let c-muted  = rgb("#c4ceda")
#let c-acc1   = rgb("#88c8f0")
#let c-acc2   = rgb("#e8c078")
#let c-rule   = rgb("#2A394A")

#set document(
  title: data.metadata.title,
  author: data.metadata.author,
)
#set page(
  width: 360.0pt,
  height: 640.0pt,
  fill: c-bg,
  margin: (top: 28.0pt, bottom: 33.0pt, left: 28.0pt, right: 28.0pt),
  footer: context {
    let pg = counter(page).get().first()
    let tot = counter(page).final().first()
    line(length: 100%, stroke: 0.5pt + c-rule)
    v(3pt)
    grid(
      columns: (1fr, auto),
      align: (left, right),
      text(font: "Inter", size: 6.8pt, fill: c-muted, tracking: 0.08em)[#upper(data.metadata.kicker)],
      text(font: "Cormorant Garamond", size: 10.5pt, weight: "bold", fill: c-ink, number-type: "lining")[#pg / #tot],
    )
  },
)

#set text(font: "Inter", size: 10.1pt, fill: c-ink, lang: "en", region: "US")
#set par(leading: 0.6em, spacing: 0.8em, justify: false)
// === PAGE 1: COVER HERO (Dissected Archetype: cover_hero) ===
#line(length: 100%, stroke: 2.2pt + c-acc1)
#v(6pt)
#text(font: "Inter", size: 7.2pt, weight: "bold", fill: c-acc1, tracking: 0.14em)[#upper(data.metadata.kicker)]
#v(4pt)
#text(font: "Cormorant Garamond", size: 26.0pt, weight: "bold", fill: c-ink, number-type: "lining")[#data.metadata.title]
#v(4pt)
#text(size: 10.2pt, style: "italic", fill: c-muted)[#data.metadata.subtitle]
#v(12pt)

#grid(
  columns: (1fr, 1fr, 1fr),
  gutter: 10pt,
  ..for kpi in data.kpis {
    (box(
      width: 100%,
      fill: c-tint,
      inset: 10pt,
      stroke: (top: 1.5pt + c-acc1),
      [
        #text(font: "Inter", size: 6.5pt, weight: "bold", fill: c-acc1, tracking: 0.12em)[#upper(kpi.label)]
        #v(4pt)
        #text(font: "Cormorant Garamond", size: 19pt, weight: "bold", fill: c-ink, number-type: "lining")[#kpi.display_value]
        #v(3pt)
        #text(font: "Inter", size: 6.6pt, fill: c-muted)[#kpi.note]
      ],
    ),)
  }
)
#v(14pt)
#grid(
  columns: (1.55fr, 1fr),
  gutter: 16pt,
  [
    #text(font: "Inter", size: 7.5pt, weight: "bold", fill: c-acc2, tracking: 0.1em)[AUDITED EXECUTIVE BRIEF]
    #v(4pt)
    Every quantitative figure on this canvas binds natively to `data/summary_metrics.json` across *#ledger.len()* cryptographic provenance tuples verified by `vedit latch`.
  ],
  box(
    fill: c-tint,
    inset: 10pt,
    stroke: (left: 2pt + c-acc2),
    [
      #text(font: "Inter", size: 6.8pt, weight: "bold", fill: c-acc2, tracking: 0.12em)[DESIGN DNA PROVENANCE]
      #v(4pt)
      Cloned from dissected archetype `mobile-primer` (360×640 pt, dark polarity, verified WCAG contrast) via #link("https://github.com/gke0op/verifiable-editorial-skills")[verifiable-editorial-skills].
    ],
  ),
)

#pagebreak()

// === PAGE 2: AUDITED DATA LEDGER & SHA-256 PROVENANCE ===
#text(font: "Cormorant Garamond", size: 17pt, weight: "bold", fill: c-acc1, number-type: "lining")[Audited Metrics & Cryptographic Ledger]
#v(3pt)
#line(length: 100%, stroke: 0.8pt + c-acc1)
#v(10pt)
#figure(
  table(
    columns: (1.6fr, 0.9fr, 1.4fr, 0.9fr),
    inset: (x: 5pt, y: 5pt),
    align: (left, right, left, left),
    stroke: (x, y) => (
      top: if y == 0 { 1.1pt + c-ink } else if y == 1 { 0.75pt + c-ink } else { 0.3pt + c-rule },
      bottom: if y == ledger.len() { 1.1pt + c-ink } else { none },
    ),
    table.header(
      text(font: "Inter", size: 6.6pt, weight: "bold", fill: c-acc1)[METRIC ID],
      text(font: "Inter", size: 6.6pt, weight: "bold", fill: c-acc1)[VALUE],
      text(font: "Inter", size: 6.6pt, weight: "bold", fill: c-acc1)[RAW SOURCE],
      text(font: "Inter", size: 6.6pt, weight: "bold", fill: c-acc1)[SHA-256 (12)],
    ),
    ..for r in ledger {
      (
        text(font: "IBM Plex Mono", size: 6.8pt, fill: c-ink)[#r.metric_id],
        text(font: "IBM Plex Mono", size: 6.8pt, weight: "semibold", fill: c-acc1)[#r.value],
        text(font: "IBM Plex Mono", size: 6.8pt, fill: c-muted)[#r.source_document],
        text(font: "IBM Plex Mono", size: 6.8pt, fill: c-acc2)[#r.raw_file_sha256.slice(0, 12)],
      )
    }
  ),
  caption: text(size: 7.6pt, style: "italic", fill: c-muted)[Rule 4 atomic provenance ledger rendered natively from `data/provenance_ledger.json`.],
)
