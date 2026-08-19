# Recommended MCP / Tooling Integrations

Suggestions for tooling that would help agent-assisted work on this
project, organized by capability. Nothing here is installed or assumed
to exist - this is a shopping list to consult when setting up an
agent's environment, not a dependency of the project itself.

## Filesystem access

An agent needs read/write access scoped to this repository (and
ideally nothing wider) to edit Lean sources and memory-bank/docs files.
Any general-purpose filesystem MCP/tool scoped to the repo root is
sufficient - no Lean-specific requirement here.

## Git integration

Useful for the session-startup checklist's "review recent git history"
step and for the Reviewer role diffing what changed since the last
review. A tool that can show `git log`/`git diff`/blame without shelling
out raw commands is a convenience, not a requirement - plain `git` CLI
access covers this fine.

## Lean language server integration

The highest-value integration: something that talks to `lake serve`
(the Lean 4 LSP) to surface goal states, diagnostics, and
hover/completion info the way an editor would, rather than an agent
inferring proof state from raw compiler output. If the agent's editor
already provides this (e.g. via a Lean-aware Helix/VSCode setup), no
separate MCP is needed; if the agent works headlessly, a goal-state
proxy speaking to `lake serve` is worth adding.

## Semantic search

Useful once the project has enough Lean source and memory-bank content
that grep-by-identifier stops being enough - e.g. finding "where do we
already define something like this invariant" across CSLib/Mathlib-style
large dependency trees. Not needed for small projects; worth adding once
`semantic-domains.md` and the Lean source both grow past what a human
can hold in their head.

## Dependency graph tooling

Useful for the Semantic Architect role to answer "what would this
semantic change invalidate downstream" before making it - i.e. a tool
that can show which theorems/definitions transitively depend on a given
one. `lean4-cli`'s ecosystem includes `importGraph` (already a transitive
dependency via mathlib in this template) which can answer *import*-level
questions; a true declaration-level dependency graph is a bigger ask and
likely agent/tool-specific.
