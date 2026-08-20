# Copilot instructions for LeanStarter

## Build and validation

Run commands from the repository root.

```sh
# Enter the development environment when elan/lake are not already available.
direnv allow
# or
nix develop

# Repository-wide Lean validation (there is no separate test or lint target).
lake build

# Run the executable smoke check.
lake exe lean-starter

# Check one module while iterating; this is the closest equivalent to a
# single-test command until first-party tests are added.
lake env lean LeanStarter/Basic.lean
```

Use `lake env lean path/to/File.lean` for any focused module check. Run
`lake update` only after changing dependencies or when the manifest must be
refreshed; never hand-edit `lake-manifest.json`.

Repository-local Copilot CLI sessions load `lean-lsp-mcp` from
`.github/mcp.json`. OpenCode sessions load it from `opencode.json` at the
repo root. Both use `uvx` from the Nix development shell and start
`lake serve` internally; run `lake build` before relying on their
proof-state tools.

## Architecture and source of truth

This is currently a Lean 4 formalization scaffold, not yet the implemented
semantic model it will become. The first-party Lean code only verifies the
toolchain and dependency setup, and the entries in
`memory-bank/theorem-roadmap.md` are illustrative placeholders.

- `LeanStarter.lean` is the library root and imports modules under
  `LeanStarter/`; `Main.lean` imports the library and defines the
  `lean-starter` executable.
- Semantic intent is developed in `memory-bank/semantic-domains.md`, with
  vocabulary in `memory-bank/terminology.md` and proof obligations in
  `memory-bank/theorem-roadmap.md`. Lean definitions encode that agreed prose;
  proofs discharge the roadmap obligations.
- `docs/architecture/modelling-decisions.md` records resolved modelling choices,
  while `docs/architecture/open-questions.md` records unresolved forks that
  should not be guessed at.
- `memory-bank/current-focus.md`, `assumptions.md`, and `review-findings.md`
  preserve session state, temporary modelling assumptions, and independent
  review results.

If the prose semantic model and Lean code disagree, treat that as a semantic
issue: update or confirm the prose intent explicitly before changing the
encoding.

## Repository-specific workflow

- Start each session by reading `AGENTS.md`, `memory-bank/current-focus.md`,
  `memory-bank/assumptions.md`, recent Git history, and
  `docs/architecture/open-questions.md`.
- Classify changes as semantic, encoding, proof, or refactoring, and state the
  active role described under `agents/`. Semantic changes must update
  `semantic-domains.md` and affected theorem-roadmap entries. Encoding changes
  must not redesign semantics. Proof changes must not alter definitions or
  weaken theorem statements to make a proof pass.
- Every definition or theorem should trace to a purpose in
  `semantic-domains.md` or `theorem-roadmap.md`. Prefer small helper lemmas over
  monolithic proof scripts.
- When a proof fails, keep the `sorry` with a short note about what was tried,
  record the obstruction in `current-focus.md` or `review-findings.md`, and do
  not silently change the statement or model.
- Before ending a session, update `current-focus.md` and any affected semantic,
  assumption, theorem-roadmap, review, decision, or open-question records.
- Import CSLib modules directly where used; CSLib has no umbrella import. Do
  not add a direct Mathlib dependency unless the formalization requires it and
  the dependency decision is documented.
- Do not edit generated/environment-managed paths such as `.lake/`, `build/`,
  `.direnv/`, or dependency sources under `.lake/packages/`; exclude them from
  broad searches.
