# vk Demo Vault

A small, self-contained `vk` vault, committed as source content (not a
build artifact), that exercises every user-facing `vk` feature in one
place. It exists so a reviewer/future change can see real, working
Markdown for each feature rather than just prose in `README.md`.

## What it demonstrates

| Feature | Where |
|---|---|
| Standard note frontmatter (`id`/`title`/`type`/`tags`/`date`) | every note |
| `aliases:` (rename/move support) | `texts/vk-demo-guide.md` |
| Cross-links, Backlinks, Related Notes (Zettelkasten navigation) | `materials/vk-demo-project.md` ↔ `records/vk-demo-kickoff.md` |
| Local asset/image embed | `materials/vk-demo-project.md` → `assets/demo-figure.svg` |
| Native citations (`[@citekey]` + `references.bib`) | `materials/vk-demo-project.md`, `references.bib` |
| `myst-substitutions` plugin (`{{ var }}`) | `materials/vk-demo-project.md`, `myst.yml`'s `project.substitutions` |
| `myst-collect-references` plugin (`{collect-citations}`) | `texts/vk-demo-references.md` |
| Native MyST Mermaid diagrams | `materials/vk-demo-diagrams.md` |
| vk's own Graphviz directive | `materials/vk-demo-diagrams.md` |
| Native MyST tabs/cards/grids | `texts/vk-demo-guide.md` |
| `taskwarrior` directive (graceful no-data fallback) | `texts/vk-demo-guide.md` |
| `exports:` frontmatter (PDF/Typst export) | `materials/vk-demo-project.md` |

Explore-page navigation (tags/recent/orphans/graph) and `explore/`
itself are generated automatically by `vault_enhance.py` at staging
time - nothing to author for those, just note tags/links existing.

## Trying it live

`vk`'s Home Manager activation automatically syncs this directory into
`$VAULTS_DIR/vk-demo-vault` on every `apply-dots` (see `vk.nix`'s
`home.activation.vkDemoVault`), so after activating you'll see it
appear directly in `vk`'s hub menu, `vk serve-all`'s root listing, and
`vk check all` - no manual copy step needed:

```bash
vk check vk-demo-vault    # static + strict-build validation
vk watch vk-demo-vault    # live preview + dufs server
```

**Don't hand-edit files under `$VAULTS_DIR/vk-demo-vault` directly** -
that copy is fully overwritten (`rm -rf` + re-copy) from this source
directory on every `apply-dots`, so local edits there don't persist.
Edit the files here in the repo instead.

If you need to iterate on `vk`/this vault without running a full
`apply-dots` (e.g. while developing `vk` itself), the same scratch-
`VAULTS_DIR` technique this repo's own dev sessions use still works and
never touches a real `$HOME/Vaults`:

```bash
cp -r modules/features/vk/demo-vault /tmp/vk-demo-vault
# Build vk (or use an already-built one), then patch a throwaway copy's
# VAULTS_DIR the same way this repo's own dev sessions do:
VK_REAL=$(readlink -f "$(which vk)")
sed 's#VAULTS_DIR="$HOME/Vaults"#VAULTS_DIR="/tmp/vk-vaults-scratch"#' "$VK_REAL" > /tmp/vk-scratch
chmod +x /tmp/vk-scratch
mkdir -p /tmp/vk-vaults-scratch
cp -r /tmp/vk-demo-vault /tmp/vk-vaults-scratch/vk-demo-vault
/tmp/vk-scratch check vk-demo-vault      # static + strict-build validation
/tmp/vk-scratch watch vk-demo-vault      # live preview + dufs server
```

## Keeping this up to date

**This is a standing rule, not a one-off**: whenever a change adds or
meaningfully alters a user-facing `vk` Markdown/plugin/navigation
feature - a new directive, a new plugin, a new frontmatter field, a
change to how links/navigation/citations resolve - add or update a note
here demonstrating it, and refresh the table above. Re-run `vk check`
against this vault (see above) before committing to confirm it still
builds cleanly. This has the same "don't let it silently drift" spirit
as `memory-bank/architecture.md` section 12's keep-in-sync checklist -
add an entry there if a change here isn't obvious from the diff alone.
