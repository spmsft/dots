#!/usr/bin/env python3
"""vk Taskwarrior directive preprocessor.

MyST is vk's only Markdown parser/renderer (see modules/features/vk.nix
and vk.sh); Pandoc is used *only* as a narrow preprocessing step for the
`taskwarrior` directive, because no released Pandoc (including current
upstream) understands MyST directive syntax directly. This script:

  1. Scans a single Markdown file for complete MyST `taskwarrior`
     directive blocks:

         :::{taskwarrior} Optional Title
         :project: gql-spec
         :status: pending
         :tags: database,gql
         :limit: 5

         Optional fallback body.
         :::

  2. Converts *only* each matched block (not the rest of the document)
     into the equivalent Pandoc fenced-Div syntax, pipes it through
     `pandoc --lua-filter=taskwarrior.lua`, and splices the resulting
     plain Markdown back in place of the original block.

Every other line of the document - including any other MyST directive,
role, or plain Markdown - passes through completely untouched, so a full
Pandoc round-trip (which risks mangling MyST-only syntax elsewhere) is
never performed. If a file has no `taskwarrior` directive at all, this
script still produces byte-identical output (safe to run unconditionally
during staging).
"""

import argparse
import re
import subprocess
import sys

# Opening fence: 3+ colons, "{taskwarrior}", optional trailing title text.
_OPEN_RE = re.compile(r"^(:{3,})\{taskwarrior\}[ \t]*(.*?)[ \t]*$")
# MyST directive option line: ":key: value" (only recognized directly
# under the opening fence, before the blank line that starts the body).
_OPTION_RE = re.compile(r"^:([A-Za-z0-9_-]+):[ \t]*(.*?)[ \t]*$")

_KNOWN_OPTIONS = ("project", "status", "tags", "limit")


def _escape_attr(value: str) -> str:
    """Escape a value for a Pandoc double-quoted Div attribute."""
    return value.replace("\\", "\\\\").replace('"', '\\"')


def _find_blocks(lines):
    """Yield (start, end, fence, title, options, body_lines) for each
    complete taskwarrior directive block. `start`/`end` are 0-based line
    indices; `end` is the index of the closing fence line (inclusive)."""
    i = 0
    n = len(lines)
    while i < n:
        m = _OPEN_RE.match(lines[i])
        if not m:
            i += 1
            continue
        fence, title = m.group(1), m.group(2)
        close_re = re.compile(r"^" + re.escape(fence) + r"[ \t]*$")

        j = i + 1
        options = {}
        while j < n:
            opt_m = _OPTION_RE.match(lines[j])
            if opt_m and opt_m.group(1).lower() in _KNOWN_OPTIONS:
                options[opt_m.group(1).lower()] = opt_m.group(2)
                j += 1
                continue
            break
        # Skip a single blank line separating options from the body, if
        # present (MyST convention).
        if j < n and lines[j].strip() == "":
            j += 1

        body_start = j
        end = None
        while j < n:
            if close_re.match(lines[j]):
                end = j
                break
            j += 1

        if end is None:
            # Unterminated directive - leave it untouched rather than
            # guessing; MyST/pandoc will surface its own parse error.
            i += 1
            continue

        body_lines = lines[body_start:end]
        yield (i, end, fence, title, options, body_lines)
        i = end + 1


def _render_block(pandoc_bin, lua_filter, title, options, body_lines):
    attrs = []
    if title:
        attrs.append('title="%s"' % _escape_attr(title))
    for key in _KNOWN_OPTIONS:
        if key in options and options[key] != "":
            attrs.append('%s="%s"' % (key, _escape_attr(options[key])))

    pandoc_src = "::: {.taskwarrior %s}\n%s\n:::\n" % (
        " ".join(attrs),
        "\n".join(body_lines).strip("\n"),
    )

    result = subprocess.run(
        [pandoc_bin, "-f", "markdown", "-t", "markdown",
         "--lua-filter=%s" % lua_filter],
        input=pandoc_src,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        # Preprocessing itself failing (not a task-query failure, which
        # the Lua filter already handles gracefully) should still not
        # silently swallow content - fall back to the original fallback
        # body text alone, with a short generated note.
        sys.stderr.write(
            "vk: taskwarrior directive preprocessing failed, "
            "using fallback content:\n%s\n" % result.stderr
        )
        fallback = "\n".join(body_lines).strip("\n")
        note = "*Taskwarrior directive preprocessing failed.*"
        return (fallback + "\n\n" + note) if fallback else note

    return result.stdout.strip("\n")


def process(text, pandoc_bin, lua_filter):
    lines = text.split("\n")
    blocks = list(_find_blocks(lines))
    if not blocks:
        return text

    out = []
    cursor = 0
    for start, end, _fence, title, options, body_lines in blocks:
        out.extend(lines[cursor:start])
        rendered = _render_block(pandoc_bin, lua_filter, title, options, body_lines)
        out.append(rendered)
        cursor = end + 1
    out.extend(lines[cursor:])
    return "\n".join(out)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", help="Source Markdown file")
    parser.add_argument("output", help="Destination Markdown file (staging tree)")
    parser.add_argument("--pandoc", required=True, help="Path to the pandoc binary")
    parser.add_argument("--lua-filter", required=True, help="Path to taskwarrior.lua")
    args = parser.parse_args(argv)

    with open(args.input, "r", encoding="utf-8") as f:
        text = f.read()

    result = process(text, args.pandoc, args.lua_filter)

    with open(args.output, "w", encoding="utf-8") as f:
        f.write(result)


if __name__ == "__main__":
    main()
