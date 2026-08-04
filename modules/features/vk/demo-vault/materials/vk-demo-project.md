---
id: materials-project-vk-demo-project
title: "Project: vk Demo"
type: project
tags: [materials, project, showcase]
date: 2026-08-04
exports:
  - format: typst
    output: exports/vk-demo-project.pdf
---

This note is the entry point into the demo vault and shows off the
plain-Markdown/frontmatter side of `vk`: a stable `id`
(`{cat}-{type}-{slug}`, exactly what `write_note()` generates), `tags`,
a `date`, and an opt-in `exports:` list - run `vk export vk-demo-vault
materials/vk-demo-project.md --format typst` (or just `--format pdf`)
to build it on demand without touching this frontmatter.

## Substitutions plugin

The pinned, offline `myst-substitutions` plugin (auto-injected at
staging time, no `myst.yml` plugin path needed in this repo copy)
replaces `{{ vault_version }}`/`{{ maintainer }}` tokens from this
vault's `myst.yml` `project.substitutions` block: this is demo vault
{{ vault_version }}, maintained by {{ maintainer }}.

## Image embed

![A tiny hand-drawn SVG exercising vk's local-asset embedding and
`vk check`'s missing-asset detection.](../assets/demo-figure.svg)

## Native citation

Notes on reproducible research practice, e.g. keeping code and data
together and testing it [@wilson2014bestpractices], pair well with a
Zettelkasten workflow for the writing itself [@ahrens2018how]. Both
entries were added via `vk import` → Bibentry, which appends the raw
BibTeX to [references.bib](../references.bib) and rejects a duplicate
citekey.

## Cross-links (exercise navigation)

- See the [kickoff event](../records/vk-demo-kickoff.md) that started
  this project - it links back here, which is what populates this
  note's own **Backlinks** section below.
- See [Graphviz & Mermaid diagrams](vk-demo-diagrams.md) for
  diagramming support.
- See the [contributor guide](../texts/vk-demo-guide.md) for authoring
  conventions, including the `taskwarrior` directive.
- See the [references page](../texts/vk-demo-references.md) for the
  `myst-collect-references` plugin.

Every link above is a plain relative Markdown link - `vk note`'s
Rename/Move File action keeps links like these correct (including
across sibling vaults) if this note or `assets/demo-figure.svg` is ever
renamed or moved.
