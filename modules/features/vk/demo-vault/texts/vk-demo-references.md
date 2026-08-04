---
id: texts-hub-vk-demo-references
title: "Hub: Collected References"
type: hub
tags: [texts, hub, showcase]
date: 2026-08-04
---

The pinned, offline `myst-collect-references` plugin (auto-injected at
staging time, same as `myst-substitutions` - no `myst.yml` plugin path
needed in this repo copy) aggregates citations/footnotes/figures/tables
scattered across every note into one place. This vault only uses
citations (see the [project note](../materials/vk-demo-project.md)),
so only `{collect-citations}` has anything to show:

:::{collect-citations}
:::

The same plugin also offers `{collect-glossary}`, `{collect-footnotes}`,
`{collect-figures}`, and `{collect-tables}` - not demonstrated here
since this vault doesn't use a glossary/footnotes/multiple captioned
figures, but wire them up the same way on a real project's own
references hub.
