# memory-bank

Durable, session-spanning notes for LeanStarter - read these before
starting work, update them before stopping. Unlike Lean source, this is
where you write down the *why*, the *not yet*, and the *tried and
failed*, none of which the type checker will ever tell you.

## Files

- **`current-focus.md`** - what's being worked on right now. The single
  most important file to read at session start and update at session
  end; treat "Next Session Start Here" as a note to your future self.
- **`terminology.md`** - glossary of project-specific vocabulary
  (names for semantic domains, relations, judgement forms). Keep this
  in sync with whatever the Semantic Architect actually names things in
  Lean - a glossary that drifts from the code is worse than none.
- **`assumptions.md`** - a running, dated log of assumptions introduced
  along the way (e.g. "assuming a deterministic small-step relation for
  now"). Every assumption here is a candidate for later
  generalization/removal - don't let them go unrecorded just because
  they seemed obvious at the time.
- **`theorem-roadmap.md`** - the theorem inventory: one entry per
  theorem (proved, in-progress, or planned), with dependencies and
  status. This is the Semantic Architect's map of "what needs proving
  and why" - Proof Engineers should check it before picking up work.
- **`semantic-domains.md`** - the semantic model itself in prose: what
  each domain (syntax, states, relations/judgements) means, independent
  of its Lean encoding. This is what the Lean Encoder role encodes
  *from*.
- **`review-findings.md`** - independent review notes from the Reviewer
  role: hidden assumptions found, proofs that prove something subtly
  different from the intended theorem, etc.

## Workflow

Read `current-focus.md` and `assumptions.md` at the start of every
session (see `AGENTS.md`'s session-startup checklist). Update
`current-focus.md`, `theorem-roadmap.md`, and any file whose subject
matter you touched, before ending a session (see `AGENTS.md`'s
session-completion checklist). Treat stale memory-bank entries as a bug
- if you notice one while working on something else, fix it in passing.
