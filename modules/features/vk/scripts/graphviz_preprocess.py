#!/usr/bin/env python3
"""vk Graphviz directive preprocessor.

MyST has no native Graphviz support and no maintained community plugin
exists for it (unlike Mermaid, which MyST renders natively - keep using
that for ordinary flowcharts/sequence diagrams; reserve Graphviz for
dependency graphs and other layout-heavy diagrams). This script renders
Graphviz DOT source to static SVG *during staging only*, the same way
scripts/taskwarrior_preprocess.py handles the `taskwarrior` directive:
scan a single Markdown file for `graphviz` directive blocks, replace only
those blocks, and leave every other line - including any other MyST
directive/role - completely untouched.

Directive syntax:

    :::{graphviz}
    :engine: dot
    :label: fig-mygraph
    :alt: Short accessible description
    :class: some-class

    digraph G { a -> b }
    :::

Recognized options: engine (dot/neato/fdp/sfdp/circo/twopi, default dot),
label, alt, class. The directive argument (if any) becomes the figure
caption.

Rendering is content-addressed: the SVG is written to
`<staging>/assets/graphviz/<sha256-of-dot-source-and-engine>.svg` so
identical diagrams across rebuilds - or across multiple notes - produce
byte-identical, cache-friendly output and never bump mtimes needlessly.
The directive block is replaced with a plain MyST `figure` directive
referencing that SVG, so the same artifact renders identically for HTML
and Typst/PDF exports without any Graphviz-specific code downstream.
"""

import argparse
import hashlib
import posixpath
import re
import subprocess
import sys

_OPEN_RE = re.compile(r"^(:{3,})\{graphviz\}[ \t]*(.*?)[ \t]*$")
_OPTION_RE = re.compile(r"^:([A-Za-z0-9_-]+):[ \t]*(.*?)[ \t]*$")
_KNOWN_OPTIONS = ("engine", "label", "alt", "class")
_ENGINES = ("dot", "neato", "fdp", "sfdp", "circo", "twopi")


class GraphvizDirectiveError(Exception):
    """Raised for a directive with invalid options; carries a 1-based
    source line number so callers can report a path:line diagnostic."""

    def __init__(self, line_no, message):
        super().__init__(message)
        self.line_no = line_no
        self.message = message


def _find_blocks(lines):
    """Yield (start, end, title, options, body_lines) for each complete
    graphviz directive block. `start`/`end` are 0-based line indices;
    `end` is the index of the closing fence line (inclusive)."""
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
            # Unterminated directive - leave it untouched; a strict MyST
            # build (vk check) will surface its own parse error.
            i += 1
            continue

        body_lines = lines[body_start:end]
        yield (i, end, title, options, body_lines)
        i = end + 1


def _engine_bin(engine, engine_bins):
    if engine not in _ENGINES:
        raise ValueError(
            "unknown graphviz engine %r (expected one of: %s)"
            % (engine, ", ".join(_ENGINES))
        )
    path = engine_bins.get(engine)
    if not path:
        raise ValueError("no binary path configured for engine %r" % engine)
    return path


def _render_svg(dot_source, engine, engine_bins):
    exe = _engine_bin(engine, engine_bins)
    # Invoke the engine binary directly (argv list, no shell) so DOT
    # source is never interpreted by a shell regardless of content.
    result = subprocess.run(
        [exe, "-Tsvg"],
        input=dot_source,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "graphviz rendering failed")
    return result.stdout


def _write_svg(staging_assets_dir, svg_text, digest):
    import os

    out_dir = os.path.join(staging_assets_dir, "graphviz")
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, "%s.svg" % digest)
    if not os.path.exists(out_path):
        tmp_path = out_path + ".vk-tmp"
        with open(tmp_path, "w", encoding="utf-8") as f:
            f.write(svg_text)
        os.replace(tmp_path, out_path)
    return out_path


def _render_block(title, options, body_lines, staging_assets_dir, engine_bins,
                   source_path, line_no, doc_rel_dir=""):
    engine = options.get("engine", "dot").strip() or "dot"
    dot_source = "\n".join(body_lines).strip("\n")
    if not dot_source.strip():
        raise GraphvizDirectiveError(
            line_no, "empty graphviz directive body in %s" % source_path
        )

    try:
        svg_text = _render_svg(dot_source, engine, engine_bins)
    except ValueError as exc:
        raise GraphvizDirectiveError(
            line_no, "%s:%d: graphviz error: %s" % (source_path, line_no, exc)
        ) from exc

    digest = hashlib.sha256((engine + "\0" + dot_source).encode("utf-8")).hexdigest()[:16]
    svg_path = _write_svg(staging_assets_dir, svg_text, digest)
    # `staging_assets_dir` is always <staging-root>/assets, but the note
    # being rewritten may itself live one level down (materials/records/
    # texts, per vk's flat-per-category convention) - a bare
    # "assets/graphviz/..." reference would then resolve relative to the
    # note's own directory (e.g. "materials/assets/...") and 404. Make the
    # emitted path relative to the note's directory instead, so it works
    # whether the note is at the staging root or one category level deep.
    abs_path = posixpath.join("assets", "graphviz", "%s.svg" % digest)
    rel_path = posixpath.relpath(abs_path, doc_rel_dir or ".")

    attrs = []
    if options.get("label", "").strip():
        attrs.append(":label: %s" % options["label"].strip())
    if options.get("alt", "").strip():
        attrs.append(":alt: %s" % options["alt"].strip())
    if options.get("class", "").strip():
        attrs.append(":class: %s" % options["class"].strip())

    fence = ":::"
    out = ["%s{figure} %s" % (fence, rel_path)]
    out.extend(attrs)
    if title.strip():
        out.append("")
        out.append(title.strip())
    out.append(fence)
    return "\n".join(out), svg_path


def process(text, staging_assets_dir, engine_bins, source_path="<unknown>",
            doc_rel_dir=""):
    lines = text.split("\n")
    blocks = list(_find_blocks(lines))
    if not blocks:
        return text, []

    out = []
    cursor = 0
    written = []
    for start, end, title, options, body_lines in blocks:
        out.extend(lines[cursor:start])
        rendered, svg_path = _render_block(
            title, options, body_lines, staging_assets_dir, engine_bins,
            source_path, start + 1, doc_rel_dir=doc_rel_dir,
        )
        out.append(rendered)
        written.append(svg_path)
        cursor = end + 1
    out.extend(lines[cursor:])
    return "\n".join(out), written


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", help="Source Markdown file")
    parser.add_argument("output", help="Destination Markdown file (staging tree)")
    parser.add_argument("--staging-assets-dir", required=True,
                         help="Path to <staging>/assets")
    parser.add_argument("--doc-rel-dir", default="",
                         help="Note's directory relative to the staging root "
                              "(e.g. 'materials'; empty/'.' for the staging "
                              "root itself) - used to emit a correct relative "
                              "image path for notes one category level deep.")
    parser.add_argument("--dot", required=True)
    parser.add_argument("--neato", required=True)
    parser.add_argument("--fdp", required=True)
    parser.add_argument("--sfdp", required=True)
    parser.add_argument("--circo", required=True)
    parser.add_argument("--twopi", required=True)
    args = parser.parse_args(argv)

    engine_bins = {
        "dot": args.dot,
        "neato": args.neato,
        "fdp": args.fdp,
        "sfdp": args.sfdp,
        "circo": args.circo,
        "twopi": args.twopi,
    }

    with open(args.input, "r", encoding="utf-8") as f:
        text = f.read()

    try:
        result, _written = process(text, args.staging_assets_dir, engine_bins,
                                    source_path=args.input,
                                    doc_rel_dir=args.doc_rel_dir)
    except GraphvizDirectiveError as exc:
        sys.stderr.write("vk: %s\n" % exc.message)
        sys.exit(1)

    with open(args.output, "w", encoding="utf-8") as f:
        f.write(result)


if __name__ == "__main__":
    main()
