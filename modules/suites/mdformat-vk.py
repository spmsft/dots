#!/usr/bin/env python3
"""mdformat-vk - MyST-safe mdformat wrapper.

mdformat-myst (the mdformat plugin that understands MyST directives/
roles/math) does not support MyST's *colon-fence* directive syntax
(`:::{name} ... :::`) - only the backtick-fence form (`` ```{name}
... ``` ``). Running mdformat directly on a colon-fenced file corrupts
it (e.g. `:::{note}` becomes `:::\\{note}` - see
executablebooks/mdformat-myst#13, unfixed upstream).

This wrapper shields every colon-fenced block (matched with the exact
same nesting rule mdit-py-plugins' colon_fence rule itself uses: a
fence of length N closes at the first later line that is colons-only
of length >= N, mirroring plain CommonMark code-fence semantics) from
mdformat by replacing each one with a unique placeholder line before
formatting, then splices the original block back in verbatim
afterwards. Everything outside colon-fenced blocks (headings,
paragraphs, tables, backtick-fenced directives, footnotes, math, etc.)
is formatted normally by mdformat+mdformat-myst.

Usage: mdformat-vk -   (reads stdin, writes stdout - matches Helix's
                        `formatter = { command = ...; args = [...] }`
                        contract)
       mdformat-vk <file>...   (in-place, like plain mdformat)
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
import uuid

_FENCE_LINE_RE = re.compile(r"^(?P<indent>[ \t]*)(?P<colons>:{3,})(?P<rest>.*)$")


def _is_close_line(line: str, indent: str, length: int) -> bool:
    """True if `line` closes a fence opened with `indent`/`length` colons."""
    m = _FENCE_LINE_RE.match(line)
    if not m or m.group("indent") != indent:
        return False
    if m.group("rest").strip():
        return False  # closing marker's tail must be blank (colons only)
    return len(m.group("colons")) >= length


def shield(text: str) -> tuple[str, dict[str, str]]:
    """Replace every colon-fenced block with a unique placeholder line.

    Returns (shielded_text, {placeholder: original_block_text}).
    """
    lines = text.splitlines(keepends=True)
    out: list[str] = []
    placeholders: dict[str, str] = {}
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        m = _FENCE_LINE_RE.match(line.rstrip("\n"))
        if m:
            indent = m.group("indent")
            length = len(m.group("colons"))
            # Find the matching close, scanning forward (same rule as
            # mdit_py_plugins.colon_fence: first line at/after i+1 whose
            # colon run is >= length, with a blank tail).
            j = i + 1
            close = None
            while j < n:
                if _is_close_line(lines[j].rstrip("\n"), indent, length):
                    close = j
                    break
                j += 1
            if close is not None:
                block = "".join(lines[i : close + 1])
                placeholder = f"<!--mdformat-vk-{uuid.uuid4().hex}-->"
                placeholders[placeholder] = block
                out.append(placeholder + "\n")
                i = close + 1
                continue
            # Unclosed fence (autocloses at end of doc, per the same
            # rule) - shield the rest of the file as one block.
            block = "".join(lines[i:])
            placeholder = f"<!--mdformat-vk-{uuid.uuid4().hex}-->"
            placeholders[placeholder] = block
            out.append(placeholder + "\n")
            break
        out.append(line)
        i += 1
    return "".join(out), placeholders


def unshield(text: str, placeholders: dict[str, str]) -> str:
    for placeholder, block in placeholders.items():
        # mdformat may reflow the placeholder's surrounding blank lines
        # but leaves the (single-line, no special characters) HTML
        # comment itself untouched as its own paragraph.
        text = text.replace(placeholder, block.rstrip("\n"))
    return text


def format_text(text: str, mdformat_args: list[str]) -> str:
    # MDFORMAT_VK_REAL_BIN lets the Nix wrapper point this at the real
    # `mdformat` binary (from the python3.withPackages env) without a
    # name collision with this script's own installed name (see
    # suites.dev-tools.markdownFormat in modules/suites/dev-tools.nix).
    real_bin = os.environ.get("MDFORMAT_VK_REAL_BIN", "mdformat")
    shielded, placeholders = shield(text)
    result = subprocess.run(
        [real_bin, *mdformat_args, "-"],
        input=shielded,
        capture_output=True,
        text=True,
        check=True,
    )
    return unshield(result.stdout, placeholders)


def main(argv: list[str]) -> int:
    if not argv or argv == ["-"]:
        sys.stdout.write(format_text(sys.stdin.read(), []))
        return 0
    for path in argv:
        with open(path, encoding="utf-8") as fh:
            original = fh.read()
        formatted = format_text(original, [])
        if formatted != original:
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(formatted)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
