# Semantic Domains

The semantic model in prose - what each domain (syntax, states,
relations/judgements) *means*, independent of how it happens to be
encoded in Lean. This is the Semantic Architect's primary artifact, and
what the Lean Encoder role encodes *from* - if a Lean definition and
this file disagree, this file is describing the intent and the Lean
code is what needs fixing (or this file needs updating first, as an
explicit semantic change - see `AGENT.md`'s change classification).

Keep entries independent of Lean syntax where possible (write "a
configuration is a pair of a term and a store", not "`Config` is a
`structure` with two fields") - the goal is a model a reader could
follow without knowing Lean, that then gets encoded faithfully.

## Format

```
## <Domain name>

**Informal meaning:** <what this represents in the system being modelled>

**Invariants:** <properties that must always hold, if any>

**Lean encoding:** <pointer to the actual definition, once encoded>
```

## Domains

_(no domains recorded yet - add one per syntactic category, state
space, or judgement form as the model takes shape; CSLib's own
`Semantics`/`Transition` modules are a reasonable reference point for
how much granularity to aim for)_
