#!/usr/bin/env python3
"""Unit tests for vault_check.py - see test_vault_enhance.py for how to run.

Graphviz-rendering-dependent checks are skipped gracefully when the
engine binaries aren't on PATH.
"""

import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

import vault_check as vc  # noqa: E402
import vault_enhance as ve  # noqa: E402

_ENGINE_BINS = {name: shutil.which(name) for name in ("dot", "neato", "fdp", "sfdp", "circo", "twopi")}
_HAS_GRAPHVIZ = all(_ENGINE_BINS.values())


def write(root, rel, content):
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    return path


class GeneratedPathExclusionTests(unittest.TestCase):
    """Regression coverage for the 2026-08 '_build/ mistaken for vault
    content' bug - vk check runs `myst build` before these checks, so
    _build/ already exists by the time build_catalog()/these scans run."""

    def test_frontmatter_check_ignores_build_and_explore(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            write(root, "_build/html/node_modules/pkg/README.md", "# no id here, not a note\n")
            write(root, "explore/tags.md", "---\ntitle: Tags\n---\nGenerated.\n")
            diags = vc.check_frontmatter_shape(root)
            self.assertEqual(diags, [])

    def test_directive_block_check_ignores_build_and_explore(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            write(root, "_build/html/whatever.md", ":::{graphviz}\nunterminated\n")
            diags = vc.check_directive_blocks(root)
            self.assertEqual(diags, [])


class StructuralPageIdScopingTests(unittest.TestCase):
    """Regression coverage for the 2026-08 'structural pages wrongly
    required an id / flagged as label-slug collisions' bug."""

    def test_structural_pages_do_not_require_id(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            write(root, "index.md", "---\ntitle: Root\n---\nHome.\n")
            write(root, "materials/index.md", "---\ntitle: Materials\n---\nList.\n")
            write(root, "main.md", "---\ntitle: Main\n---\nContent.\n")
            diags = vc.check_frontmatter_shape(root)
            self.assertEqual(diags, [])

    def test_categorized_note_requires_id(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            write(root, "materials/general/note.md", "---\ntitle: No Id\n---\nBody.\n")
            diags = vc.check_frontmatter_shape(root)
            self.assertEqual(len(diags), 1)
            self.assertIn("id", diags[0].message)

    def test_multiple_idless_index_pages_do_not_collide(self):
        catalog = [
            ve.Note("index.md", {"title": "Root"}),
            ve.Note("materials/index.md", {"title": "Materials"}),
            ve.Note("records/index.md", {"title": "Records"}),
        ]
        diags = vc.check_duplicate_identity(catalog)
        self.assertEqual(diags, [])  # id-less notes never compared for label-slug collision

    def test_real_duplicate_id_is_flagged(self):
        catalog = [
            ve.Note("materials/general/a.md", {"id": "dup", "title": "A"}),
            ve.Note("materials/general/b.md", {"id": "dup", "title": "B"}),
        ]
        diags = vc.check_duplicate_identity(catalog)
        # Same id -> both a duplicate-id diagnostic and a label-slug
        # collision (label_slug is derived from id).
        self.assertEqual(len(diags), 2)
        self.assertTrue(any("duplicate id" in d.message for d in diags))


class LinksAndAssetsTests(unittest.TestCase):
    def test_unresolved_link_is_flagged(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            write(root, "materials/general/note.md",
                  "---\nid: note-1\ntitle: Note\n---\nSee [gone](missing.md).\n")
            catalog = ve.build_catalog(root)
            diags = vc.check_links_and_assets(root, catalog)
            self.assertEqual(len(diags), 1)
            self.assertIn("unresolved local document link", diags[0].message)

    def test_missing_asset_is_flagged(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            write(root, "materials/general/note.md",
                  "---\nid: note-1\ntitle: Note\n---\n![alt](missing.png)\n")
            catalog = ve.build_catalog(root)
            diags = vc.check_links_and_assets(root, catalog)
            self.assertEqual(len(diags), 1)
            self.assertIn("missing linked asset", diags[0].message)

    def test_existing_asset_is_not_flagged(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            write(root, "materials/general/note.md",
                  "---\nid: note-1\ntitle: Note\n---\n![alt](pic.png)\n")
            write(root, "materials/general/pic.png", "img")
            catalog = ve.build_catalog(root)
            diags = vc.check_links_and_assets(root, catalog)
            self.assertEqual(diags, [])


class OrphanTests(unittest.TestCase):
    def test_orphan_reported_as_warning_only(self):
        note = ve.Note("materials/general/lonely.md", {"id": "lonely"})
        diags = vc.check_orphans([note])
        self.assertEqual(len(diags), 1)
        self.assertEqual(diags[0].level, "warning")


@unittest.skipUnless(_HAS_GRAPHVIZ, "graphviz binaries not found on PATH")
class GraphvizRenderingCheckTests(unittest.TestCase):
    def test_invalid_dot_reported_as_error(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            write(root, "materials/general/diagram.md",
                  "---\nid: diagram\ntitle: Diagram\n---\n\n:::{graphviz}\nnot valid dot {{{\n:::\n")
            diags = vc.check_graphviz_rendering(root, _ENGINE_BINS)
            self.assertEqual(len(diags), 1)


if __name__ == "__main__":
    unittest.main()
