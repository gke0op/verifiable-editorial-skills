# `zig/` — Sovereign Zig 0.17.0 Editorial Harness (`vedit 0.6.0-zig`)

**100% Zero-Python** bare-metal CLI for 6-gate PDF verification, pure-Zig PNG/JPEG panoramic plate & facing-spread rendering, SIL-OFL font provisioning, PDF sample dissection/injection, and SHA-256-latched Typst `PDF/UA-1` scaffolding.

## Build & Verify
```bash
zig fmt --check build.zig src/mupdf.zig src/audit.zig src/links.zig src/dissect.zig src/scaffold.zig src/media.zig src/court_tests.zig src/main.zig
zig build test && zig build test --release=safe
zig build test-court && zig build test-court --release=safe
zig build --release=safe
./zig-out/bin/vedit version
```

Runtime tools used by the binary (all non-Python): `mutool` (`mupdf-tools`), `typst` (`0.15.1`), `curl`, optional `verapdf` (ISO 14289-1).

## Modules
| File | Role |
| :--- | :--- |
| `src/kernels_p2zig.zig` | 12 mathematical & dissection kernels (`// uroboros:zig-tir`) covering WCAG contrast, CMYK GCR TAC, AABB collisions, orphan headlines, Rule 10 signed grounding, DPI, grid columns, archetypes, and dual-key coverage. |
| `src/mupdf.zig` | Pure-C `mutool` bridge, P6 PPM decoder, ISO 32000 `BT..ET` stream blanker, `W`/`W*` clip-path tracer/stripper, `/Subtype /Link` `/URI` annotation extractor, and dual-key `/Image` XObject rewriter (preserving `/SMask` & xref offsets). |
| `src/audit.zig` | Verification gates 1–5: `latch` (`std.crypto.hash.sha2.Sha256` + Rule 4), `contrast`, `geometry` (4-corner clip slicing), `coverage`, `prose` (Rule 10 half-ULP signed+exponent), and `prepress` (+ live `veraPDF`). |
| `src/links.zig` | Gate 6 (`vedit links`): Rule 11 clickable PDF `/URI` audit, unlinked text URL/DOI detector, citation/ledger coverage, and live anti-hallucination verifier (DOI Handle Registry, GBIF/iNaturalist APIs, HTTP GET Soft-404 & bot-challenge rejection). |
| `src/media.zig` | Pure-Zig `fetch-fonts` (8 SIL-OFL fonts + SHA-256 manifest), `plate` (panoramic crop + black-point lift + raised-cosine feather + ITU-T T.81 Baseline 4:4:4 JPEG / compressed PNG encoders), and `spreads` (facing-spread contact sheets with spine shadow). |
| `src/dissect.zig` | PDF sample dissector (`vedit inject` / `inspect`) extracting trim, margins, 60-30-10 WCAG palette, font ladder (mapped to SIL-OFL), grids, and page archetypes. |
| `src/scaffold.zig` | `vedit archetypes` registry indexer and `vedit init` zero-Python Typst `PDF/UA-1` project scaffolder. |
| `src/court_tests.zig` | 33-test pure-Zig adversarial sabotage, live local-HTTP Rule 11, flagship regression & closed-loop test court (`zig build test-court`). |
| `src/main.zig` | CLI entrypoint (`--json` on every subcommand) + kernel unit tests. |
