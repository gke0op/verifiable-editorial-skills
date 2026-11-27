# `zig/` — Sovereign Zig 0.17.0 Editorial Harness (`vedit 0.7.0-zig`)

**100% Zero-Python** bare-metal CLI for 6-gate PDF verification, pure-Zig PNG/JPEG panoramic plate & facing-spread rendering, SHA-256-pinned SIL-OFL font provisioning, PDF sample dissection/injection, and SHA-256-latched Typst `PDF/UA-1` scaffolding.

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
| `src/mupdf.zig` | Pure-C `mutool` bridge, per-process private `0700` temp dirs, P6 PPM & 4-channel CMYK PAM decoders, lexer-accurate ISO 32000 `BT..ET` blanker, Bezier/polygon dynamic-stack `W`/`W*` clip tracer, libmupdf `mutool run` link extractor, dereferenced font-embedding inspector, `/ToUnicode` advance-anomaly detector, and dual-key `/Image` XObject rewriter. |
| `src/audit.zig` | Verification gates 1–5: cryptographic `latch` (`std.crypto.hash.sha2.Sha256` + Rule 4), composited 144/360-DPI `contrast`, OBB/Bezier `geometry`, tonal-variance `coverage`, Rule 10 unit-aware + `/ToUnicode` `prose`, and real CMYK PAM TAC `prepress` (+ fail-closed live `veraPDF`). |
| `src/links.zig` | Gate 6 (`vedit links`, offline ON by default in `audit-all`): Rule 11 clickable PDF `/URI` audit, canonical IPv4-aton/IPv6 CIDR SSRF guard, same-page unlinked URL/DOI detector, citation/ledger coverage, and live anti-hallucination verifier (`curl -g` + hardened pure-Zig `std.http.Client` fallback rejecting 404/410/403/5xx, Soft-404s, and HTTP-200 bot challenges). |
| `src/media.zig` | Pure-Zig `fetch-fonts` (8 SHA-256-pinned SIL-OFL fonts + TTF/OTF magic checks), `plate` (panoramic crop + black-point lift + raised-cosine feather + ITU-T T.81 Baseline 4:4:4 JPEG / compressed PNG encoders), and `spreads` (facing-spread contact sheets with spine shadow). |
| `src/dissect.zig` | PDF sample dissector (`vedit inject` / `inspect`) extracting trim, margins, 60-30-10 WCAG palette, font ladder (mapped to SIL-OFL), band-union vertical fill %, 100×100 deduplicated photo %, grids, and page archetypes with RFC 8259 JSON escaping. |
| `src/scaffold.zig` | `vedit archetypes` registry indexer and `vedit init` zero-Python Typst `PDF/UA-1` project scaffolder (RFC 8259 escaped). |
| `src/court_tests.zig` | 51-test pure-Zig adversarial sabotage, live local-HTTP Rule 11, flagship regression & closed-loop test court (`zig build test-court`, `Debug` + `--release=safe`). |
| `src/main.zig` | Fail-closed CLI entrypoint (strict flag & finite numeric validation, RFC 8259 `--json` on every subcommand) + kernel unit tests. |
