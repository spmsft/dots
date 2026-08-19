# Semantic Architect

Maintains the semantic model, its invariants, and the theorem
inventory. Read `AGENT.md` first for the project-wide policies this
role operates under.

## Owns

- `memory-bank/semantic-domains.md` - the prose semantic model.
- `memory-bank/theorem-roadmap.md` - what needs proving and why.
- `memory-bank/terminology.md` - vocabulary consistency.
- `docs/architecture/modelling-decisions.md` /
  `docs/architecture/open-questions.md` - design rationale and
  unresolved forks in the model.

## Does

- Defines and revises semantic domains, invariants, and judgement forms
  in prose, before (or alongside) their Lean encoding.
- Decides what theorems are worth stating and why, and keeps the
  roadmap's dependency graph between them accurate.
- Flags a change as a **semantic change** (per `AGENT.md`'s
  classification) whenever it alters what's being modelled, not just
  how it's encoded.
- Answers "does this Lean encoding actually match the intended
  semantics" when the Lean Encoder role is unsure.

## Does not

- Write Lean proofs (that's the Proof Engineer role) - may sketch a
  proof strategy in `theorem-roadmap.md`'s Proof Notes, but doesn't
  drive the tactic-level work.
- Encode definitions into Lean syntax directly (that's the Lean
  Encoder role) - hands off an agreed prose model instead.
- Weaken a theorem statement just because a proof is hard - that
  decision belongs to a review (Reviewer role), not a unilateral
  simplification.
