#!/usr/bin/env python3
"""Unit tests for vault_enhance.py.

Run via: python3 -m unittest discover -s modules/features/vk/scripts
(needs PyYAML on PYTHONPATH - use vk's own Nix-managed Python, e.g.:
  $(nix build .#homeConfigurations.default.activationPackage --print-out-paths --no-link)
  ...or simply `nix shell nixpkgs#python3Packages.pyyaml -c python3 -m unittest ...`
  from the repo root - see README.md's "Testing vk" section.)
"""

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

import vault_enhance as ve  # noqa: E402


def write(root, rel, content):
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    return path


class BuildCatalogTests(unittest.TestCase):
    def test_excludes_explore_and_build_dirs(self):
        """Regression test for the 2026-08 bug where 'vk check' (which
        runs `myst build` before static checks) picked up MyST's own
        _build/ output - including vendored theme node_modules
        README/CHANGELOG/LICENSE files - as if they were vault notes."""
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            write(root, "materials/general/real-note.md", "---\nid: note-1\ntitle: Real\n---\nBody.\n")
            write(root, "explore/tags.md", "---\ntitle: Tags\n---\nGenerated.\n")
            write(root, "_build/html/node_modules/some-pkg/README.md", "# Some package\n")
            write(root, "_build/temp/whatever.md", "temp artifact\n")

            catalog = ve.build_catalog(root)
            rels = {n.rel_path for n in catalog}

            self.assertEqual(rels, {"materials/general/real-note.md"})

    def test_deterministic_order(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            write(root, "b.md", "# B\n")
            write(root, "a.md", "# A\n")
            catalog = ve.build_catalog(root)
            self.assertEqual([n.rel_path for n in catalog], ["a.md", "b.md"])

    def test_malformed_frontmatter_does_not_crash(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            write(root, "broken.md", "---\nid: [unterminated\n---\nBody\n")
            catalog = ve.build_catalog(root)
            self.assertEqual(len(catalog), 1)
            self.assertIsNone(catalog[0].id)


class NoteLabelSlugTests(unittest.TestCase):
    def test_label_slug_derived_from_id_when_present(self):
        note = ve.Note("materials/general/foo.md", {"id": "My Cool Note"})
        self.assertEqual(note.label_slug, "my-cool-note")

    def test_label_slug_falls_back_to_filename_stem(self):
        note = ve.Note("materials/general/index.md", {})
        self.assertEqual(note.label_slug, "index")


class LinkNotesTests(unittest.TestCase):
    def test_resolves_link_by_id_and_alias(self):
        target = ve.Note("materials/general/target.md", {"id": "target-id", "aliases": ["materials/general/old-name"]})
        source = ve.Note(
            "materials/general/source.md", {},
            body="See [target](target.md) and [old link](old-name.md).",
        )
        catalog = [target, source]
        ve.link_notes(catalog)
        self.assertIn(target, source.links)
        self.assertIn(source, target.backlinks)


if __name__ == "__main__":
    unittest.main()
