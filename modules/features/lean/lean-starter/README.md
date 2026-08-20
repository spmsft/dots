# lean-starter

A minimal Lean 4 project template with a formal-semantics-oriented
dependency set pre-declared: **Batteries** (stdlib extensions), **Aesop**
(proof automation), **Qq** (metaprogramming/quasiquotation), and
**CSLib** (the CS-focused counterpart to Mathlib - operational
semantics, automata, process calculi). No Mathlib dependency, since it's
not needed for PL semantics/specification work.

## First build

```sh
lake update   # resolves and fetches the pinned deps above
lake build
```

`lake` comes from `elan` (installed via `suites.dev-tools.lean` in this
repo) - `elan` reads this project's `lean-toolchain` file and
transparently fetches the matching Lean release the first time you
build.

### If `lake update` complains about a toolchain mismatch

Each dependency (Batteries/Aesop/CSLib) pins its own expected Lean
version via its own `lean-toolchain` file. If this project's
`lean-toolchain` doesn't match what a dependency expects, `lake` will
tell you - copy the version string from the failing dependency's
`lean-toolchain` (or the matching tag from its repo) into this
project's `lean-toolchain` and re-run `lake update`. This is normal
Lean/Lake workflow, not something Nix or elan can resolve for you.

## Lean MCP server

`.github/mcp.json` (Copilot CLI) and `opencode.json` (OpenCode) both
configure [`lean-lsp-mcp`](https://github.com/oOo0oOo/lean-lsp-mcp),
which wraps `lake serve` and exposes proof-goal, term-information, and
theorem-search tools to an agent. It runs via `uvx`, provided by this
project's `flake.nix` dev shell - `direnv allow`/`nix develop`, then
`lake build` once before relying on its proof-state tools.
`scripts/check-versions.sh` compares the pinned `lean-lsp-mcp`/Lean
toolchain versions against upstream; see `memory-bank/versions.md`.

## Layout

- `lakefile.toml` - project + dependency manifest
- `lean-toolchain` - pinned Lean release (elan reads this)
- `LeanStarter.lean` / `LeanStarter/` - library root and submodules
- `Main.lean` - executable entry point (`lean-exe` target)
- `AGENTS.md` - entry point for AI-agent-assisted formalization work
  (project principles, change classification, proof-failure policy,
  session checklists) - point any agent here first
- `agents/` - one file per role (semantic architect / Lean encoder /
  proof engineer / reviewer)
- `memory-bank/` - durable session-spanning state (current focus,
  assumptions, theorem roadmap, semantic model, review findings,
  pinned dependency versions)
- `docs/architecture/` - modelling decisions and open questions;
  `docs/tooling/` - non-binding tooling recommendations
- `.github/mcp.json`, `opencode.json` - Lean MCP server config (see
  above); `scripts/check-versions.sh` - checks pinned versions against
  upstream
