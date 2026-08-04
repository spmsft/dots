---
id: texts-guide-vk-demo-guide
title: "Guide: Contributing to This Vault"
type: guide
tags: [texts, guide, showcase]
date: 2026-08-04
aliases: [texts/vk-demo-guide-old-name]
---

This note also demonstrates vk's Rename/Move File support: it carries
an `aliases:` entry as if it had once lived at
`texts/vk-demo-guide-old-name.md` - a link written against that old
path would still resolve (and, per `note_rename.py`'s live rewriting,
would already have been rewritten to the current path had the rename
happened through `vk note` instead of by hand here).

## Native MyST tabs (no vk-side plugin needed)

::::{tab-set}
:::{tab-item} Materials
Durable reference material: sources, entities, projects, quotes, topics.
:::
:::{tab-item} Records
Timestamped events, notes, and observations.
:::
:::{tab-item} Texts
Longer-form writing: articles, guides, hubs.
:::
::::

## Native MyST cards

::::{grid} 1 1 2 2
:::{card} Keep links relative
:header: ✏️ Authoring
Use plain Markdown links/image syntax - `vk check`/`note_rename.py`
both understand exactly that syntax, nothing fancier.
:::
:::{card} One id per note
:header: 🪪 Identity
Every categorized note gets a stable `id` - `vault_check.py` flags
duplicates and structural pages are exempt.
:::
::::

## Taskwarrior directive (graceful fallback)

This demo vault has no real Taskwarrior data, so the directive below
falls back to its own body text rather than failing the build - the
same graceful-degradation path a real vault hits if `task` isn't
installed or a query comes back empty.

:::{taskwarrior} Open vk Documentation Tasks
:project: vk-demo
:status: pending
:tags: docs
:limit: 5

_(No Taskwarrior data in this demo vault - configure a real `project`/
`status`/`tags` filter in your own vault to see live results here.)_
:::
