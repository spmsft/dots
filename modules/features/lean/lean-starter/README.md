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

## Editor support

Helix (25.07.1+, `hx --health lean`) already ships built-in Lean 4
support (tree-sitter grammar + a `lake serve`-based language server) -
no `~/.config/helix/languages.toml` changes are needed. Just make sure
`lake`/`lean` resolve on PATH (`elan` handles this).

Helix has no built-in goal-state/InfoView panel (that's VSCode-specific,
webview-based UI) - you get hover/diagnostics/completions via the LSP,
but not an interactive goal tree. This repo packages
[lean-helix-view](https://github.com/wyattgill9/lean-helix-view) (a
`lake serve` proxy + ratatui goal/diagnostics viewer) as
`pkgs/lean-helix-view.nix`, installed via
`suites.dev-tools.leanHelixView` (off by default - enable it per-host
in your `dots-local`). When enabled:

1. `~/.config/helix/languages.toml` (see
   `settings/chromaden/home/.config/helix/languages.toml` for the
   reference override) points Helix's `lean` language-server at
   `lean-helix-view proxy -- lake serve` instead of `lake serve`
   directly - Helix talks to it exactly as before, transparently.
2. Run `lean-helix-view watch` in a separate tmux/zellij pane from the
   project root to see goals/diagnostics as you edit in Helix.

## Layout

- `lakefile.toml` - project + dependency manifest
- `lean-toolchain` - pinned Lean release (elan reads this)
- `LeanStarter.lean` / `LeanStarter/` - library root and submodules
- `Main.lean` - executable entry point (`lean-exe` target)
