# Agent Guide - LeanStarter

This project is a Lean 4 formalization repository. Agents (AI or human)
working here should read this file first, every session.

## Principles

- **Formal correctness over coding velocity.** A theorem that took three
  sessions and is actually true beats one landed in an hour that hides
  an `sorry` or a too-strong hypothesis.
- **Semantic clarity over proof cleverness.** A boring, readable proof
  of the right statement is worth more than a golfed proof of a
  statement nobody re-checked.
- **Traceability from semantic obligations to Lean artifacts.** Every
  definition/theorem should trace back to a stated purpose in
  `memory-bank/theorem-roadmap.md` or `memory-bank/semantic-domains.md`
  - not just exist because it compiled.
- **Small, composable lemmas preferred over large proofs.** If a proof
  script is growing unwieldy, look for a lemma hiding inside it first.
- **Proof failures generate investigation notes, not semantic drift.**
  If a theorem won't prove, the default move is to record *why* in
  `memory-bank/current-focus.md`/`review-findings.md` and ask a human
  (or the Semantic Architect role) - not to quietly weaken the
  definition or the statement until something typechecks.

## Change classification

Classify every change you make as one of:

1. **Semantic change** - alters what is being modelled (new/changed
   definitions, invariants, or the meaning of an existing one). Owned
   by the **Semantic Architect** role. Must update
   `memory-bank/semantic-domains.md` and, if it invalidates existing
   theorems, `memory-bank/theorem-roadmap.md`.
2. **Encoding change** - changes how an already-agreed semantic idea is
   represented in Lean (structures, inductives, notation) without
   changing its meaning. Owned by the **Lean Encoder** role.
3. **Proof change** - proves, strengthens, or repairs a proof of an
   already-stated theorem; may add helper lemmas. Owned by the
   **Proof Engineer** role. Must never change a definition or weaken a
   theorem statement to make the proof pass - that's a semantic change
   and needs sign-off.
4. **Refactoring** - no change in meaning or proof obligations (renames,
   file moves, style). Safe for any role, but still worth a one-line
   note if it touches shared definitions.

If you're not sure which bucket a change falls in, treat it as a
semantic change and flag it rather than guessing.

## Proof failure policy

A `sorry`, `admit`, or a proof that times out is not a blocker to hide -
it's a signal to record. When a proof doesn't go through:

1. Leave the `sorry` in place with a comment describing what was tried.
2. Add an entry to `memory-bank/review-findings.md` or
   `memory-bank/current-focus.md` describing the obstruction (missing
   lemma? statement too strong? hidden assumption?).
3. Do not alter the statement or the underlying definition to make it
   provable without recording that as a **semantic change** and getting
   it reviewed.

## Memory-bank workflow

`memory-bank/` is this project's durable, human-and-agent-readable
state - read it instead of reconstructing context from scratch, and
update it before ending a session. See `memory-bank/README.md` for what
each file is for.

## Agent roles

See `agents/` for one file per role:

- [`agents/semantic-architect.md`](agents/semantic-architect.md) -
  maintains the semantic model, invariants, and theorem inventory.
  Does not write Lean proofs.
- [`agents/lean-encoder.md`](agents/lean-encoder.md) - encodes agreed
  definitions into Lean (structures, inductives, notation). Does not
  redesign semantics.
- [`agents/proof-engineer.md`](agents/proof-engineer.md) - proves
  stated theorems, may add helper lemmas, must not alter definitions to
  make proofs pass.
- [`agents/reviewer.md`](agents/reviewer.md) - independently reviews
  proofs, checks hidden assumptions, produces review reports.

A single session can wear more than one hat, but say which hat you're
wearing for each change, and don't let "proof engineer" quietly become
"semantic architect" mid-session without flagging it.

## Session startup checklist

1. Read this file (`AGENT.md`).
2. Read `memory-bank/current-focus.md`.
3. Read `memory-bank/assumptions.md`.
4. Review recent git history (`git log --oneline -20`) for context on
   what just happened.
5. Review `docs/architecture/open-questions.md` for anything blocking
   the area you're about to touch.

## Session completion checklist

1. Update `memory-bank/current-focus.md` (objective, blockers, "next
   session start here").
2. Record any discoveries (new lemmas needed, surprising interactions
   between definitions, etc.) in `memory-bank/current-focus.md` or
   `memory-bank/semantic-domains.md`.
3. Record any assumptions introduced in `memory-bank/assumptions.md`.
4. Update theorem status in `memory-bank/theorem-roadmap.md`.
5. Document unresolved issues in `docs/architecture/open-questions.md`.
