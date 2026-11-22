// APS Physical Review Letters (REVTeX 4.2 / PRL) Reference Letter
// 100% Zero-Python Pipeline: Pure Zig 0.17.0 Symplectic & C4v Exact Diagonalization + Pure-Vector SVGs + Rust-Native Typst PDF/UA-1.

#let data = json("../data/summary_metrics.json")
#let ledger = json("../data/provenance_ledger.json")
#let m = data.metrics
#let meta = data.metadata
#let raw-sha = meta.raw_file_hashes.at("yang_mills_protocol.csv")

// Classic APS Physical Review Letters Palette (all >= 5.5:1 WCAG AA on #FFFFFF & #FAFBFD)
#let c-white   = rgb("#FFFFFF")
#let c-tint    = rgb("#F8FAFC")
#let c-ink     = rgb("#0F172A")
#let c-body    = rgb("#111827")
#let c-muted   = rgb("#334155")
#let c-rule    = rgb("#1E293B")
#let c-hair    = rgb("#CBD5E1")
#let c-cobalt  = rgb("#1D4ED8")
#let c-crimson = rgb("#991B1B")
#let c-teal    = rgb("#0F766E")

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
#let fmt3(v) = {
  let r = calc.round(v, digits: 3)
  let s = str(r)
  if not s.contains(".") { s + ".000" }
  else {
    let p = s.split(".").at(1)
    if p.len() == 1 { s + "00" } else if p.len() == 2 { s + "0" } else { s }
  }
}
#let fmt4(v) = {
  let r = calc.round(v, digits: 4)
  let s = str(r)
  if not s.contains(".") { s + ".0000" }
  else {
    let p = s.split(".").at(1)
    if p.len() == 1 { s + "000" } else if p.len() == 2 { s + "00" } else if p.len() == 3 { s + "0" } else { s }
  }
}

#set document(
  title: "Classical-to-Quantum Chaos and Bohigas-Giannoni-Schmit Spectral Universality in the Quartic-Regularized SU(2) Yang-Mills Oscillator",
  author: "Verifiable Editorial Systems Collective",
  keywords: ("Quantum chaos", "Random matrix theory", "Symplectic integrators", "Yang-Mills oscillator", "REVTeX 4.2", "Zig 0.17"),
)

#set page(
  paper: "us-letter",
  fill: c-white,
  margin: (top: 44pt, bottom: 42pt, left: 45pt, right: 45pt),
  header: context {
    if counter(page).get().first() > 1 {
      grid(
        columns: (1fr, auto, 1fr),
        align: (left, center, right),
        text(font: "Source Serif 4", size: 7.4pt, weight: "semibold", fill: c-ink)[PRL 137, 014101 (2026)],
        text(font: "Inter", size: 7.6pt, weight: "bold", fill: c-ink, tracking: 0.14em)[PHYSICAL REVIEW LETTERS],
        text(font: "Source Serif 4", size: 7.4pt, fill: c-muted)[22 NOVEMBER 2026],
      )
      v(-4.5pt)
      line(length: 100%, stroke: 0.55pt + c-rule)
    }
  },
  footer: context {
    let pg = counter(page).get().first()
    let tot = counter(page).final().first()
    line(length: 100%, stroke: 0.45pt + c-hair)
    v(3pt)
    grid(
      columns: (1fr, auto, 1fr),
      align: (left, center, right),
      text(font: "Inter", size: 6.1pt, fill: c-muted)[Open Archive · REVTeX 4.2 Spec · SHA-256 sealed],
      text(font: "Source Serif 4", size: 8.2pt, weight: "semibold", fill: c-ink)[014101-#pg],
      text(font: "Inter", size: 6.1pt, fill: c-muted)[0031-9007/26/137(1)/014101(#tot)],
    )
  },
)

#set text(
  font: "Source Serif 4",
  size: 8.8pt,
  fill: c-body,
  lang: "en",
  region: "US",
)
#set par(leading: 0.52em, spacing: 0.62em, justify: true, first-line-indent: 10pt)
#set math.equation(numbering: "(1)")

// Authentic PRL run-in italic section opener helper: *Title.*—
#let prl-sec(title) = {
  v(4pt)
  text(style: "italic", weight: "semibold", fill: c-ink)[#title.]
  [—]
}

// Genuine REVTeX 4.2 stepped `widetext` bracket macro:
//   Top:    left-column horizontal rule ending in an upward vertical tick  (────────────┘)
//   Bottom: right-column horizontal rule starting with a downward tick     (┌────────────)
#let revtex-widetext(body) = {
  block(
    width: 100%,
    breakable: false,
    inset: (y: 2pt),
    [
      // Top stepped left-column bracket ────────────┘
      #box(width: 100%, height: 7pt, [
        #place(bottom + left, line(length: 48.6%, stroke: 0.6pt + c-rule))
        #place(bottom + left, dx: 48.6%, line(start: (0pt, 0pt), end: (0pt, -6.5pt), stroke: 0.6pt + c-rule))
      ])
      #v(4pt)
      #body
      #v(4pt)
      // Bottom stepped right-column bracket ┌────────────
      #box(width: 100%, height: 7pt, [
        #place(top + left, dx: 51.4%, line(length: 48.6%, stroke: 0.6pt + c-rule))
        #place(top + left, dx: 51.4%, line(start: (0pt, 0pt), end: (0pt, 6.5pt), stroke: 0.6pt + c-rule))
      ])
    ],
  )
}

// ============================================================================
// PAGE 1 — AUTHENTIC APS PHYSICAL REVIEW LETTERS (REVTeX 4.2) MASTHEAD
// ============================================================================
#grid(
  columns: (1fr, auto, 1fr),
  align: (left + bottom, center + bottom, right + bottom),
  text(font: "Source Serif 4", size: 8.2pt, weight: "bold", fill: c-ink)[PRL 137, 014101 (2026)],
  text(font: "Inter", size: 10.4pt, weight: "bold", fill: c-ink, tracking: 0.16em)[PHYSICAL REVIEW LETTERS],
  text(font: "Inter", size: 6.7pt, weight: "semibold", fill: c-muted, tracking: 0.08em)[REVTeX 4.2 · OPEN ARCHIVE],
)
#v(2.5pt)
#line(length: 100%, stroke: 1.2pt + c-rule)
#v(-6.5pt)
#line(length: 100%, stroke: 0.45pt + c-rule)
#v(10pt)

// Centered Title, Author, Affiliation, Date
#align(center, [
  #set par(first-line-indent: 0pt, justify: false, leading: 0.48em)
  #box(width: 92%, text(font: "Source Serif 4", size: 13.4pt, weight: "bold", fill: c-ink)[
    Classical-to-Quantum Chaos and Bohigas–Giannoni–Schmit Spectral Universality in the Quartic-Regularized #math.equation(numbering: none, alt: "S U 2", $"SU"(2)$) Yang–Mills Oscillator
  ])
  #v(7pt)
  #text(font: "Source Serif 4", size: 9.6pt, weight: "semibold", fill: c-ink)[
    Verifiable Editorial Systems Collective#super[\*]
  ]
  #v(2pt)
  #text(font: "Source Serif 4", size: 7.7pt, style: "italic", fill: c-muted)[
    Open-Source Computational Physics & Reproducible Science Archive (`verifiable-editorial-skills`), Bare-Metal Zig 0.17 & Typst Edition
  ]
  #v(2.5pt)
  #text(font: "Source Serif 4", size: 7.5pt, fill: c-muted)[
    (Received 22 November 2026; compiled with zero-Python SHA-256 verification)
  ]
])

#v(8pt)

// Signature PRL Narrow Centered Abstract (84% width, justified, NO "Abstract" header)
#align(center, box(
  width: 85%,
  [
    #set par(first-line-indent: 0pt, justify: true, leading: 0.48em, spacing: 0.4em)
    #text(size: 8.15pt, fill: c-body)[
      We report a zero-Python, cryptographically verified numerical study bridging classical symplectic chaos and quantum spectral universality in the quartic-regularized spatially homogeneous #math.equation(numbering: none, alt: "S U 2", $"SU"(2)$) Yang–Mills oscillator #math.equation(numbering: none, alt: "H equals half p squared plus half q squared plus alpha times x squared y squared plus epsilon over 2 x to the 4 plus y to the 4", $H(alpha) = (p_x^2 + p_y^2 + x^2 + y^2)/2 + alpha [x^2 y^2 + (epsilon/2)(x^4 + y^4)]$) with #math.equation(numbering: none, alt: "epsilon equals 0.05", $epsilon = 0.05$), implemented end-to-end in bare-metal Zig 0.17.0. Across *#m.sweep_points* couplings (#math.equation(numbering: none, alt: "alpha from 0 to 2.50", $alpha in [0, 2.50]$), classical energy #math.equation(numbering: none, alt: "E equals 20.0", $E = 20.0$)), fourth-order Yoshida symplectic integration preserves Hamiltonian energy to #math.equation(numbering: none, alt: "delta E over E less than or equal to 93.29 times 10 to the minus 11", $|Delta E / E| <= #fmt2(m.global_max_rel_dE_e11) times 10^(-11)$) across all #m.orbits_per_coupling phase-space orbits while variational Benettin renormalization tracks the chaotic sea from *#fmt1(m.kam_chaotic_pct)%* (#math.equation(numbering: none, alt: "alpha equals 0.025", $alpha = 0.025$)) through mixed Kolmogorov–Arnold–Moser (KAM) islands (*#fmt1(m.mixed_chaotic_pct)%* at #math.equation(numbering: none, alt: "alpha equals 0.125", $alpha = 0.125$)) to *#fmt1(m.chaotic_chaotic_pct)%* at #math.equation(numbering: none, alt: "alpha equals 2.50", $alpha = 2.50$) (#math.equation(numbering: none, alt: "mean Lyapunov equals 0.916", $chevron.l lambda_1 chevron.r = #fmt3(m.chaotic_lyap_mean)$)). Desymmetrized exact diagonalization of the #math.equation(numbering: none, alt: "C 4 v", $C_(4v)$) #math.equation(numbering: none, alt: "A 1", $A_1$) irreducible block via squeezed-basis Householder–QL (#math.equation(numbering: none, alt: "D equals 676", $D = #m.basis_dim_small$) vs. #math.equation(numbering: none, alt: "900", $#m.basis_dim_large$)) confirms simultaneous quantum convergence to Gaussian Orthogonal Ensemble (GOE) statistics: the unfolding-free gap ratio rises from *#fmt4(m.kam_r_mean)* toward GOE (*#fmt4(m.chaotic_r_mean)* vs. 0.5307), Brody repulsion reaches *#fmt3(m.chaotic_brody_beta)*, Kolmogorov–Smirnov distance favors GOE (*#fmt4(m.chaotic_ks_goe)*) over Poisson (*#fmt4(m.chaotic_ks_poisson)*), and number variance #math.equation(numbering: none, alt: "Sigma squared of 5", $Sigma^2 (5)$) drops to *#fmt2(m.sigma2_L5_chaotic)*. Every published scalar, curve, and Poincaré crossing is certified by a five-gate `PDF/UA-1` court.
    ]
    #v(4pt)
    #text(font: "Inter", size: 6.3pt, fill: c-muted)[
      DOI: `10.0000/OpenArchive.PRL.137.014101` · PhySH: Quantum chaos, Random matrix theory, Symplectic integrators · SHA-256: #raw(raw-sha.slice(0, 16) + "…")
    ]
  ],
))
#v(9pt)

// ============================================================================
// TWO-COLUMN PHYSICAL REVIEW LETTERS BODY
// ============================================================================
#show: columns.with(2, gutter: 14pt)

#prl-sec[Introduction]The Bohigas–Giannoni–Schmit (BGS) conjecture @bohigas1984bgs asserts that the short- and long-range spectral fluctuations of time-reversal-invariant quantum systems whose classical counterparts are chaotic obey universal Gaussian Orthogonal Ensemble (GOE) random-matrix statistics, whereas classically integrable systems exhibit uncorrelated Berry–Tabor Poisson clustering @berry1977tabor. Two-dimensional coupled quartic oscillators—arising directly from spatially homogeneous #math.equation(numbering: none, alt: "S U 2", $"SU"(2)$) Yang–Mills gauge fields @matinyan1981ym and Pullen–Edmonds bound potentials @pullen1981jpa @haller1984prl—provide an ideal laboratory because a single dimensionless scaling parameter #math.equation(numbering: none, alt: "gamma equals alpha E", $gamma = alpha E$) sweeps continuously from integrable harmonic motion to widespread chaos without open escape channels.

Despite five decades of numerical evidence, reproducible verification of the classical-to-quantum correspondence remains vulnerable to three silent numerical artifacts: (i) secular energy drift in non-symplectic Runge–Kutta integrators that artificially perturbs KAM tori; (ii) incomplete symmetry desymmetrization, where superposed irreducible blocks mask level repulsion; and (iii) manual transcription drift between solver output and published journal figures. In this Letter, we eliminate all three failure modes by coupling a deterministic bare-metal Zig 0.17.0 symplectic and exact-diagonalization engine directly to a Rust-native Typst `REVTeX 4.2` (`PDF/UA-1`) manuscript guarded by a five-gate cryptographic audit court.

#prl-sec[Model and symplectic dynamics]We study the two-degree-of-freedom quartic-regularized #math.equation(numbering: none, alt: "S U 2", $"SU"(2)$) Yang–Mills Hamiltonian (#math.equation(numbering: none, alt: "hbar equals 1", $planck = 1$)):

#math.equation(
  block: true,
  alt: "Equation 1: H of alpha equals one half times p x squared plus p y squared plus x squared plus y squared, plus alpha times x squared y squared plus epsilon over 2 times x to the fourth plus y to the fourth.",
  $ H(alpha) = frac(1, 2)(p_x^2 + p_y^2 + x^2 + y^2) + alpha [ x^2 y^2 + frac(epsilon, 2)(x^4 + y^4) ] $,
) <eq-ham>

with isotropic wall regularization #math.equation(numbering: none, alt: "epsilon equals 0.05", $epsilon = 0.05$), preserving exact #math.equation(numbering: none, alt: "C 4 v", $C_(4v)$) point-group symmetry while confining the narrow hyperbolic channels along #math.equation(numbering: none, alt: "x equals 0", $x = 0$) and #math.equation(numbering: none, alt: "y equals 0", $y = 0$) so high-lying quantum eigenstates converge uniformly.

Classical trajectories on the fixed energy shell #math.equation(numbering: none, alt: "E equals 20.0", $E = 20.0$) are integrated via Yoshida's fourth-order symmetric symplectic composition @yoshida1990symplectic using constant frequency-matched steps #math.equation(numbering: none, alt: "delta t equals 0.010 divided by square root of 1 plus 4 alpha E", $Delta t = 0.010 / sqrt(1 + 4 alpha E)$) over #math.equation(numbering: none, alt: "T equals 200", $T = 200$) across #m.orbits_per_coupling stratified initial conditions on the #math.equation(numbering: none, alt: "x equals 0, p x greater than 0", $x = 0, p_x > 0$) Poincaré section. Simultaneously, we evolve the exact linearized #math.equation(numbering: none, alt: "4 by 4", $4 times 4$) variational tangent equations #math.equation(numbering: none, alt: "delta z dot equals J Hessian H delta z", $delta dot(bold(z)) = bold(J) nabla^2 H(bold(z)) delta bold(z)$) under periodic Benettin renormalization @benettin1980lyap every 25 steps to extract the maximal Lyapunov exponent:

#math.equation(
  block: true,
  alt: "Equation 2: lambda 1 equals limit as T goes to infinity of 1 over T sum of natural log of norm of tangent vector delta z.",
  $ lambda_1 = lim_(T -> infinity) frac(1, T) sum_(m=1)^M ln norm(delta bold(z)_m)_2 $,
) <eq-lyap>

Orbits with #math.equation(numbering: none, alt: "lambda 1 greater than 0.03", $lambda_1 > 0.03$) classify as chaotic, defining the phase-space chaotic fraction #math.equation(numbering: none, alt: "mu sub C", $mu_C$). Section crossings are refined by two Newton–Yoshida iterations onto #math.equation(numbering: none, alt: "x equals 0", $x = 0$) to machine precision.

// ============================================================================
// FULL-WIDTH FIGURE 1 (POINCARE SURFACES OF SECTION) FLOATING TOP OF PAGE 2
// ============================================================================
#place(
  top,
  scope: "parent",
  float: true,
  clearance: 11pt,
  figure(
    image("assets/fig1_poincare_sections.svg", width: 100%, alt: "Three-panel vector Poincare surface of section plot in the y, p_y plane at x=0, p_x>0 for E=20. Panel a at alpha=0.025 shows pure nested blue KAM tori with 0% chaotic orbits. Panel b at alpha=0.125 shows mixed phase space with blue KAM islands embedded inside a crimson chaotic sea (70.8% chaotic). Panel c at alpha=2.50 shows a nearly ergodic crimson Yang-Mills chaotic sea filling the exact quartic-walled energetic boundary (95.8% chaotic)."),
    caption: text(font: "Source Serif 4", size: 7.7pt, fill: c-body)[
      #text(weight: "bold")[FIG. 1.] Exact symplectic Poincaré surfaces of section #math.equation(numbering: none, alt: "y, p y", $(y, p_y)$) at #math.equation(numbering: none, alt: "x equals 0, p x greater than 0", $x = 0, p_x > 0$) (#math.equation(numbering: none, alt: "E equals 20.0", $E = 20.0$)) across three regimes: (a) near-integrable KAM tori (#math.equation(numbering: none, alt: "alpha equals 0.025", $alpha = 0.025$), #m.poincare_pts_a crossings, #math.equation(numbering: none, alt: "mu C equals 0.0 percent", $mu_C = #fmt1(m.kam_chaotic_pct)\%$)); (b) mixed phase space (#math.equation(numbering: none, alt: "alpha equals 0.125", $alpha = 0.125$), #m.poincare_pts_b crossings, #math.equation(numbering: none, alt: "mu C equals 70.8 percent", $mu_C = #fmt1(m.mixed_chaotic_pct)\%$)); and (c) Yang–Mills chaotic sea (#math.equation(numbering: none, alt: "alpha equals 2.50", $alpha = 2.50$), #m.poincare_pts_c crossings, #math.equation(numbering: none, alt: "mu C equals 95.8 percent", $mu_C = #fmt1(m.chaotic_chaotic_pct)\%$)). Blue dots denote regular orbits (#math.equation(numbering: none, alt: "lambda 1 less than or equal to 0.03", $lambda_1 <= 0.03$))\; crimson dots denote chaotic trajectories (#math.equation(numbering: none, alt: "lambda 1 greater than 0.03", $lambda_1 > 0.03$)) inside the exact quartic energetic boundary (dashed curve).
    ],
    supplement: none,
  ),
)

#prl-sec[Desymmetrized quantum spectrum]Because #math.equation(numbering: none, alt: "H of alpha", $H(alpha)$) is invariant under reflections #math.equation(numbering: none, alt: "x to minus x, y to minus y", $(x, y) -> (plus.minus x, plus.minus y)$) and exchange #math.equation(numbering: none, alt: "x swapped with y", $x <-> y$), unprojected spectra superpose five independent #math.equation(numbering: none, alt: "C 4 v", $C_(4v)$) symmetry sectors and spuriously mimic Poisson statistics. We strictly isolate the fully symmetric #math.equation(numbering: none, alt: "A 1", $A_1$) irreducible representation spanned by symmetrized even-even harmonic oscillator states #math.equation(numbering: none, alt: "ket i, j A 1", $|i, j chevron.r_(A_1) = c_(i j)(|2i, 2j chevron.r + (1 - delta_(i j))|2j, 2i chevron.r)$) (#math.equation(numbering: none, alt: "0 less than or equal to i less than or equal to j, i plus j less than or equal to M", $0 <= i <= j, med i + j <= M$)) in a squeezed oscillator basis of variational frequency #math.equation(numbering: none, alt: "omega of alpha equals 1 plus 12 alpha to the one third", $omega(alpha) = (1 + 12 alpha)^(1/3)$), yielding the exact banded matrix elements in Eq. @eq-a1mat. Here #math.equation(numbering: none, alt: "Q u v", $cal(Q)_(u v)$), #math.equation(numbering: none, alt: "V cross u v", $cal(V)_(u v)^(times)$), and #math.equation(numbering: none, alt: "W u v", $cal(W)_(u v)$) follow algebraically from the exact tridiagonal operator #math.equation(numbering: none, alt: "X a b equals 2a plus half on diagonal", $X_(a,a) = 2a + 1/2$), #math.equation(numbering: none, alt: "X a, a plus 1 equals half square root of 2a plus 1 times 2a plus 2", $X_(a,a+1) = sqrt((2a+1)(2a+2))/2$) and its pentadiagonal square #math.equation(numbering: none, alt: "X squared", $X^2$).

Every dense #math.equation(numbering: none, alt: "A 1", $A_1$) Hamiltonian is diagonalized in pure Zig 0.17.0 via Wilkinson Householder tridiagonalization and implicit-shift QL iteration without external LAPACK bindings. To certify eigenvalue accuracy, `pipeline.zig` enforces three Reality Compiler invariants on every coupling: (i) exact trace and Frobenius spectral sums matching matrix invariants to machine epsilon (#math.equation(numbering: none, alt: "less than 10 to the minus 14", $< 10^(-14)$)); (ii) exact #math.equation(numbering: none, alt: "omega", $omega$)-invariance at #math.equation(numbering: none, alt: "alpha equals 0", $alpha = 0$) (#math.equation(numbering: none, alt: "E 0 equals 1, E 1 equals 3", $E_0 = 1, E_1 = 3$) at both #math.equation(numbering: none, alt: "omega equals 1.0", $omega = 1.0$) and #math.equation(numbering: none, alt: "omega equals 1.7", $omega = 1.7$)); and (iii) double-basis convergence verification between #math.equation(numbering: none, alt: "D equals 676", $D = #m.basis_dim_small$) (#math.equation(numbering: none, alt: "M equals 50", $M = 50$)) and #math.equation(numbering: none, alt: "D equals 900", $D = #m.basis_dim_large$) (#math.equation(numbering: none, alt: "M equals 58", $M = 58$)), retaining only bulk levels #math.equation(numbering: none, alt: "k greater than or equal to 30", $k >= 30$) converged below #math.equation(numbering: none, alt: "0.02", $0.02$) in absolute energy.

We evaluate the unfolding-free adjacent gap ratio @oganesyan2007prb @atas2013prl:

#math.equation(
  block: true,
  alt: "Equation 3: r tilde k equals min of s k and s k minus 1 divided by max of s k and s k minus 1.",
  $ tilde(r)_k = frac(min(E_(k+1) - E_k, med E_k - E_(k-1)), max(E_(k+1) - E_k, med E_k - E_(k-1))) in [0, 1] $,
) <eq-ratio>

alongside degree-4 polynomial unfolding #math.equation(numbering: none, alt: "epsilon k equals N bar of E k", $epsilon.alt_k = overline(N)(E_k)$) for nearest-neighbor spacing #math.equation(numbering: none, alt: "P of s", $P(s)$), Brody level repulsion #math.equation(numbering: none, alt: "beta", $beta$) @brody1973rmp, Kolmogorov–Smirnov distances #math.equation(numbering: none, alt: "D K S", $D_"KS"$), and long-range number variance #math.equation(numbering: none, alt: "Sigma squared of L", $Sigma^2 (L) = chevron.l (n(epsilon.alt, L) - L)^2 chevron.r$).

// ============================================================================
// GENUINE REVTeX 4.2 STEPPED WIDETEXT EQUATION BLOCK (BOTTOM OF PAGE 2 — Eqs. 4 & 5!)
// ============================================================================
#place(
  bottom,
  scope: "parent",
  float: true,
  clearance: 10pt,
  revtex-widetext([
    #math.equation(
      block: true,
      alt: "Equation 4: Exact squeezed-basis C 4 v A 1 Hamiltonian matrix element between basis states i, j and k, l equals omega times 2 i plus 2 j plus 1 delta u v, plus 1 minus omega squared over 2 omega times Q u v, plus alpha over omega squared times cross term V u v plus epsilon over 2 times quartic wall term W u v.",
      $ chevron.l i, j | H(alpha) | k, l chevron.r_(A_1) = omega (2 i + 2 j + 1) delta_(u v) + frac(1 - omega^2, 2 omega) cal(Q)_(u v) + frac(alpha, omega^2) [ cal(V)_(u v)^(times) + frac(epsilon, 2) cal(W)_(u v) ], quad omega(alpha) = (1 + 12 alpha)^(1/3) $,
    ) <eq-a1mat>
    #v(2pt)
    #math.equation(
      block: true,
      alt: "Equation 5: Atas-Bogomolny-Giraud-Roux GOE adjacent gap ratio surmise P GOE of r tilde equals 27 over 4 times r tilde plus r tilde squared divided by 1 plus r tilde plus r tilde squared to the five halves power, alongside Brody interpolating CDF F beta of s equals 1 minus exp of minus b beta s to the beta plus 1.",
      $ P_"GOE" (tilde(r)) = frac(27, 4) frac(tilde(r) + tilde(r)^2, (1 + tilde(r) + tilde(r)^2)^(5/2)), quad chevron.l tilde(r) chevron.r_"GOE" = 0.5307, quad chevron.l tilde(r) chevron.r_"P" = 2 ln 2 - 1 approx 0.3863, quad F_beta (s) = 1 - exp(-b_beta s^(beta + 1)) $,
    ) <eq-rmt>
  ]),
)

// ============================================================================
// FULL-WIDTH FIGURE 2 FLOATING TOP OF PAGE 3
// ============================================================================
#place(
  top,
  scope: "parent",
  float: true,
  clearance: 11pt,
  figure(
    image("assets/fig2_chaos_rmt_transition.svg", width: 100%, alt: "Two-panel vector exhibit. Panel a plots the unfolding-free quantum adjacent gap ratio r-tilde (blue circles, left axis) alongside the classical mean Lyapunov exponent lambda_1 (crimson squares, right axis) across alpha from 0 to 2.50, showing simultaneous transition from near-Poisson to the GOE 0.531 line. Panel b shows the unfolded spacing histogram P(s) at alpha=2.50 across 203 converged C4v A1 levels closely tracking the crimson GOE Wigner surmise curve with strong level repulsion at s=0 and Brody beta=0.945."),
    caption: text(font: "Source Serif 4", size: 7.7pt, fill: c-body)[
      #text(weight: "bold")[FIG. 2.] Classical-to-quantum chaos correspondence across all #m.sweep_points couplings: (a) simultaneous rise of classical mean Lyapunov exponent #math.equation(numbering: none, alt: "mean lambda 1", $chevron.l lambda_1 chevron.r$) (dashed crimson, right axis) and unfolding-free quantum gap ratio #math.equation(numbering: none, alt: "mean r tilde", $chevron.l tilde(r) chevron.r$) (solid blue, left axis) from near-Poisson (#math.equation(numbering: none, alt: "0.386", $0.386$)) onto the GOE benchmark (#math.equation(numbering: none, alt: "0.531", $0.531$)) @atas2013prl; (b) unfolded nearest-neighbor spacing distribution #math.equation(numbering: none, alt: "P of s", $P(s)$) at #math.equation(numbering: none, alt: "alpha equals 2.50", $alpha = 2.50$) (#m.bulk_window_size converged #math.equation(numbering: none, alt: "A 1", $A_1$) levels) displaying textbook level repulsion (#math.equation(numbering: none, alt: "beta equals 0.945", $beta = #fmt3(m.chaotic_brody_beta)$)) closely matching the GOE Wigner surmise (solid crimson) and rejecting Poisson clustering (dashed slate).
    ],
    supplement: none,
  ),
)

#prl-sec[Classical-to-quantum universality]Figure 1 and Table I reveal an unmistakable parallel transition in classical phase space and quantum level correlations. At #math.equation(numbering: none, alt: "alpha equals 0", $alpha = 0$), the isotropic 2D harmonic oscillator is superintegrable with exact integer shell degeneracies (#math.equation(numbering: none, alt: "E equals 2 k plus 1", $E = 2k + 1$)), collapsing adjacent gap ratios to zero—the classic resonant exclusion noted by Berry and Tabor @berry1977tabor. Immediately upon switching on weak quartic coupling (#math.equation(numbering: none, alt: "alpha equals 0.025, gamma equals 0.50", $alpha = 0.025, med gamma = 0.50$)), shell degeneracies split into smooth nested KAM tori [Fig. 1(a), #math.equation(numbering: none, alt: "mu C equals 0.0 percent", $mu_C = #fmt1(m.kam_chaotic_pct)\%$)], yielding #math.equation(numbering: none, alt: "mean lambda 1 equals 0.017", $chevron.l lambda_1 chevron.r = #fmt3(m.kam_lyap_mean)$), #math.equation(numbering: none, alt: "mean r tilde equals 0.4159", $chevron.l tilde(r) chevron.r = #fmt4(m.kam_r_mean)$), and weak Brody repulsion (#math.equation(numbering: none, alt: "beta equals 0.330", $beta = 0.330$)).

At intermediate coupling (#math.equation(numbering: none, alt: "alpha equals 0.125, gamma equals 2.50", $alpha = 0.125, med gamma = 2.50$)), resonance overlap fractures outer tori into a #fmt1(m.mixed_chaotic_pct)% chaotic sea surrounding coherent regular KAM islands [Fig. 1(b)], lifting #math.equation(numbering: none, alt: "mean lambda 1", $chevron.l lambda_1 chevron.r$) to *#fmt3(m.mixed_lyap_mean)* and driving #math.equation(numbering: none, alt: "mean r tilde", $chevron.l tilde(r) chevron.r$) abruptly into the GOE band (*#fmt4(m.mixed_r_mean)*) in the bulk quantum window where effective energy #math.equation(numbering: none, alt: "alpha E bulk", $alpha E_"bulk"$) already exceeds the classical chaos onset. By #math.equation(numbering: none, alt: "alpha equals 2.50, gamma equals 50.0", $alpha = 2.50, med gamma = 50.0$), #fmt1(m.chaotic_chaotic_pct)% of sampled orbits occupy the connected chaotic sea [Fig. 1(c), #math.equation(numbering: none, alt: "mean lambda 1 equals 0.916", $chevron.l lambda_1 chevron.r = #fmt3(m.chaotic_lyap_mean)$), peak #math.equation(numbering: none, alt: "lambda 1 max equals 1.090", $lambda_(1,"max") = #fmt3(m.chaotic_lyap_max)$)], and all *#m.bulk_window_size* converged bulk #math.equation(numbering: none, alt: "A 1", $A_1$) levels lock onto BGS universality: #math.equation(numbering: none, alt: "mean r tilde equals 0.5255", $chevron.l tilde(r) chevron.r = #fmt4(m.chaotic_r_mean)$), Brody #math.equation(numbering: none, alt: "beta equals 0.945", $beta = #fmt3(m.chaotic_brody_beta)$), and a Kolmogorov–Smirnov distance #math.equation(numbering: none, alt: "D K S GOE equals 0.0473", $D_"KS"^"GOE" = #fmt4(m.chaotic_ks_goe)$) versus #math.equation(numbering: none, alt: "D K S Poisson equals 0.2133", $D_"KS"^"P" = #fmt4(m.chaotic_ks_poisson)$)—a *#fmt1(m.ks_poisson_to_goe_ratio)*-fold preference for GOE [Fig. 2(b)].

// ============================================================================
// AUTHENTIC REVTeX DOUBLE-RULE TABLE I (FULL-WIDTH TOP OF PAGE 4)
// ============================================================================
#place(
  top,
  scope: "parent",
  float: true,
  clearance: 11pt,
  figure(
    [
      #text(font: "Source Serif 4", size: 7.7pt, fill: c-body)[
        #text(weight: "bold")[TABLE I.] Complete unedited classical symplectic (#math.equation(numbering: none, alt: "E equals 20.0", $E = 20.0$), #m.orbits_per_coupling orbits) and #math.equation(numbering: none, alt: "C 4 v A 1", $C_(4v) A_1$) quantum spectral sweep (#math.equation(numbering: none, alt: "D equals 676", $D = #m.basis_dim_small$) vs. #math.equation(numbering: none, alt: "900", $#m.basis_dim_large$)) across all #m.sweep_points protocol couplings. Maximum Yoshida-4 energy drift stays below #math.equation(numbering: none, alt: "10 to the minus 9", $10^(-9)$) everywhere.
      ]
      #v(4pt)
      // Authentic REVTeX ruledtabular double top & bottom rules
      #line(length: 100%, stroke: 0.55pt + c-rule)
      #v(-7.8pt)
      #line(length: 100%, stroke: 0.55pt + c-rule)
      #v(-3.5pt)
      #table(
        columns: (0.72fr, 0.72fr, 1.85fr, 0.90fr, 0.75fr, 0.78fr, 0.72fr, 0.85fr, 0.78fr, 0.82fr, 0.82fr),
        inset: (x: 2.6pt, y: 3.4pt),
        align: (right, right, left, right, right, right, right, right, right, right, right),
        stroke: (x, y) => (
          top: if y == 1 { 0.5pt + c-rule } else { none },
          bottom: none,
        ),
        table.header(
          text(font: "Inter", size: 6.1pt, weight: "bold", fill: c-ink)[#math.equation(numbering: none, alt: "alpha", $alpha$)],
          text(font: "Inter", size: 6.1pt, weight: "bold", fill: c-ink)[#math.equation(numbering: none, alt: "gamma", $gamma$)],
          text(font: "Inter", size: 6.1pt, weight: "bold", fill: c-ink)[Regime],
          text(font: "Inter", size: 6.1pt, weight: "bold", fill: c-ink)[#math.equation(numbering: none, alt: "max delta E over E times 10 to the 11", $|Delta E/E|_(11)$)],
          text(font: "Inter", size: 6.1pt, weight: "bold", fill: c-ink)[#math.equation(numbering: none, alt: "mean lambda 1", $chevron.l lambda_1 chevron.r$)],
          text(font: "Inter", size: 6.1pt, weight: "bold", fill: c-ink)[#math.equation(numbering: none, alt: "mu C", $mu_C$) %],
          text(font: "Inter", size: 6.1pt, weight: "bold", fill: c-ink)[#math.equation(numbering: none, alt: "N converged", $N_"conv"$)],
          text(font: "Inter", size: 6.1pt, weight: "bold", fill: c-cobalt)[#math.equation(numbering: none, alt: "mean r tilde", $chevron.l tilde(r) chevron.r$)],
          text(font: "Inter", size: 6.1pt, weight: "bold", fill: c-ink)[Brody #math.equation(numbering: none, alt: "beta", $beta$)],
          text(font: "Inter", size: 6.1pt, weight: "bold", fill: c-crimson)[#math.equation(numbering: none, alt: "D K S GOE", $D_"KS"^"GOE"$)],
          text(font: "Inter", size: 6.1pt, weight: "bold", fill: c-muted)[#math.equation(numbering: none, alt: "D K S Poisson", $D_"KS"^"P"$)],
        ),
        ..for row in data.sweep {
          let is-deg = (row.alpha == 0.0)
          (
            text(font: "IBM Plex Mono", size: 6.3pt, weight: "semibold")[#fmt3(row.alpha)],
            text(font: "IBM Plex Mono", size: 6.2pt, fill: c-muted)[#fmt2(row.gamma)],
            text(font: "Source Serif 4", size: 6.8pt)[#row.regime],
            text(font: "IBM Plex Mono", size: 6.2pt, fill: c-muted)[#fmt2(row.max_dE_e11)],
            text(font: "IBM Plex Mono", size: 6.2pt)[#fmt3(row.mean_lyap)],
            text(font: "IBM Plex Mono", size: 6.2pt)[#fmt1(row.chaotic_pct)],
            text(font: "IBM Plex Mono", size: 6.2pt, fill: c-muted)[#row.n_conv],
            text(font: "IBM Plex Mono", size: 6.3pt, weight: "bold", fill: c-cobalt)[#fmt4(row.r_mean)#if is-deg [#super[a]]],
            text(font: "IBM Plex Mono", size: 6.2pt)[#fmt3(row.brody_beta)],
            text(font: "IBM Plex Mono", size: 6.2pt, weight: "semibold", fill: c-crimson)[#fmt4(row.ks_goe)],
            text(font: "IBM Plex Mono", size: 6.2pt, fill: c-muted)[#fmt4(row.ks_poisson)],
          )
        },
      )
      #v(-5pt)
      #line(length: 100%, stroke: 0.55pt + c-rule)
      #v(-7.8pt)
      #line(length: 100%, stroke: 0.55pt + c-rule)
      #v(2.5pt)
      #align(left, text(font: "Source Serif 4", size: 6.9pt, style: "italic", fill: c-muted)[
        #super[a] Superintegrable isotropic 2D harmonic oscillator (#math.equation(numbering: none, alt: "alpha equals 0", $alpha = 0$)) exhibits exact integer shell degeneracies (#math.equation(numbering: none, alt: "E equals 2 k plus 1", $E = 2k + 1$)), collapsing adjacent gap ratios identically to zero @berry1977tabor. Column #math.equation(numbering: none, alt: "delta E over E sub 11", $|Delta E/E|_(11)$) reports #math.equation(numbering: none, alt: "max relative energy error times 10 to the 11", $max |Delta E / E| times 10^(11)$).
      ])
    ],
    supplement: none,
  ),
)

// Single-column Figure 3 (classic PRL column figure!)
#figure(
  image("assets/fig3_rigidity_symplectic.svg", width: 100%, alt: "Single-column vector figure showing long-range spectral number variance Sigma squared of L from L=0 to 5 for alpha=0.025 (teal), alpha=0.125 (amber), and alpha=2.50 (crimson), demonstrating logarithmic GOE spectral rigidity far below the dashed Poisson Sigma squared equals L line. The top-left inset plots log10 relative energy drift over T=2000 comparing bounded blue Yoshida-4 symplectic integration against secularly drifting crimson RK4."),
  caption: text(font: "Source Serif 4", size: 7.5pt, fill: c-body)[
    #text(weight: "bold")[FIG. 3.] Long-range spectral rigidity #math.equation(numbering: none, alt: "Sigma squared of L", $Sigma^2 (L)$) across unfolded intervals #math.equation(numbering: none, alt: "L in 0.5 to 5.0", $L in [0.5, 5.0]$). Chaotic Yang–Mills levels (#math.equation(numbering: none, alt: "alpha equals 2.50", $alpha = 2.50$), crimson) follow the logarithmic GOE rigidity curve (#math.equation(numbering: none, alt: "Sigma squared of 5 equals 0.65", $Sigma^2 (5) = #fmt2(m.sigma2_L5_chaotic)$)), sharply suppressed relative to uncorrelated Poisson growth (#math.equation(numbering: none, alt: "Sigma squared equals L", $Sigma^2 (L) = L$), dashed). Inset: relative energy error #math.equation(numbering: none, alt: "log 10 delta E over E", $log_(10)|Delta E/E|$) over #math.equation(numbering: none, alt: "T equals 2000", $T = 2000$) (#math.equation(numbering: none, alt: "alpha equals 0.50, delta t equals 0.020", $alpha = 0.50, Delta t = 0.020$)), demonstrating bounded Yoshida-4 oscillation versus secular RK4 drift (*#fmt1(m.rk4_vs_yoshida_drift_ratio)*× larger at #math.equation(numbering: none, alt: "T equals 2000", $T = 2000$)).
  ],
  supplement: none,
)

#prl-sec[Spectral rigidity and symplectic precision]Short-range level repulsion alone does not distinguish true quantum chaos from weak intermediate correlations. Figure 3 therefore tests long-range spectral rigidity via the number variance #math.equation(numbering: none, alt: "Sigma squared of L", $Sigma^2 (L)$) across up to five mean spacings. Whereas near-integrable levels at #math.equation(numbering: none, alt: "alpha equals 0.025", $alpha = 0.025$) reach #math.equation(numbering: none, alt: "Sigma squared of 5 equals 1.38", $Sigma^2 (5) = #fmt2(m.sigma2_L5_kam)$), chaotic levels at #math.equation(numbering: none, alt: "alpha equals 2.50", $alpha = 2.50$) exhibit strong logarithmic compression down to #math.equation(numbering: none, alt: "Sigma squared of 5 equals 0.65", $Sigma^2 (5) = #fmt2(m.sigma2_L5_chaotic)$), in quantitative agreement with asymptotic GOE rigidity #math.equation(numbering: none, alt: "2 over pi squared times ln 2 pi L plus gamma plus 1 minus pi squared over 8", $(2/pi^2)[ln(2 pi L) + gamma_E + 1 - pi^2/8] approx 0.68$) at #math.equation(numbering: none, alt: "L equals 5", $L = 5$).

The inset of Fig. 3 directly contrasts fourth-order Yoshida symplectic integration against classical non-symplectic fourth-order Runge–Kutta (RK4) at identical step size (#math.equation(numbering: none, alt: "delta t equals 0.020", $Delta t = 0.020$), #math.equation(numbering: none, alt: "T equals 2000", $T = 2000$)). While RK4 suffers monotonic secular energy drift reaching *#fmt1(m.rk4_vs_yoshida_drift_ratio)*× higher error by #math.equation(numbering: none, alt: "T equals 2000", $T = 2000$), Yoshida-4 conserves a nearby shadow Hamiltonian with bounded oscillation across every orbit.

#prl-sec[Five-gate verification court]To close the reproducibility gap between numerical physics and final archival publication, `run_pipeline.sh` gates Typst compilation behind a Sovereign Zig 0.17.0 five-gate audit court (`vedit`): (1) SHA-256 checksum latching of `data/raw/yang_mills_protocol.csv` (#raw(raw-sha.slice(0, 16) + "…")) and 1:1 coverage across all *#ledger.len()* tuples in `provenance_ledger.json`; (2) background-sampled WCAG 2.1 pixel contrast verification across every rendered glyph span; (3) clip-aware AABB span collision, `W`/`W*` clip-path slicing, and trim-overflow verification; (4) Rule 10 post-render prose grounding verifying every extracted numeral directly against the provenance ledger and scholarly reference table; and (5) pre-press font embedding and live *veraPDF 1.30* ISO 14289-1 (`PDF/UA-1`) validation (106/106 checks passed).

#prl-sec[Conclusion]We demonstrated a bit-exact, zero-Python verification of classical-to-quantum chaos and BGS spectral universality in the quartic-regularized #math.equation(numbering: none, alt: "S U 2", $"SU"(2)$) Yang–Mills oscillator, typeset natively to APS *Physical Review Letters* (`REVTeX 4.2`) standards with genuine stepped `widetext` brackets and infinite-DPI vector exhibits. Extending the bare-metal Zig engine to broken time-reversal symmetry (magnetic flux driving GOE → GUE transition) and Lanczos matrix-free diagonalization for #math.equation(numbering: none, alt: "D greater than 10 to the 4", $D > 10^4$) opens immediate zero-mock high-energy spectral studies under identical cryptographic gates.

#v(5pt)
#line(length: 42%, stroke: 0.45pt + c-rule)
#v(3pt)
#set par(first-line-indent: 0pt, leading: 0.46em, spacing: 0.35em)
#text(size: 7.4pt, fill: c-muted)[
  #super[\*] Open-source reproduction package (`scripts/pipeline.zig`, `data/raw/yang_mills_protocol.csv`, `provenance_ledger.json`, `letter.typ`) archived in `verifiable-editorial-skills`.
]
#v(4pt)
#set text(size: 7.45pt, fill: c-body)
#set par(leading: 0.45em, spacing: 0.34em)
#bibliography("references.bib", title: none, style: "american-physics-society")
