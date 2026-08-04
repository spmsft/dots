#!/usr/bin/env python3
"""vk note/asset-rename helper.

Implements the narrow "rename" vk's `note` menu offers - conceptually
just a file move that keeps the rest of the vault(s) consistent:

  - For a Markdown note (`.md`): preserve its stable `id`, record its
    former path as an `alias` (so links written before the rename keep
    resolving via vault_enhance.py's alias-aware link resolution), and
    move the file.
  - For any other file (an asset - image, PDF, etc.): just move it.
    There's no frontmatter/id/alias to preserve for a plain asset.

Either way, update *exact* Markdown/`{doc}` document links and image
embeds pointing at the moved file - from other files in the same
vault, and from files in *sibling* vaults (vk vaults are always
siblings directly under one `$VAULTS_DIR`, so a cross-vault relative
link/image like `../other-vault/assets/diagram.png` is a normal,
supported thing to write, and is resolved/rewritten the same way as an
in-vault one).

Deliberately narrow, matching the plan this implements:
  - Only Markdown link/image syntax (`[text](path)`/`![alt](path)`,
    which share the same `(...)` target syntax) and MyST `{doc}` role
    syntax (`` {doc}`path` ``/`` {doc}`text <path>` ``) pointing at the
    moved file are rewritten - never free prose, never external URLs,
    and never citations.
  - The link's own relative-path *form* is preserved as closely as
    possible: an existing relative link is recomputed relative to its
    own file's directory, not replaced with an absolute path.
  - Matching/rewriting is done in absolute-filesystem-path space
    (resolved via `os.path.normpath`, not a filesystem `resolve()`, so
    it works whether or not the old path still exists on disk) purely
    as internal computation - what actually gets *written* back is
    always a relative path (`os.path.relpath` between two absolute
    paths), so no absolute filesystem path (and no `$HOME`) ever ends
    up in vault content or generated URLs.
"""

import argparse
import os
import re
import shutil
import sys
from pathlib import Path

import yaml

_MD_LINK_RE = re.compile(r"(\[[^\]]*\]\()([^)\s]+)(\))")
_MYST_DOC_ROLE_RE = re.compile(r"(\{doc\}`(?:[^<`]*<\s*)?)([^`>]+?)(\s*>?`)")


def _split_frontmatter(text):
    if not text.startswith("---"):
        return None, text
    lines = text.splitlines(keepends=True)
    if not lines or lines[0].strip() != "---":
        return None, text
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end is None:
        return None, text
    raw = "".join(lines[1:end])
    try:
        meta = yaml.safe_load(raw)
    except yaml.YAMLError:
        return None, text
    if not isinstance(meta, dict):
        return None, text
    body = "".join(lines[end + 1:])
    return meta, body


def _is_external(target):
    target = target.strip()
    return (not target) or target.startswith("#") or bool(
        re.match(r"^[a-zA-Z][a-zA-Z0-9+.\-]*:", target)
    )


def _resolve_abs(target, from_abs_dir):
    """Resolve a Markdown/{doc} link target written in a file located
    in `from_abs_dir` to a normalized absolute path (no extension),
    without requiring the target to exist on disk."""
    bare = target.split("#", 1)[0].split("?", 1)[0]
    if not bare:
        return None
    abs_path = os.path.normpath(os.path.join(str(from_abs_dir), bare))
    return os.path.splitext(abs_path)[0]


def _target_matches(target, from_abs_dir, old_abs_noext):
    """Does this link target - written in a file located at
    `from_abs_dir` - resolve to the note's old absolute path (any
    vault, same rules vault_enhance.py's own link resolver uses)?"""
    if _is_external(target):
        return False
    resolved = _resolve_abs(target, from_abs_dir)
    return resolved is not None and resolved == old_abs_noext


def _rewrite_target(old_target, from_abs_dir, new_abs_path):
    """Recompute a link that pointed at the old path so it points at
    the new one, preserving a relative link's relative-ness. Keeps the
    target's extension if the original had one written (covers both
    explicit `.md` links and any asset extension like `.png`/`.pdf`);
    only an originally-extensionless MyST `{doc}` target (the implicit
    `.md` convention) stays extensionless."""
    bare = old_target.split("#", 1)[0].split("?", 1)[0]
    suffix = old_target[len(bare):]
    had_ext = bool(Path(bare).suffix)

    rel = Path(os.path.relpath(str(new_abs_path), str(from_abs_dir))).as_posix()
    if not had_ext:
        rel = str(Path(rel).with_suffix(""))
    return rel + suffix


def _iter_vault_md_files(vaults_root):
    """Every authored Markdown file across every vault directly under
    `vaults_root` (vk vaults are always its immediate subdirectories -
    see vk.sh's VAULTS_DIR/list_vaults()). Skips each vault's own
    disposable `.vk-staging` build tree."""
    for vault_dir in sorted(p for p in vaults_root.iterdir() if p.is_dir()):
        for path in sorted(vault_dir.rglob("*.md")):
            if ".vk-staging" in path.parts:
                continue
            yield path


def update_links(vaults_root, vault_name, old_rel_path, new_rel_path):
    """Rewrite exact Markdown/{doc} links to the renamed note across
    every other authored Markdown file in *any* vault under
    `vaults_root` (this operates on the real vaults directly, not a
    disposable staging tree - a rename is an authoring action, not a
    build step)."""
    old_abs = vaults_root / vault_name / old_rel_path
    new_abs = vaults_root / vault_name / new_rel_path
    old_abs_noext = os.path.splitext(os.path.normpath(str(old_abs)))[0]

    updated = []
    for path in _iter_vault_md_files(vaults_root):
        if path == new_abs:
            continue  # the renamed note's own body is never rewritten
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue

        from_abs_dir = path.parent
        changed = False

        def _replace(m):
            nonlocal changed
            prefix, target, suffix = m.group(1), m.group(2), m.group(3)
            if _target_matches(target, from_abs_dir, old_abs_noext):
                changed = True
                return prefix + _rewrite_target(target, from_abs_dir, new_abs) + suffix
            return m.group(0)

        new_text = _MD_LINK_RE.sub(_replace, text)
        new_text = _MYST_DOC_ROLE_RE.sub(_replace, new_text)

        if changed and new_text != text:
            path.write_text(new_text, encoding="utf-8")
            try:
                rel_for_report = path.relative_to(vaults_root).as_posix()
            except ValueError:
                rel_for_report = str(path)
            updated.append(rel_for_report)
    return updated


def _move_note(old_path, new_path, old_rel_path):
    """Markdown-specific move: preserve `id`, add the former path as an
    `aliases` entry so pre-rename links keep resolving."""
    text = old_path.read_text(encoding="utf-8")
    meta, body = _split_frontmatter(text)
    if meta is None:
        meta = {}

    old_alias = str(Path(old_rel_path).with_suffix(""))
    aliases = meta.get("aliases")
    if not isinstance(aliases, list):
        aliases = [] if aliases is None else [aliases]
    if old_alias not in aliases:
        aliases.append(old_alias)
    meta["aliases"] = aliases

    fm_text = yaml.safe_dump(meta, sort_keys=False, allow_unicode=True)
    new_text = "---\n" + fm_text + "---\n" + body

    new_path.parent.mkdir(parents=True, exist_ok=True)
    new_path.write_text(new_text, encoding="utf-8")
    old_path.unlink()


def rename_item(vault_root, old_rel_path, new_rel_path):
    """Move any file (note or asset) within a vault, updating every
    reference to it - across that vault and its siblings."""
    old_path = vault_root / old_rel_path
    new_path = vault_root / new_rel_path
    if not old_path.is_file():
        raise FileNotFoundError(f"no such file: {old_rel_path}")
    if new_path.exists():
        raise FileExistsError(f"a file already exists at: {new_rel_path}")

    if old_path.suffix.lower() == ".md":
        _move_note(old_path, new_path, old_rel_path)
    else:
        new_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(old_path), str(new_path))

    updated = update_links(vault_root.parent, vault_root.name, old_rel_path, new_rel_path)
    return updated


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("vault_root", type=Path)
    parser.add_argument("old_rel_path")
    parser.add_argument("new_rel_path")
    args = parser.parse_args(argv)

    try:
        updated = rename_item(args.vault_root, args.old_rel_path, args.new_rel_path)
    except (FileNotFoundError, FileExistsError) as exc:
        print(f"note_rename: {exc}", file=sys.stderr)
        return 1

    print(f"Moved {args.old_rel_path} -> {args.new_rel_path}")
    if updated:
        print(f"Updated links in {len(updated)} file(s): {', '.join(updated)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
