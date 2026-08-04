#!/usr/bin/env python3
"""vk staged-tree enhancer.

MyST only ever builds a vault's disposable ``.vk-staging`` tree (see
``stage_vault()``/``myst_build()`` in vk.sh); this script is the second
step of that staging pipeline, run after plain file copy + Taskwarrior
preprocessing and before ``myst build``. It is intentionally the *only*
place vk does frontmatter/config analysis, so later features (tags,
backlinks, related notes, orphans, the Mermaid graph) can all be added
here as one deterministic pass rather than scattered shell parsing.

This script does four things:

  1. **Note catalog** - parse YAML frontmatter (``id``, ``title``,
     ``tags``, ``aliases``, ``category``/``type``, ``date``) plus body
     text from every staged ``*.md`` file (excluding vk's own generated
     ``explore/`` pages) into an in-memory catalog.

  2. **Staged myst.yml merge** - read the vault's own authored
     ``myst.yml`` (already plain-copied into staging by stage_vault())
     and merge a small set of managed defaults into it *for the staged
     copy only*: ``site.options.folders: true`` (native fix for MyST's
     ``/index-1`` collision routes - see memory-bank/decisions.md), an
     optional bibliography reference when ``references.bib`` exists and
     is non-empty, the shared style/logo/favicon assets, and the
     managed plugin bundle (appended to any user-declared plugins). An
     explicit value already present in the authored config always
     wins - this only fills in keys the user hasn't set. The authored
     ``myst.yml`` itself is never touched.

  3. **Note-level navigation** - resolve Markdown/`{doc}` links between
     notes (treating aliases as previous ids/paths), append a linked
     tag-chip row and generated Backlinks/Related-Notes sections to
     each staged note, all diff-guarded and clearly delimited so a
     later rebuild always regenerates rather than accumulates them.

  4. **Zettelkasten navigation pages** - staging-only pages under
     ``explore/`` (overview, tags index + one page per tag, recent
     notes by staged mtime, orphans with no incoming note links, and a
     Mermaid link graph), plus a `project.toc` entry for them when the
     vault defines an explicit toc.

Every write here is content-diff guarded (mirrors vk.sh's own
``cmp -s`` pattern) so an unchanged result never bumps the staged
file's mtime - required for ``vault_needs_build()``'s mtime comparison
and MyST's own incremental build cache to keep working.
"""

import argparse
import re
import sys
from pathlib import Path

import yaml

FRONTMATTER_KEYS = ("id", "title", "tags", "aliases", "category", "type", "date")

# Category folder names this repo's vaults use (see modules/features/vk.nix
# / vk.sh's regen_category_indexes()) - used only as a fallback when a note
# has no explicit frontmatter `category`, and to exclude structural,
# non-topical tags from Related Notes scoring below.
STRUCTURAL_CATEGORIES = ("materials", "records", "texts")

# Markers bracketing vk's own generated Backlinks/Related Notes section,
# so re-running the enhancer always replaces (never accumulates) it. In
# practice this never fires against genuinely stale content anyway:
# stage_vault()'s plain-copy pass always re-copies a note fresh from the
# *authored* vault before this script runs (a staged file that already
# carries a previous generated section differs from its authored source
# byte-for-byte, so `cmp -s` always triggers a re-copy) - but the markers
# still make the intent explicit and give a Note.body a way to have its
# previous generated section swapped out.
NAV_MARK_START = "<!-- vk:generated:nav:start -->"
NAV_MARK_END = "<!-- vk:generated:nav:end -->"

_MD_LINK_RE = re.compile(r"\[([^\]]*)\]\(([^)\s]+)\)")
_MYST_DOC_ROLE_RE = re.compile(r"\{doc\}`(?:[^<`]*<\s*)?([^`>]+?)\s*>?`")

RELATED_NOTES_CAP = 5
GRAPH_EDGE_CAP = 300


class Note:
    """One staged Markdown file's parsed frontmatter, path, and body."""

    def __init__(self, rel_path, meta, body="", mtime=0.0):
        self.rel_path = rel_path
        self.id = meta.get("id")
        self.title = meta.get("title") or Path(rel_path).stem
        self.tags = _as_list(meta.get("tags"))
        self.aliases = _as_list(meta.get("aliases"))
        self.category = meta.get("category") or _category_from_path(rel_path)
        self.type = meta.get("type")
        self.date = meta.get("date")
        self.body = body
        self.mtime = mtime
        # Populated by link_notes() below.
        self.links = []       # list of Note this note links to
        self.backlinks = []   # list of Note that link to this note
        self.related = []     # list of (Note, score), capped/sorted

    @property
    def key(self):
        """Best identifier for this note: its stable vk id, or its
        staged relative path when no id is present."""
        return self.id or self.rel_path

    @property
    def label_slug(self):
        return _slugify(self.id or Path(self.rel_path).stem)


def _category_from_path(rel_path):
    parts = Path(rel_path).parts
    if parts and parts[0] in STRUCTURAL_CATEGORIES:
        return parts[0]
    return None


def _slugify(value):
    value = re.sub(r"[^a-zA-Z0-9]+", "-", str(value).strip().lower())
    return value.strip("-") or "untitled"


def _as_list(value):
    if value is None:
        return []
    if isinstance(value, list):
        return [str(v) for v in value]
    return [str(value)]


def split_frontmatter(text):
    """Return (meta_dict, body_text) for a Markdown file's text.

    Returns an empty dict (and the original text as the body) when the
    file has no ``---``-delimited YAML frontmatter block, or when the
    block fails to parse as YAML (a malformed note must never crash the
    whole staging pipeline - it just contributes no metadata, same as a
    note with no frontmatter at all; ``vk check`` is the place that
    flags this as a problem, not this best-effort scan).
    """
    if not text.startswith("---"):
        return {}, text
    lines = text.splitlines(keepends=True)
    if not lines or lines[0].strip() != "---":
        return {}, text
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end is None:
        return {}, text
    raw = "".join(lines[1:end])
    try:
        meta = yaml.safe_load(raw)
    except yaml.YAMLError:
        return {}, text
    meta = meta if isinstance(meta, dict) else {}
    body = "".join(lines[end + 1:])
    return meta, body


def build_catalog(staging_root):
    """Parse frontmatter for every staged ``*.md`` file into a list of Note.

    Deterministically ordered by relative path so downstream consumers
    (and tests) never depend on filesystem iteration order. Excludes
    ``explore/`` - vk's own generated navigation pages (tags/recent/
    orphans/graph) - so a previous run's generated output is never fed
    back into note cataloging, link analysis, or Related Notes scoring
    on a later rebuild. Also excludes ``_build/`` - MyST's own build
    output directory (written directly inside ``.vk-staging``, i.e.
    ``staging_root`` itself) - which is full of *.md files that aren't
    vault content at all (compiled/copied build artifacts, and - for
    the bundled ``book-theme`` - its own vendored npm dependencies'
    README/CHANGELOG/LICENSE files). Without this, running 'vk check'
    (which builds before checking, so ``_build/`` already exists by the
    time this runs) would misreport those as duplicate ids/orphans/
    label-slug collisions.
    """
    catalog = []
    for path in sorted(staging_root.rglob("*.md")):
        rel = path.relative_to(staging_root).as_posix()
        if rel == "explore" or rel.startswith("explore/"):
            continue
        if rel == "_build" or rel.startswith("_build/"):
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        meta, body = split_frontmatter(text)
        try:
            mtime = path.stat().st_mtime
        except OSError:
            mtime = 0.0
        catalog.append(Note(rel, meta, body=body, mtime=mtime))
    return catalog


def _set_default(mapping, path, value):
    """Set ``mapping[path[0]][path[1]]... = value`` only if unset.

    Never overwrites a key the user already set anywhere along the
    path - an explicit authored value always wins over a managed
    default, at any nesting level.
    """
    node = mapping
    for key in path[:-1]:
        if key not in node or not isinstance(node.get(key), dict):
            if key in node:
                # User set a non-dict value at this level (e.g. `site:
                # false`) - back off entirely rather than clobbering it.
                return
            node[key] = {}
        node = node[key]
    last = path[-1]
    if last not in node:
        node[last] = value


def merge_myst_config(vault_root, staging_root):
    """Merge managed defaults into the staged myst.yml, in place.

    Reads the staged copy (already plain-copied from the vault's
    authored myst.yml by stage_vault()), applies defaults, and rewrites
    it only if the merged result actually differs byte-for-byte from
    what's already there.
    """
    staged_yml = staging_root / "myst.yml"
    if not staged_yml.exists():
        return

    try:
        original_text = staged_yml.read_text(encoding="utf-8")
    except OSError:
        return
    try:
        config = yaml.safe_load(original_text)
    except yaml.YAMLError:
        return
    if not isinstance(config, dict):
        return

    _set_default(config, ["site", "options", "folders"], True)

    bib_path = vault_root / "references.bib"
    if bib_path.exists() and bib_path.stat().st_size > 0:
        _set_default(config, ["project", "bibliography"], ["references.bib"])

    # Shared visual layer (see stage_vault() in vk.sh, which writes these
    # exact staged paths): only fills in the option when the vault's own
    # myst.yml doesn't already set it, so an explicit authored
    # style/logo/favicon always wins over the managed default.
    _set_default(config, ["site", "options", "style"], "assets/vk-managed.css")
    _set_default(config, ["site", "options", "logo"], "assets/vk-logo.svg")
    _set_default(config, ["site", "options", "favicon"], "assets/vk-logo.svg")

    merged_text = yaml.safe_dump(config, sort_keys=False, allow_unicode=True)
    if merged_text != original_text:
        staged_yml.write_text(merged_text, encoding="utf-8")


def merge_managed_plugins(vault_root, staging_root, managed_plugin_paths):
    """Append managed plugin paths to the staged myst.yml's
    ``project.plugins`` list, in place.

    Managed plugins (see modules/features/vk.nix's vkPluginSubstitutions/
    vkPluginCollectReferences - immutable, pinned Nix store paths, never
    fetched over the network at build/serve time) are appended *after*
    any user-declared plugins so an authored ordering is preserved, and
    exact-string duplicates are removed so re-running staging is
    idempotent and a vault that already lists a managed plugin path
    itself doesn't end up with it twice. The authored myst.yml itself is
    never modified - only the staged copy.
    """
    if not managed_plugin_paths:
        return

    staged_yml = staging_root / "myst.yml"
    if not staged_yml.exists():
        return

    try:
        original_text = staged_yml.read_text(encoding="utf-8")
    except OSError:
        return
    try:
        config = yaml.safe_load(original_text)
    except yaml.YAMLError:
        return
    if not isinstance(config, dict):
        return

    project = config.get("project")
    if not isinstance(project, dict):
        if "project" in config:
            # Non-dict `project:` value (e.g. `project: false`) - back
            # off rather than clobbering it.
            return
        project = {}
        config["project"] = project

    plugins = project.get("plugins")
    if plugins is None:
        plugins = []
    elif not isinstance(plugins, list):
        # Explicit non-list `plugins:` value - back off entirely.
        return

    existing = {str(p) for p in plugins}
    merged = list(plugins)
    for path in managed_plugin_paths:
        if str(path) not in existing:
            merged.append(str(path))
            existing.add(str(path))
    project["plugins"] = merged

    merged_text = yaml.safe_dump(config, sort_keys=False, allow_unicode=True)
    if merged_text != original_text:
        staged_yml.write_text(merged_text, encoding="utf-8")


def _resolve_link_target(target, from_rel_path, by_key, by_relpath, by_relpath_noext):
    """Resolve one Markdown/`{doc}` link target to a Note, or None.

    Only resolves local document links (a bare fragment like `#anchor`,
    or anything with a URL scheme such as `http(s)://`/`mailto:`, is
    left alone - this never scans prose for implicit links, only actual
    Markdown/MyST link syntax). Aliases are treated as previous IDs/
    paths, so a renamed note's old links still resolve.
    """
    target = target.strip()
    if not target or target.startswith("#"):
        return None
    if re.match(r"^[a-zA-Z][a-zA-Z0-9+.\-]*:", target):
        return None  # external URL / mailto: / etc.
    target = target.split("#", 1)[0].split("?", 1)[0]
    if not target:
        return None

    if target in by_key:
        return by_key[target]

    # Markdown links are relative to the linking file's own directory;
    # MyST {doc} roles are conventionally project-root relative. Try
    # both interpretations before giving up.
    candidates = []
    base_dir = Path(from_rel_path).parent
    candidates.append((base_dir / target).as_posix())
    candidates.append(target.lstrip("./"))

    for cand in candidates:
        cand_norm = Path(cand).as_posix()
        # by_relpath_noext's keys (including alias entries, which are
        # stored extension-stripped - see link_notes() below) never
        # carry a ".md" suffix, so a real Markdown link target (which
        # always does) must be extension-stripped too before comparing
        # against it - otherwise an alias for a renamed note's old path
        # would never actually match a plain `[text](old-name.md)`
        # link, silently breaking the "old links still resolve"
        # guarantee this function's docstring promises.
        cand_noext = str(Path(cand_norm).with_suffix(""))
        for lookup, key in ((by_relpath, cand_norm), (by_relpath_noext, cand_noext)):
            if key in lookup:
                return lookup[key]
            if key.lstrip("/") in lookup:
                return lookup[key.lstrip("/")]
    return None


def link_notes(catalog):
    """Resolve outgoing Markdown/`{doc}` links between staged notes and
    populate each Note's `.links`/`.backlinks` in place.

    Only exact, resolvable local document links count - never arbitrary
    prose scanning. Aliases (a note's previous IDs/paths) are indexed
    alongside its current id/path, so links written before a rename
    keep resolving.
    """
    by_key = {}
    by_relpath = {}
    by_relpath_noext = {}
    for note in catalog:
        by_relpath[note.rel_path] = note
        by_relpath_noext[str(Path(note.rel_path).with_suffix(""))] = note
        if note.id:
            by_key[note.id] = note
        for alias in note.aliases:
            by_key.setdefault(alias, note)
            by_relpath_noext.setdefault(str(Path(alias).with_suffix("")), note)

    for note in catalog:
        seen = set()
        for _text, target in _MD_LINK_RE.findall(note.body):
            if not target.endswith(".md"):
                continue
            resolved = _resolve_link_target(
                target, note.rel_path, by_key, by_relpath, by_relpath_noext
            )
            if resolved is not None and resolved is not note and resolved.rel_path not in seen:
                seen.add(resolved.rel_path)
                note.links.append(resolved)
                resolved.backlinks.append(note)
        for target in _MYST_DOC_ROLE_RE.findall(note.body):
            resolved = _resolve_link_target(
                target, note.rel_path, by_key, by_relpath, by_relpath_noext
            )
            if resolved is not None and resolved is not note and resolved.rel_path not in seen:
                seen.add(resolved.rel_path)
                note.links.append(resolved)
                resolved.backlinks.append(note)


def topical_tags(note):
    """A note's tags, minus purely structural category/type values -
    those describe *what a note is* (materials/records/texts and
    similar type labels), not a topic worth matching notes on."""
    exclude = {t.lower() for t in STRUCTURAL_CATEGORIES}
    if note.category:
        exclude.add(str(note.category).lower())
    if note.type:
        exclude.add(str(note.type).lower())
    return [t for t in note.tags if t.lower() not in exclude]


def compute_related(catalog):
    """Populate each Note's `.related` with up to RELATED_NOTES_CAP
    (Note, score) pairs, scored purely by shared topical-tag count.

    Deterministically ordered (score desc, then title, then path) so
    output never depends on dict/set iteration order, and capped so a
    handful of broad tags shared vault-wide can't swamp every page.
    """
    tag_sets = {note.rel_path: set(t.lower() for t in topical_tags(note)) for note in catalog}
    for note in catalog:
        own_tags = tag_sets[note.rel_path]
        if not own_tags:
            note.related = []
            continue
        scored = []
        for other in catalog:
            if other is note:
                continue
            score = len(own_tags & tag_sets[other.rel_path])
            if score > 0:
                scored.append((other, score))
        scored.sort(key=lambda pair: (-pair[1], (pair[0].title or "").lower(), pair[0].rel_path))
        note.related = scored[:RELATED_NOTES_CAP]


def _tag_chips_block(note):
    if not note.tags:
        return ""
    chips = " ".join(
        "[`%s`](/explore/tags/%s.md)" % (tag, _slugify(tag)) for tag in note.tags
    )
    return chips


def _generated_nav_section(note):
    """Render the Backlinks/Related Notes block appended to a staged
    note. Returns "" when there is nothing to show (an empty section
    would just be visual noise on notes with neither)."""
    parts = []
    if note.backlinks:
        parts.append("### Backlinks\n")
        for b in sorted(note.backlinks, key=lambda n: (n.title or "").lower()):
            parts.append("- [%s](/%s)" % (b.title or b.rel_path, b.rel_path))
        parts.append("")
    if note.related:
        parts.append("### Related Notes\n")
        for r, _score in note.related:
            parts.append("- [%s](/%s)" % (r.title or r.rel_path, r.rel_path))
        parts.append("")
    if not parts:
        return ""
    return "\n".join(["## Explore\n", *parts]).rstrip() + "\n"


def apply_note_navigation(staging_root, catalog):
    """Append generated tag-chip/Backlinks/Related-Notes content to each
    staged note in place, diff-guarded like every other staged write.

    Everything generated here lives inside one NAV_MARK_START/END block
    so vault_check.py can strip it wholesale before scanning a note's
    body for authored links/assets - without that, vk's own generated
    tag-chip links (which point at `explore/tags/*.md`, deliberately
    excluded from the note catalog) would misreport as "unresolved
    local document links", and generated Backlinks/Related links would
    inflate real link/orphan analysis on every subsequent `vk check`.
    """
    for note in catalog:
        path = staging_root / note.rel_path
        try:
            original = path.read_text(encoding="utf-8")
        except OSError:
            continue

        meta, body = split_frontmatter(original)
        chips = _tag_chips_block(note)
        nav_section = _generated_nav_section(note)
        if not chips and not nav_section:
            continue

        block_parts = []
        if chips:
            block_parts.append(chips + "\n")
        if nav_section:
            block_parts.append(nav_section)
        block = NAV_MARK_START + "\n" + "\n".join(block_parts) + NAV_MARK_END + "\n"

        new_body = body.rstrip("\n") + "\n\n" + block

        if meta:
            fm_text = yaml.safe_dump(meta, sort_keys=False, allow_unicode=True)
            new_text = "---\n" + fm_text + "---\n" + new_body
        else:
            new_text = new_body

        if new_text != original:
            path.write_text(new_text, encoding="utf-8")


def _write_if_changed(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        try:
            if path.read_text(encoding="utf-8") == text:
                return
        except OSError:
            pass
    path.write_text(text, encoding="utf-8")


def generate_explore_pages(staging_root, catalog):
    """Write vk's own staging-only Zettelkasten navigation pages under
    ``explore/``: overview, tags index + one page per tag, recent notes,
    orphans, and a Mermaid link graph. Every write is diff-guarded."""
    explore = staging_root / "explore"

    by_category = {}
    for note in catalog:
        by_category.setdefault(note.category or "uncategorized", []).append(note)

    lines = ["---", "title: Explore", "---", "", "# Explore", ""]
    lines.append("%d notes total." % len(catalog))
    lines.append("")
    for cat in sorted(by_category):
        lines.append("- **%s**: %d" % (cat, len(by_category[cat])))
    lines.append("")
    lines.append("- [Tags](/explore/tags/index.md)")
    lines.append("- [Recent](/explore/recent.md)")
    lines.append("- [Orphans](/explore/orphans.md)")
    lines.append("- [Graph](/explore/graph.md)")
    _write_if_changed(explore / "index.md", "\n".join(lines) + "\n")

    # Tags index + per-tag pages.
    by_tag = {}
    for note in catalog:
        for tag in note.tags:
            by_tag.setdefault(tag, []).append(note)

    tag_lines = ["---", "title: Tags", "---", "", "# Tags", ""]
    for tag in sorted(by_tag, key=str.lower):
        tag_lines.append("- [`%s`](/explore/tags/%s.md) (%d)" % (tag, _slugify(tag), len(by_tag[tag])))
    _write_if_changed(explore / "tags" / "index.md", "\n".join(tag_lines) + "\n")

    for tag, notes in by_tag.items():
        page = ["---", "title: 'Tag: %s'" % tag, "---", "", "# Tag: %s" % tag, ""]
        for note in sorted(notes, key=lambda n: (n.title or "").lower()):
            page.append("- [%s](/%s)" % (note.title or note.rel_path, note.rel_path))
        _write_if_changed(explore / "tags" / ("%s.md" % _slugify(tag)), "\n".join(page) + "\n")

    # Recent, ordered by staged source mtime (newest first); authored
    # `date` (if any) is shown separately so the two are never confused.
    recent_lines = ["---", "title: Recent", "---", "", "# Recent", ""]
    for note in sorted(catalog, key=lambda n: n.mtime, reverse=True):
        date_suffix = " - %s" % note.date if note.date else ""
        recent_lines.append("- [%s](/%s)%s" % (note.title or note.rel_path, note.rel_path, date_suffix))
    _write_if_changed(explore / "recent.md", "\n".join(recent_lines) + "\n")

    # Orphans: no incoming authored note links. A warning-level list,
    # not a build failure - `vk check` is where this becomes a report.
    orphan_lines = ["---", "title: Orphans", "---", "", "# Orphans", "",
                     "Notes with no incoming links from other notes.", ""]
    orphans = [n for n in catalog if not n.backlinks]
    for note in sorted(orphans, key=lambda n: (n.title or "").lower()):
        orphan_lines.append("- [%s](/%s)" % (note.title or note.rel_path, note.rel_path))
    _write_if_changed(explore / "orphans.md", "\n".join(orphan_lines) + "\n")

    # Graph: a Mermaid flowchart of authored note-to-note links, with
    # short labels, per-category styling, deterministic node ids, and a
    # defensive edge cap (large vaults stay renderable, with a clear
    # truncation notice rather than an unreadable/oversized diagram).
    graph_lines = ["---", "title: Graph", "---", "", "# Graph", "", "```{mermaid}", "flowchart LR"]
    node_ids = {n.rel_path: "n%d" % i for i, n in enumerate(sorted(catalog, key=lambda n: n.rel_path))}
    for note in sorted(catalog, key=lambda n: n.rel_path):
        label = (note.title or note.rel_path).replace('"', "'")
        graph_lines.append('    %s["%s"]' % (node_ids[note.rel_path], label))
    for cat in STRUCTURAL_CATEGORIES:
        members = [node_ids[n.rel_path] for n in catalog if n.category == cat]
        if members:
            graph_lines.append("    class %s cat-%s" % (",".join(members), cat))

    edges = []
    for note in sorted(catalog, key=lambda n: n.rel_path):
        for target in sorted(note.links, key=lambda n: n.rel_path):
            edges.append((node_ids[note.rel_path], node_ids[target.rel_path]))
    truncated = len(edges) > GRAPH_EDGE_CAP
    for src, dst in edges[:GRAPH_EDGE_CAP]:
        graph_lines.append("    %s --> %s" % (src, dst))
    graph_lines.append("```")
    if truncated:
        graph_lines.append("")
        graph_lines.append(
            "*Graph truncated to the first %d of %d links.*" % (GRAPH_EDGE_CAP, len(edges))
        )
    _write_if_changed(explore / "graph.md", "\n".join(graph_lines) + "\n")


def merge_explore_toc(staging_root):
    """Add an "Explore" entry (and its children) to the staged
    `project.toc`, only when the vault's authored config already
    defines an explicit `toc` (MyST auto-discovers every file when no
    `toc` is set, so `explore/` pages are already reachable there - an
    explicit toc, though, only builds/lists what it names). Idempotent
    and never touches the authored `myst.yml`.
    """
    staged_yml = staging_root / "myst.yml"
    if not staged_yml.exists():
        return
    try:
        original_text = staged_yml.read_text(encoding="utf-8")
        config = yaml.safe_load(original_text)
    except (OSError, yaml.YAMLError):
        return
    if not isinstance(config, dict):
        return

    project = config.get("project")
    if not isinstance(project, dict):
        return
    toc = project.get("toc")
    if not isinstance(toc, list):
        return  # no explicit toc - auto-discovery already covers explore/

    already_present = any(
        isinstance(entry, dict) and entry.get("file") == "explore/index.md"
        for entry in toc
    )
    if already_present:
        return

    toc.append({
        "file": "explore/index.md",
        "children": [
            {"file": "explore/tags/index.md"},
            {"file": "explore/recent.md"},
            {"file": "explore/orphans.md"},
            {"file": "explore/graph.md"},
        ],
    })

    merged_text = yaml.safe_dump(config, sort_keys=False, allow_unicode=True)
    if merged_text != original_text:
        staged_yml.write_text(merged_text, encoding="utf-8")


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("vault_root", type=Path, help="Authored vault directory")
    parser.add_argument("staging_root", type=Path, help="Vault's .vk-staging directory")
    parser.add_argument(
        "--managed-plugin", action="append", default=[],
        help="Path to a managed plugin .mjs file; may be repeated",
    )
    args = parser.parse_args(argv)

    if not args.staging_root.is_dir():
        print(f"vault_enhance: no such staging directory: {args.staging_root}", file=sys.stderr)
        return 1

    catalog = build_catalog(args.staging_root)
    merge_myst_config(args.vault_root, args.staging_root)
    merge_managed_plugins(args.vault_root, args.staging_root, args.managed_plugin)

    link_notes(catalog)
    compute_related(catalog)
    apply_note_navigation(args.staging_root, catalog)
    generate_explore_pages(args.staging_root, catalog)
    merge_explore_toc(args.staging_root)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
