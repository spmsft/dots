# Pinned Versions

Tracks the versions of key dependencies pinned in this repository and when
they were last checked against upstream releases.

## Format

```
| Dependency | Pinned Version | Last Checked | Latest Known | Status |
```

## Current

| Dependency       | Pinned Version | Last Checked | Latest Known | Status       |
|------------------|----------------|--------------|--------------|--------------|
| lean toolchain   | (see `lean-toolchain`) | — | — | — |
| lean-lsp-mcp    | (see `.github/mcp.json` / `opencode.json`) | — | — | — |

## How to update

Run `scripts/check-versions.sh` to compare pinned versions against upstream.
If behind, update the pinned version in the relevant config file and record
the change here. Run `lake update` if the Lean toolchain changed.

## Version check history

_(append entries here after each check)_
