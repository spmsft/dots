# Theorem Roadmap

The theorem inventory: one entry per theorem, proved, in-progress, or
merely planned. This is the Semantic Architect's map of what needs
proving and why - check here before picking up proof work, and update
status here as work progresses (see `AGENT.md`'s session-completion
checklist).

## Format

```
### <Identifier>

- **Purpose:** <why this theorem matters - what property of the system it establishes>
- **Dependencies:** <other theorems/lemmas this relies on>
- **Related Definitions:** <semantic domains / Lean declarations this is about>
- **Status:** Planned | In Progress | Blocked | Proved
- **Proof Notes:** <approach, gotchas, why it's blocked if applicable>
```

## Entries

_(the three entries below are illustrative examples for a small-step
operational semantics - replace them with your project's real theorems
once the semantic model in `semantic-domains.md` is in place)_

### determinism_of_step

- **Purpose:** Establishes that the small-step relation is a partial
  function - a program has at most one next state - which most later
  reasoning (e.g. "the trace is well-defined") relies on implicitly.
- **Dependencies:** none.
- **Related Definitions:** `Step` (the `-->` small-step judgement),
  `Config` (program configurations).
- **Status:** Planned
- **Proof Notes:** Likely a straightforward induction on the two
  derivations of `Step`, `cases`-ing on the outermost rule of each and
  discharging mismatches by `contradiction`/`injection` on constructor
  disagreement.

### progress

- **Purpose:** Every well-typed, non-final configuration can take a
  step - rules out the semantics "getting stuck" on a term the type
  system accepted.
- **Dependencies:** a typing judgement/relation to state "well-typed"
  against (not yet formalized - see `docs/architecture/open-questions.md`).
- **Related Definitions:** `Step`, `Config`, the (planned) typing
  judgement.
- **Status:** Blocked
- **Proof Notes:** Blocked on deciding whether typing is even in scope
  for this project, or whether "progress" should instead be stated
  purely operationally (e.g. against a syntactic notion of "stuck
  configuration").

### preservation

- **Purpose:** Stepping preserves whatever invariant/typing the
  configuration had before the step - the usual partner to `progress`
  in a type-soundness argument.
- **Dependencies:** `determinism_of_step` (convenient but not required),
  the same typing judgement `progress` depends on.
- **Related Definitions:** `Step`, the (planned) typing judgement.
- **Status:** Planned
- **Proof Notes:** Expect this to be the bulk of the semantic-soundness
  effort; plan to break it into one lemma per `Step` rule rather than
  one monolithic induction.
