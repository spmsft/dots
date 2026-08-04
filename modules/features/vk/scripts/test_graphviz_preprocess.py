#!/usr/bin/env python3
"""Unit tests for graphviz_preprocess.py - see test_vault_enhance.py for how to run.

Requires real Graphviz binaries on PATH (dot/neato/fdp/sfdp/circo/twopi);
skips the rendering tests gracefully if unavailable.
"""

import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

import graphviz_preprocess as gp  # noqa: E402

_ENGINE_BINS = {name: shutil.which(name) for name in gp._ENGINES}
_HAS_GRAPHVIZ = all(_ENGINE_BINS.values())


@unittest.skipUnless(_HAS_GRAPHVIZ, "graphviz binaries not found on PATH")
class ProcessTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.assets_dir = str(Path(self.tmp.name) / "assets")

    def test_renders_simple_digraph_to_figure(self):
        text = "Intro.\n\n:::{graphviz}\ndigraph G { a -> b }\n:::\n\nOutro.\n"
        result, written = gp.process(text, self.assets_dir, _ENGINE_BINS, source_path="note.md")

        self.assertEqual(len(written), 1)
        self.assertTrue(Path(written[0]).exists())
        self.assertIn(":::{figure} assets/graphviz/", result)
        self.assertIn("Intro.", result)
        self.assertIn("Outro.", result)
        self.assertNotIn("{graphviz}", result)

    def test_doc_rel_dir_produces_correct_relative_image_path(self):
        # Notes always live one category level deep (materials/records/
        # texts) per vk's flat-per-category convention - a note there
        # must reference "../assets/graphviz/...", not a staging-root-
        # relative "assets/graphviz/..." (which would 404 as
        # "materials/assets/graphviz/..." once MyST resolves it against
        # the note's own directory). Regression test for the 2026-08 bug
        # this doc_rel_dir parameter fixes.
        text = ":::{graphviz}\ndigraph G { a -> b }\n:::\n"
        result, _written = gp.process(
            text, self.assets_dir, _ENGINE_BINS,
            source_path="materials/note.md", doc_rel_dir="materials",
        )
        self.assertIn(":::{figure} ../assets/graphviz/", result)

    def test_doc_rel_dir_defaults_to_staging_root(self):
        text = ":::{graphviz}\ndigraph G { a -> b }\n:::\n"
        result, _written = gp.process(text, self.assets_dir, _ENGINE_BINS, source_path="note.md")
        self.assertIn(":::{figure} assets/graphviz/", result)
        self.assertNotIn("../assets/graphviz/", result)

    def test_preserves_surrounding_content_untouched(self):
        text = "# Title\n\nSome *other* [directive](x.md) untouched.\n"
        result, written = gp.process(text, self.assets_dir, _ENGINE_BINS, source_path="note.md")
        self.assertEqual(result, text)
        self.assertEqual(written, [])

    def test_content_addressed_caching_same_dot_same_file(self):
        text = ":::{graphviz}\ndigraph G { a -> b }\n:::\n"
        _r1, w1 = gp.process(text, self.assets_dir, _ENGINE_BINS, source_path="a.md")
        _r2, w2 = gp.process(text, self.assets_dir, _ENGINE_BINS, source_path="b.md")
        self.assertEqual(w1, w2)  # identical DOT source -> identical output path

    def test_label_alt_class_options_carried_into_figure_directive(self):
        text = (":::{graphviz}\n:engine: neato\n:label: fig-x\n:alt: An example\n"
                ":class: my-class\n\ndigraph G { a -> b }\n:::\n")
        result, _written = gp.process(text, self.assets_dir, _ENGINE_BINS, source_path="note.md")
        self.assertIn(":label: fig-x", result)
        self.assertIn(":alt: An example", result)
        self.assertIn(":class: my-class", result)

    def test_invalid_dot_source_raises_directive_error(self):
        text = ":::{graphviz}\nthis is not valid dot {{{\n:::\n"
        with self.assertRaises(gp.GraphvizDirectiveError):
            gp.process(text, self.assets_dir, _ENGINE_BINS, source_path="note.md")

    def test_unknown_engine_raises_directive_error(self):
        text = ":::{graphviz}\n:engine: bogus\n\ndigraph G { a -> b }\n:::\n"
        with self.assertRaises(gp.GraphvizDirectiveError):
            gp.process(text, self.assets_dir, _ENGINE_BINS, source_path="note.md")


class FindBlocksTests(unittest.TestCase):
    def test_no_blocks_returns_empty(self):
        blocks = list(gp._find_blocks(["hello", "world"]))
        self.assertEqual(blocks, [])

    def test_unterminated_block_is_ignored(self):
        lines = [":::{graphviz}", "digraph G { a -> b }"]
        blocks = list(gp._find_blocks(lines))
        self.assertEqual(blocks, [])  # left untouched - myst build --strict will flag it


if __name__ == "__main__":
    unittest.main()
