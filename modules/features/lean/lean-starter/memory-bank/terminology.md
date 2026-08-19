# Terminology

Project-specific vocabulary for LeanStarter's semantic model. Keep this
in sync with the actual Lean names (`semantic-domains.md` is the prose
model; this is the glossary of *terms*, not domains).

| Term | Meaning | Lean name(s) |
|------|---------|--------------|
| _(example)_ configuration | A program state the operational semantics steps between | `Config` |
| _(example)_ small-step relation | The `-->` one-step reduction judgement | `Step` |

Add a row whenever you introduce a new term that isn't self-explanatory
from its Lean name alone - especially anything borrowed from a paper
that uses different notation than what ends up in the Lean source.
