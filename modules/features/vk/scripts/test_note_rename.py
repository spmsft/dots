#!/usr/bin/env python3
"""Unit tests for note_rename.py - see test_vault_enhance.py for how to run."""

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

import note_rename as nr  # noqa: E402


def write(root, rel, content):
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    return path


class RenameNoteTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.vaults_root = Path(self.tmp.name)
        self.vault = self.vaults_root / "vault-a"
        self.vault.mkdir()

    def test_move_note_preserves_id_and_adds_alias(self):
        write(self.vault, "materials/general/old-name.md",
              "---\nid: my-id\ntitle: Old\n---\nBody.\n")
        nr.rename_item(self.vault, "materials/general/old-name.md", "materials/general/new-name.md")

        self.assertFalse((self.vault / "materials/general/old-name.md").exists())
        new_text = (self.vault / "materials/general/new-name.md").read_text()
        self.assertIn("id: my-id", new_text)
        self.assertIn("materials/general/old-name", new_text)  # alias recorded

    def test_move_asset_is_plain_move_no_frontmatter(self):
        write(self.vault, "assets/pic.png", "fake-binary-content")
        nr.rename_item(self.vault, "assets/pic.png", "assets/renamed.png")

        self.assertFalse((self.vault / "assets/pic.png").exists())
        self.assertEqual((self.vault / "assets/renamed.png").read_text(), "fake-binary-content")

    def test_rejects_existing_destination(self):
        write(self.vault, "a.md", "# A\n")
        write(self.vault, "b.md", "# B\n")
        with self.assertRaises(FileExistsError):
            nr.rename_item(self.vault, "a.md", "b.md")

    def test_rejects_missing_source(self):
        with self.assertRaises(FileNotFoundError):
            nr.rename_item(self.vault, "does-not-exist.md", "new.md")

    def test_same_vault_link_rewrite_preserves_extension(self):
        write(self.vault, "materials/general/note.md", "# Note\n")
        write(self.vault, "materials/general/other.md",
              "See [note](note.md) and image ![alt](../../assets/diagram.png).\n")
        write(self.vault, "assets/diagram.png", "img-bytes")

        nr.rename_item(self.vault, "materials/general/note.md", "materials/general/renamed.md")
        updated_text = (self.vault / "materials/general/other.md").read_text()
        self.assertIn("[note](renamed.md)", updated_text)

        nr.rename_item(self.vault, "assets/diagram.png", "assets/diagram-2.png")
        updated_text = (self.vault / "materials/general/other.md").read_text()
        self.assertIn("![alt](../../assets/diagram-2.png)", updated_text)
        self.assertTrue(updated_text.endswith(".png).\n"))  # extension preserved, not stripped

    def test_cross_vault_link_rewrite(self):
        other_vault = self.vaults_root / "vault-b"
        other_vault.mkdir()
        write(self.vault, "materials/general/note.md", "# Note\n")
        write(other_vault, "materials/general/referrer.md",
              "See [note](../../../vault-a/materials/general/note.md).\n")

        updated = nr.rename_item(self.vault, "materials/general/note.md", "materials/general/renamed.md")

        self.assertIn("vault-b/materials/general/referrer.md", updated)
        referrer_text = (other_vault / "materials/general/referrer.md").read_text()
        self.assertIn("renamed.md", referrer_text)
        self.assertNotIn("$HOME", referrer_text)
        self.assertNotIn(str(self.vaults_root), referrer_text)  # no absolute-path leakage

    def test_own_body_never_rewritten(self):
        write(self.vault, "materials/general/note.md",
              "# Note\n\nSelf-link: [self](note.md)\n")
        nr.rename_item(self.vault, "materials/general/note.md", "materials/general/renamed.md")
        text = (self.vault / "materials/general/renamed.md").read_text()
        self.assertIn("[self](note.md)", text)  # untouched, as documented


if __name__ == "__main__":
    unittest.main()
