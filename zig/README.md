# `zig/` — Sovereign Zig 0.17.0 Editorial Harness (`vedit 0.5.0-zig`)

Zero-Python bare-metal CLI for PDF verification, PDF sample dissection/injection, and SHA-256-latched Typst `PDF/UA-1` scaffolding.

## Build & Verify
```bash
zig fmt --check build.zig src/mupdf.zig src/audit.zig src/dissect.zig src/scaffold.zig src/main.zig
zig build test
zig build test --release=safe
zig build --release=safe
./zig-out/bin/vedit version
```

Runtime tools used by the binary (all non-Python): `mutool` (`mupdf-tools`), `typst` (`0.15.1`), optional `verapdf` (ISO 14289-1).

## Modules
| File | Role |
| :--- | :--- |
| `src/kernels_p2zig.zig` | 12 mathematical & dissection kernels transpiled from `verifiable_editorial/kernels_p2zig_src.py` via `p2zig --strict` (`// uroboros:zig-tir`). |
| `src/mupdf.zig` | Pure-C `mutool` bridge, P6 PPM decoder, ISO 32000 `BT..ET` stream blanker, `W`/`W*` clip-path stripper, and dual-key `/Image` XObject rewriter (preserving `/SMask` & xref offsets). |
| `src/audit.zig` | All 5 verification gates: `latch` (`std.crypto.hash.sha2.Sha256` + Rule 4), `contrast`, `geometry` (incl. clip slicing), `coverage`, `prose` (Rule 10 signed+superscript), and `prepress` (+ live `veraPDF`). |
| `src/dissect.zig` | PDF sample dissector (`vedit inject` / `inspect`) extracting trim, margins, 60-30-10 WCAG palette, font ladder (mapped to SIL-OFL), grids, and page archetypes. |
| `src/scaffold.zig` | `vedit archetypes` registry indexer and `vedit init` zero-Python Typst `PDF/UA-1` project scaffolder. |
| `src/main.zig` | CLI entrypoint (`--json` on every subcommand) + `p2zig` kernel unit tests. |
