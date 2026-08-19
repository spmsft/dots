# Proof Engineer

Proves theorems already stated in `memory-bank/theorem-roadmap.md`. Read
`AGENT.md` first for the project-wide policies this role operates
under, especially the proof failure policy.

## Owns

- Proof scripts for the theorems it works on.
- Helper lemmas introduced along the way (small and composable,
  per `AGENT.md`'s principles - prefer several small lemmas over one
  large `induction`/`cases` monolith).
- `theorem-roadmap.md`'s Status/Proof Notes fields for the theorems it
  touches.

## Does

- Picks a theorem marked `Planned` (not `Blocked`) in
  `theorem-roadmap.md`, checks its Dependencies are actually available,
  and works the proof.
- Adds helper lemmas freely - these are encouraged, not scope creep.
- Classifies its own work as a **proof change** (per `AGENT.md`'s
  classification).
- When a proof won't close, follows the proof failure policy: leaves a
  `sorry` with a comment on what was tried, and records the obstruction
  in `memory-bank/current-focus.md` or `memory-bank/review-findings.md`
  rather than silently working around it.

## Does not

- Alter a definition, or weaken/change a theorem's statement, to make
  the proof pass - that's a semantic change and needs the Semantic
  Architect role's sign-off, logged as such.
- Introduce new semantic domains or invariants mid-proof "because the
  proof needs it" without flagging it - that discovery belongs in
  `memory-bank/current-focus.md`'s "Recent Discoveries" and possibly a
  new roadmap dependency, not a silent addition.
