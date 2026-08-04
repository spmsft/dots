#!/usr/bin/env python3
"""vk static vault checker.

Runs vk's own deterministic, offline checks against an already-staged
vault tree (see stage_vault()/vault_enhance.py in vk.sh - this script
assumes staging has already happened and never mutates anything itself,
unlike vault_enhance.py). It is the non-MyST half of `vk check`; vk.sh
separately runs a staged `myst build --strict` (and, only with
--external, `--check-links`) and combines both results.

Checks performed (all offline, all report `path:line: message`
diagnostics where a line number is meaningful):

  - Frontmatter shape: malformed YAML; missing `title` (every page);
    missing `id` (categorized notes under materials/records/texts only
    - vk's own structural pages, like every category's `index.md`,
    `main.md`, and `imprint.md`, never have one by design).
  - Duplicate `id`s, duplicate `aliases`, and any alias that collides
    with another note's `id` (a genuine ambiguity for link resolution).
  - Duplicate generated label slugs among notes that *have* an `id`
    (vk's own `id`-derived MyST label - see vault_enhance.py's
    `Note.label_slug`), which would silently collide as MyST
    cross-reference targets.
  - Unresolved local Markdown/`{doc}` document links (aliases count as
    valid targets - a link written before a rename still resolves).
  - Missing linked local assets (Markdown image syntax pointing at a
    local file that does not exist in the staged tree).
  - Unterminated `taskwarrior`/`graphviz` directive blocks (an opening
    fence with no matching closing fence before end of file).
  - Invalid Graphviz directive options or DOT syntax (rendered through
    the real Graphviz binaries, same as staging, but to a throwaway
    directory so `vk check` never touches real staged output).

Orphan notes (no incoming note links) are reported as warnings only -
per the design, an isolated note is worth a nudge, never a build
failure.
"""

import argparse
import re
import sys
import tempfile
from pathlib import Path

import vault_enhance as ve
import graphviz_preprocess as gp

_IMG_RE = re.compile(r"!\[[^\]]*\]\(([^)\s]+)\)")


def _strip_generated_nav(body):
    """Remove vk's own generated tag-chip/Backlinks/Related-Notes block
    (see vault_enhance.apply_note_navigation) before scanning a note's
    body for authored links/assets - otherwise generated links to
    `explore/tags/*.md` (deliberately excluded from the note catalog)
    would misreport as unresolved, and generated Backlinks/Related
    links would double-count as authored connectivity."""
    start = body.find(ve.NAV_MARK_START)
    if start == -1:
        return body
    end = body.find(ve.NAV_MARK_END, start)
    if end == -1:
        return body[:start]
    return body[:start] + body[end + len(ve.NAV_MARK_END):]


class Diagnostic:
    def __init__(self, path, line, message, level="error"):
        self.path = path
        self.line = line
        self.message = message
        self.level = level

    def __str__(self):
        loc = f"{self.path}:{self.line}" if self.line else self.path
        return f"{loc}: {self.level}: {self.message}"


def _is_generated_path(rel):
    """Is `rel` (a path relative to staging_root) something vk/MyST
    generated rather than authored vault content? Covers vk's own
    ``explore/`` navigation pages (see vault_enhance.py's
    build_catalog()) and MyST's ``_build/`` build output directory -
    `vk check` runs `myst build` before these checks, so `_build/`
    already exists by the time this scans, full of *.md files that
    aren't vault content (compiled artifacts, and - for book-theme -
    its own vendored npm dependencies' README/CHANGELOG/LICENSE
    files)."""
    return (
        rel in ("explore", "_build")
        or rel.startswith("explore/")
        or rel.startswith("_build/")
    )


def _is_categorized_note(rel):
    """Is `rel` an actual Zettelkasten note (something 'vk note'/'vk
    import' would create - see write_note() in vk.sh, which always
    writes flat as "$cat/$title.md") rather than one of vk's own
    structural pages? Structural pages - the root/category `index.md`
    files, `main.md`, `imprint.md`, and any other vault-root page a
    user drops in - never get a stable `id` by vk's own design (there's
    nothing to preserve across a rename, and nothing else ever needs to
    `{doc}`-reference them by id), so the frontmatter-shape check below
    must not demand one from them."""
    parts = Path(rel).parts
    return bool(parts) and parts[0] in ve.STRUCTURAL_CATEGORIES and Path(rel).name != "index.md"


def check_frontmatter_shape(staging_root):
    diags = []
    for path in sorted(staging_root.rglob("*.md")):
        rel = path.relative_to(staging_root).as_posix()
        if _is_generated_path(rel):
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as exc:
            diags.append(Diagnostic(rel, 1, f"cannot read file: {exc}"))
            continue
        if not text.startswith("---"):
            continue  # frontmatter is optional (e.g. main.md, index.md)
        lines = text.splitlines()
        end = None
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                end = i
                break
        if end is None:
            diags.append(Diagnostic(rel, 1, "unterminated frontmatter block"))
            continue
        raw = "\n".join(lines[1:end])
        import yaml
        try:
            meta = yaml.safe_load(raw)
        except yaml.YAMLError as exc:
            diags.append(Diagnostic(rel, 1, f"malformed YAML frontmatter: {exc}"))
            continue
        if meta is None:
            continue
        if not isinstance(meta, dict):
            diags.append(Diagnostic(rel, 1, "frontmatter must be a mapping"))
            continue
        required = ("id", "title") if _is_categorized_note(rel) else ("title",)
        for key in required:
            if not meta.get(key):
                diags.append(Diagnostic(rel, 1, f"missing required frontmatter field: {key}"))
    return diags


def check_duplicate_identity(catalog):
    diags = []
    by_id = {}
    by_alias = {}
    by_slug = {}
    for note in catalog:
        if note.id:
            if note.id in by_id:
                diags.append(Diagnostic(
                    note.rel_path, 1,
                    f"duplicate id {note.id!r} (also used by {by_id[note.id]})"
                ))
            else:
                by_id[note.id] = note.rel_path
        for alias in note.aliases:
            if alias in by_alias:
                diags.append(Diagnostic(
                    note.rel_path, 1,
                    f"duplicate alias {alias!r} (also used by {by_alias[alias]})"
                ))
            by_alias[alias] = note.rel_path
        # label_slug only corresponds to a real MyST cross-reference
        # target when the note has an explicit `id` - MyST doesn't
        # generate any implicit project-wide target from a bare
        # filename (confirmed: several id-less notes sharing a
        # filename, e.g. every category's own `index.md`, build fine
        # under `myst build --strict`). Checking it for id-less notes
        # would just be flagging harmless same-named structural pages
        # across different directories.
        if note.id:
            slug = note.label_slug
            if slug in by_slug:
                diags.append(Diagnostic(
                    note.rel_path, 1,
                    f"label slug {slug!r} collides with {by_slug[slug]}"
                ))
            else:
                by_slug[slug] = note.rel_path

    for alias, alias_owner in by_alias.items():
        if alias in by_id and by_id[alias] != alias_owner:
            diags.append(Diagnostic(
                alias_owner, 1,
                f"alias {alias!r} collides with another note's id (owned by {by_id[alias]})"
            ))
    return diags


def check_links_and_assets(staging_root, catalog):
    diags = []
    ve.link_notes(catalog)
    by_key = {n.id: n for n in catalog if n.id}
    for n in catalog:
        for alias in n.aliases:
            by_key.setdefault(alias, n)
    by_relpath = {n.rel_path: n for n in catalog}
    by_relpath_noext = {str(Path(n.rel_path).with_suffix("")): n for n in catalog}

    for note in catalog:
        lines = note.body.split("\n")
        for lineno, line in enumerate(lines, start=1):
            for _text, target in ve._MD_LINK_RE.findall(line):
                if not target.endswith(".md"):
                    continue
                t = target.strip()
                if not t or t.startswith("#") or re.match(r"^[a-zA-Z][a-zA-Z0-9+.\-]*:", t):
                    continue
                resolved = ve._resolve_link_target(
                    t, note.rel_path, by_key, by_relpath, by_relpath_noext,
                )
                if resolved is None:
                    diags.append(Diagnostic(note.rel_path, lineno, f"unresolved local document link: {target}"))

            for asset_target in _IMG_RE.findall(line):
                t = asset_target.strip()
                if not t or re.match(r"^[a-zA-Z][a-zA-Z0-9+.\-]*:", t):
                    continue
                candidate = (staging_root / note.rel_path).parent / t
                if not candidate.exists():
                    diags.append(Diagnostic(note.rel_path, lineno, f"missing linked asset: {t}"))
    return diags


def check_directive_blocks(staging_root):
    """Flag unterminated `taskwarrior`/`graphviz` directive blocks - an
    opening fence with no matching closing fence before end of file."""
    diags = []
    open_re = re.compile(r"^(:{3,})\{(taskwarrior|graphviz)\}")

    for path in sorted(staging_root.rglob("*.md")):
        rel = path.relative_to(staging_root).as_posix()
        if _is_generated_path(rel):
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        lines = text.split("\n")
        i = 0
        while i < len(lines):
            m = open_re.match(lines[i])
            if not m:
                i += 1
                continue
            fence, kind = m.group(1), m.group(2)
            close_re = re.compile(r"^" + re.escape(fence) + r"[ \t]*$")
            j = i + 1
            end = None
            while j < len(lines):
                if close_re.match(lines[j]):
                    end = j
                    break
                j += 1
            if end is None:
                diags.append(Diagnostic(rel, i + 1, f"unterminated {kind} directive block"))
                i += 1
                continue
            i = end + 1

    return diags


def check_graphviz_rendering(staging_root, engine_bins):
    diags = []
    with tempfile.TemporaryDirectory() as scratch:
        scratch_assets = Path(scratch) / "assets"
        for path in sorted(staging_root.rglob("*.md")):
            rel = path.relative_to(staging_root).as_posix()
            if _is_generated_path(rel):
                continue
            try:
                text = path.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError):
                continue
            if "{graphviz}" not in text:
                continue
            try:
                gp.process(text, str(scratch_assets), engine_bins, source_path=rel)
            except gp.GraphvizDirectiveError as exc:
                diags.append(Diagnostic(rel, exc.line_no, str(exc.message).split(": ", 2)[-1]))
    return diags


def check_orphans(catalog):
    return [
        Diagnostic(n.rel_path, None, "orphan note: no incoming links from other notes", level="warning")
        for n in catalog if not n.backlinks
    ]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("staging_root", type=Path)
    parser.add_argument("--dot", required=True)
    parser.add_argument("--neato", required=True)
    parser.add_argument("--fdp", required=True)
    parser.add_argument("--sfdp", required=True)
    parser.add_argument("--circo", required=True)
    parser.add_argument("--twopi", required=True)
    args = parser.parse_args(argv)

    if not args.staging_root.is_dir():
        print(f"vault_check: no such staging directory: {args.staging_root}", file=sys.stderr)
        return 1

    engine_bins = {
        "dot": args.dot, "neato": args.neato, "fdp": args.fdp,
        "sfdp": args.sfdp, "circo": args.circo, "twopi": args.twopi,
    }

    catalog = ve.build_catalog(args.staging_root)
    for note in catalog:
        note.body = _strip_generated_nav(note.body)

    diags = []
    diags.extend(check_frontmatter_shape(args.staging_root))
    diags.extend(check_duplicate_identity(catalog))
    diags.extend(check_links_and_assets(args.staging_root, catalog))
    diags.extend(check_directive_blocks(args.staging_root))
    diags.extend(check_graphviz_rendering(args.staging_root, engine_bins))
    diags.extend(check_orphans(catalog))

    errors = [d for d in diags if d.level == "error"]
    warnings = [d for d in diags if d.level == "warning"]

    for d in sorted(diags, key=lambda d: (d.path, d.line or 0)):
        print(str(d))

    print(f"\n{len(errors)} error(s), {len(warnings)} warning(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
