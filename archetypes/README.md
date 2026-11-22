# `archetypes/` — Dissected PDF Design DNA Library

Every directory here was generated mechanically from a real PDF by the Sovereign Zig 0.17.0 harness (`vedit inject <sample.pdf> --name <slug>`).

Each archetype contains three agent-ready files:
- **`blueprint.json`** — trim geometry, margins, measured 60-30-10 WCAG palette, font scale mapped to bundled SIL-OFL substitutes, and page-by-page grid/density/archetype cadence.
- **`skeleton.typ`** — immediately compilable Typst `0.15.1` (`--pdf-standard ua-1`) starter wired to `data/summary_metrics.json` and `data/provenance_ledger.json`.
- **`AGENT_CARD.md`** — ~250-token summary card for AI agents.

## Add a New Sample & Spawn a Verified Publication
```bash
# 1. Dissect any external PDF into this registry
./zig/zig-out/bin/vedit inject path/to/reference.pdf --name custom-style

# 2. List all registered archetypes (--json for agents)
./zig/zig-out/bin/vedit archetypes

# 3. Scaffold & compile a fresh SHA-256-latched PDF/UA-1 publication from it
./zig/zig-out/bin/vedit init ./my-pub --archetype custom-style --title "My Verified Report"
VEDIT_BIN="$(pwd)/zig/zig-out/bin/vedit" bash ./my-pub/build.sh
```
