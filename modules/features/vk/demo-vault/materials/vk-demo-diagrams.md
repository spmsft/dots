---
id: materials-topic-vk-demo-diagrams
title: "Topic: Graphviz & Mermaid Diagrams"
type: topic
tags: [materials, topic, showcase]
date: 2026-08-04
---

`vk` renders two kinds of diagrams, from different sources:

## Mermaid (native MyST support)

MyST renders `{mermaid}` directives natively - no vk-side preprocessing
needed, so prefer this for ordinary flowcharts/sequence diagrams.

```{mermaid}
flowchart LR
    A[Note] -->|vk stage| B(MyST build)
    B --> C{HTML / PDF / Typst}
```

## Graphviz (vk's own directive)

MyST has no native Graphviz support, so `vk` preprocesses a
`:::{graphviz}` directive block at staging time (see
`scripts/graphviz_preprocess.py`): the DOT source is rendered to a
content-addressed static SVG (cached by a hash of engine+source, so
identical diagrams across notes/rebuilds never re-render), and the
directive is replaced with a plain `{figure}`. Reserve this for
layout-heavy diagrams (dependency graphs, etc.) that Mermaid doesn't
cover well.

:::{graphviz}
:engine: dot
:label: fig-vk-pipeline
:alt: vk's staging pipeline from source note to rendered output

digraph vk_pipeline {
    rankdir=LR;
    note [label="note.md"];
    stage [label="stage_vault()"];
    myst [label="myst build"];
    out [label="HTML / PDF / Typst"];
    note -> stage -> myst -> out;
}
:::

See the [project note](vk-demo-project.md) for the substitutions/
citation/exports side of the same pipeline.
