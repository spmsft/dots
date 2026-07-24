#!/usr/bin/env bash
# vk - Terminal-first wiki & Zettelkasten engine.
#
# The Nix-level preamble (modules/features/vk.nix) resolves every external
# binary this script needs into the *_BIN variables below, and sets
# VAULTS_DIR/VK_FILTERS_SRC_DIR/VK_SHORTCODES_SRC_DIR before sourcing
# this file - keeping this static, shellcheck-able body free of any Nix
# syntax (mirrors the viewer.nix/clipboard.nix pattern: small Nix
# preamble + real shell file).
set -euo pipefail

mkdir -p "$VAULTS_DIR"

# Helper: list every real vault's name, one per line, sorted
# alphabetically. A "real" vault is any $VAULTS_DIR subdirectory that
# owns its own _quarto.yml (written by 'vk new') - this deliberately
# excludes $VAULTS_DIR's own root-project artifacts ('vk serve-all'
# regenerates _site/, site_libs/, .quarto/, index.md, imprint.md and
# _quarto.yml directly inside $VAULTS_DIR itself, none of which are
# vaults) from ever appearing in a vault picker or listing.
list_vaults() {
    local v name
    for v in "$VAULTS_DIR"/*/; do
        v="${v%/}"
        [ -f "$v/_quarto.yml" ] || continue
        name=$(basename "$v")
        echo "$name"
    done | sort
}

# Helper: Ensure vault argument or select interactively via gum.
get_vault() {
    local name="${1:-}"
    if [ -z "$name" ]; then
        local vaults
        vaults=$(list_vaults)
        if [ -n "$vaults" ]; then
            name=$(echo "$vaults" | "$GUM_BIN" choose --header "Select target vault:")
        else
            name=$("$GUM_BIN" input --placeholder "No vaults found. Enter name for a new vault:")
        fi
    fi
    echo "$name"
}

# Helper: ensure a vault has its own main.md - the free-form, hand-edited
# landing-page content that index.md includes via a quarto shortcode
# (see 'new' and index.md's template below). Only ever generated when
# missing (never overwritten). Seeded empty: index.md's own front-matter
# "title" already renders the vault name as the page header via
# quarto's title block, so an explicit "# $name" heading here would
# just duplicate it in the body.
ensure_main_md() {
    local path="$1"
    if [ ! -f "$path/main.md" ]; then
        : > "$path/main.md"
    fi
}

# Helper: (re)install every vk-managed Lua filter/shortcode into vault
# $1 - unlike main.md/imprint.md (only seeded if missing, since those
# are meant to be hand-edited), these are vk-owned script files never
# meant to be hand-edited in a vault, so a vk.sh upgrade should always
# propagate to every existing vault on next use. Each file is
# compared before writing (see the cmp -s guard below) rather than
# unconditionally cp'd, purely to avoid bumping mtimes when nothing
# actually changed - see that guard's own comment for why that matters.
#
# Two different kinds, mirroring how quarto itself distinguishes them:
#   - Plain whole-document AST filters (VK_FILTERS_SRC_DIR/*.lua, e.g.
#     wikilinks.lua) are copied to the vault root and referenced via
#     _quarto.yml's format.html.filters: list - ensure_quarto_filters_yml()
#     (below) keeps that list in sync idempotently.
#   - Shortcode extensions (VK_SHORTCODES_SRC_DIR/*/, e.g.
#     shortcodes/taskwarrior/) are quarto extensions proper (their own
#     _extension.yml + .lua), copied wholesale into the vault's
#     _extensions/<name>/ - quarto auto-discovers any shortcode
#     extension present there, no _quarto.yml wiring needed at all.
sync_vk_filters() {
    local path="$1"
    local filter_src filter_base shortcode_dir shortcode_base f rel
    mkdir -p "$path/_extensions"
    for filter_src in "$VK_FILTERS_SRC_DIR"/*.lua; do
        [ -e "$filter_src" ] || continue
        filter_base=$(basename "$filter_src")
        # cmp -s guard before writing - a plain unconditional `cp` would
        # bump the destination's mtime on every call even when content
        # is unchanged, which would make vault_needs_build() (mtime-
        # based) think the vault changed on *every single* serve-all
        # poll, rebuilding forever (the same class of bug already fixed
        # once for regen_category_index()/root index.md - see
        # memory-bank/decisions.md's 2026-07-23 entries).
        cmp -s "$filter_src" "$path/$filter_base" 2>/dev/null || cp "$filter_src" "$path/$filter_base"
        ensure_quarto_filters_yml "$path" "$filter_base"
    done
    for shortcode_dir in "$VK_SHORTCODES_SRC_DIR"/*/; do
        [ -d "$shortcode_dir" ] || continue
        shortcode_base=$(basename "$shortcode_dir")
        mkdir -p "$path/_extensions/$shortcode_base"
        while IFS= read -r -d '' f; do
            rel="${f#"$shortcode_dir"}"
            cmp -s "$f" "$path/_extensions/$shortcode_base/$rel" 2>/dev/null || \
                cp "$f" "$path/_extensions/$shortcode_base/$rel"
        done < <(find "$shortcode_dir" -type f -print0)
    done
}

# Helper: ensure _quarto.yml at $1 lists filter $2 under
# format.html.filters: - idempotent (no-op if already listed), and a
# no-op entirely if the vault has no _quarto.yml yet (shouldn't happen
# in practice - 'vk new' always writes one before ever calling
# sync_vk_filters(), but this guards against a partially-initialized
# vault directory).
ensure_quarto_filters_yml() {
    local quarto_yml="$1/_quarto.yml" filter_base="$2"
    [ -f "$quarto_yml" ] || return 0
    grep -qxF "      - $filter_base" "$quarto_yml" && return 0
    if grep -qx "    filters:" "$quarto_yml"; then
        sed -i "/^    filters:\$/a\\      - $filter_base" "$quarto_yml"
    fi
}

# Helper: (re)generate one category's own index.md as an actual listing
# of every note inside it (title from the note's own front matter,
# falling back to the filename when a note has none), sorted
# alphabetically by that title - rather than the empty file 'vk new'
# touches into existence at vault-creation time. Writes only when the
# generated content actually differs, so an unrelated call (e.g. from
# serve-all's polling loop) doesn't spuriously bump this file's mtime
# and trigger vault_needs_build() to rebuild the vault every single
# poll even when nothing really changed.
regen_category_index() {
    local dir="$1" title="$2"
    local f base note_title tmp
    tmp=$(mktemp)
    {
        echo '---'
        echo "title: \"$title\""
        echo '---'
        echo
        # No body heading here - front matter's "title" above already
        # renders as the page header via quarto's title block, so a
        # "# $title" heading here would just duplicate it.
        for f in "$dir"/*.md; do
            [ -e "$f" ] || continue
            base=$(basename "$f")
            [ "$base" = "index.md" ] && continue
            note_title=$(grep -m1 '^title:' "$f" 2>/dev/null | sed -E 's/^title:[[:space:]]*"?//; s/"?[[:space:]]*$//')
            [ -z "$note_title" ] && note_title="${base%.md}"
            printf '%s\t%s\n' "$note_title" "$base"
        done | sort | while IFS=$'\t' read -r note_title base; do
            echo "- [[$base|$note_title]]"
        done
    } > "$tmp"
    if ! cmp -s "$tmp" "$dir/index.md" 2>/dev/null; then
        mv "$tmp" "$dir/index.md"
    else
        rm -f "$tmp"
    fi
}

# Helper: regenerate all three of a vault's category listings
# (materials/records/texts). Called from cd_vault() (so every vk command
# that touches a vault refreshes them) and from serve_all_rebuild()'s
# per-vault loop (which reaches vaults without going through cd_vault).
regen_category_indexes() {
    local vault_path="$1"
    regen_category_index "$vault_path/materials" "Materials"
    regen_category_index "$vault_path/records" "Records"
    regen_category_index "$vault_path/texts" "Texts"
}

# Helper: cd into an existing vault, or fail with a clear message instead
# of a bare "set -e" exit from a failed cd.
cd_vault() {
    local name="$1"
    local path="$VAULTS_DIR/$name"
    if [ -z "$name" ]; then
        echo "No vault selected." >&2
        exit 1
    fi
    if [ ! -d "$path" ]; then
        echo "Error: vault '$name' does not exist at $path (use 'vk new' first)." >&2
        exit 1
    fi
    ensure_main_md "$path"
    regen_category_indexes "$path"
    sync_vk_filters "$path"
    cd "$path"
}

# Helper: pull dufs' own -p/--port and -b/--bind/--host flags (plus their
# --flag=value forms) out of the remaining CLI args, for 'watch' and
# 'serve-all'. Anything left over is collected into POSITIONAL[] (e.g.
# the vault name for 'watch') so flags can be given in any order, before
# or after the vault name. PORT defaults to 5050 (vk's own default, not
# dufs' built-in 5000) unless overridden; BIND stays empty and falls
# back to dufs' own default (0.0.0.0) when unset.
parse_serve_flags() {
    PORT="5050"
    BIND=""
    POSITIONAL=()
    while [ $# -gt 0 ]; do
        case "$1" in
            -p|--port)
                PORT="${2:?--port requires a value}"
                shift 2
                ;;
            --port=*)
                PORT="${1#*=}"
                shift
                ;;
            -b|--bind|--host)
                BIND="${2:?--bind/--host requires a value}"
                shift 2
                ;;
            --bind=*|--host=*)
                BIND="${1#*=}"
                shift
                ;;
            *)
                POSITIONAL+=("$1")
                shift
                ;;
        esac
    done
}

# Helper: build the dufs argv array (DUFS_ARGS) from PORT/BIND (set by
# parse_serve_flags). Must run in the current shell, not a subshell/command
# substitution, since it sets a global array.
build_dufs_args() {
    DUFS_ARGS=()
    if [ -n "$PORT" ]; then DUFS_ARGS+=(--port "$PORT"); fi
    if [ -n "$BIND" ]; then DUFS_ARGS+=(--bind "$BIND"); fi
}

# Helper: the URL dufs will actually be reachable at, given PORT/BIND
# (PORT defaults to 5050 via parse_serve_flags; BIND falls back to
# dufs' own default, 0.0.0.0, when unset).
dufs_url() {
    echo "http://${BIND:-0.0.0.0}:${PORT:-5050}"
}

# Helper: substring/fuzzy content search over $1 (a directory - either "."
# from inside an already-cd'd vault, or $VAULTS_DIR for a global,
# cross-vault search), shared by 'vk search' and 'vk note's "Fuzzy Search
# Text". Passing the search root straight to rg (rather than cd-ing into
# it) means the paths rg prints are always valid from the caller's cwd -
# required for the global case, which runs before any cd_vault.
search_content() {
    local root="$1"
    local placeholder="${2:-Search body content...}"
    local selection
    # gum >=0.14 dropped the old --ansi flag in favor of --strip-ansi/
    # --no-strip-ansi (default: don't strip), so no flag is needed here
    # to preserve rg's --color=always highlighting.
    selection=$("$RG_BIN" --line-number --no-heading --color=always --glob '!_site/**' --glob '!_extensions/**' --glob '!site_libs/**' --glob '!.quarto/**' . "$root" | "$GUM_BIN" filter --placeholder "$placeholder")
    if [ -z "$selection" ]; then exit 1; fi
    local file line
    file=$(echo "$selection" | cut -d: -f1)
    line=$(echo "$selection" | cut -d: -f2)
    "$HX_BIN" "$file:$line"
}

# Helper: interactively prompt for category + subtype, in that order
# (subtype choices depend on the chosen category) - sets CAT/TYPE.
# Shared by 'vk note's "Create Note" action and every 'vk import' mode
# so the categories/subtypes/their alphabetical ordering only need to
# be maintained in one place.
prompt_category_type() {
    CAT=$("$GUM_BIN" choose "materials" "records" "texts")
    case "$CAT" in
        records) TYPE=$("$GUM_BIN" choose "event" "note" "observation") ;;
        materials) TYPE=$("$GUM_BIN" choose "entity" "project" "quote" "source" "topic") ;;
        texts) TYPE=$("$GUM_BIN" choose "article" "guide" "hub") ;;
    esac
}

# Helper: write a new note file at "$CAT/$TITLE.md" with standard
# front matter (records get a full date+time stamp, others just a
# date - see 'vk note's original comment on why), and a body read from
# stdin. Sets NOTE_FILE to the written path. Shared by 'vk note's
# "Create Note" action and every 'vk import' mode.
write_note() {
    local cat="$1" type="$2" title="$3"
    local file="$cat/${title%.md}.md"
    local date_stamp
    if [ "$cat" = "records" ]; then
        date_stamp=$(date '+%Y-%m-%d %H:%M')
    else
        date_stamp=$(date +%Y-%m-%d)
    fi
    {
        echo "---"
        echo "title: \"${title//_/ }\""
        echo "type: $type"
        echo "date: $date_stamp"
        echo "---"
        echo
        cat
    } > "$file"
    NOTE_FILE="$file"
}

# Helper: best-effort <meta property="$2"|name="$2" content="..."/>
# extraction from a fetched HTML file $1 - tries both attribute orders
# since real-world pages vary. Prints the extracted value (possibly
# empty) and always exits 0 so callers can chain multiple lookups
# without `set -e` aborting on a miss.
extract_meta_tag() {
    local html="$1" key="$2" val=""
    val=$("$RG_BIN" -o -N "(?:property|name)=\"$key\"[^>]*content=\"([^\"]*)\"" -r '$1' "$html" 2>/dev/null | head -1) || true
    if [ -z "$val" ]; then
        val=$("$RG_BIN" -o -N "content=\"([^\"]*)\"[^>]*(?:property|name)=\"$key\"" -r '$1' "$html" 2>/dev/null | head -1) || true
    fi
    printf '%s' "$val"
}

# Helper: best-effort BibTeX field extraction from a pasted entry $1 -
# handles both brace-delimited (`title = {Foo}`) and quote-delimited
# (`title = "Foo"`) values, case-insensitively (BibTeX field names are
# conventionally lowercase but not enforced). Prints the value
# (possibly empty).
bib_field() {
    local entry="$1" field="$2" val=""
    val=$(printf '%s' "$entry" | "$RG_BIN" -o -N -i "$field\s*=\s*[{\"]([^}\"]*)[}\"]" -r '$1' | head -1) || true
    printf '%s' "$val"
}

# Helper: render a pasted BibTeX entry $1 as a single human-readable
# citation line - "Authors. *Title*. Rest." (title italicized,
# remaining bits - venue/volume/pages/year - comma-joined into "Rest"),
# rather than reaching for citeproc's default CSL style (which
# typically quotes article titles and italicizes the *venue* instead -
# the opposite of what was wanted here). Falls back to pandoc
# --citeproc only if no title/author could be parsed at all (e.g. a
# malformed or unusually-shaped entry).
format_bib_entry() {
    local entry="$1"
    local authors title year venue volume pages rest formatted
    authors=$(bib_field "$entry" author)
    authors="${authors// and /, }"
    title=$(bib_field "$entry" title)
    year=$(bib_field "$entry" year)
    venue=$(bib_field "$entry" journal)
    [ -z "$venue" ] && venue=$(bib_field "$entry" booktitle)
    [ -z "$venue" ] && venue=$(bib_field "$entry" publisher)
    volume=$(bib_field "$entry" volume)
    pages=$(bib_field "$entry" pages)

    if [ -z "$title" ] && [ -z "$authors" ]; then
        local citekey tmp_dir
        citekey=$(printf '%s' "$entry" | "$RG_BIN" -o -N '^@\w+\{([^,]+),' -r '$1' | head -1)
        if [ -n "$citekey" ]; then
            tmp_dir=$(mktemp -d)
            echo "$entry" > "$tmp_dir/refs.bib"
            printf '[@%s]\n' "$citekey" > "$tmp_dir/cite.md"
            formatted=$("$PANDOC_BIN" "$tmp_dir/cite.md" --citeproc --bibliography="$tmp_dir/refs.bib" --to plain 2>/dev/null || true)
            rm -rf "$tmp_dir"
        fi
        [ -z "$formatted" ] && formatted="(Could not render a formatted citation - check the pasted BibTeX entry is valid.)"
        printf '%s' "$formatted"
        return
    fi

    rest=""
    [ -n "$venue" ] && rest="$venue"
    if [ -n "$volume" ]; then
        rest="${rest:+$rest, }vol. $volume"
    fi
    if [ -n "$pages" ]; then
        rest="${rest:+$rest, }pp. $pages"
    fi
    [ -n "$year" ] && rest="${rest:+$rest, }$year"

    formatted=""
    [ -n "$authors" ] && formatted="$authors. "
    formatted="${formatted}*${title:-Untitled}*."
    [ -n "$rest" ] && formatted="$formatted $rest."
    printf '%s' "$formatted"
}

# Helper: 'vk import file'/'vk import page' both need MarkItDown
# (Microsoft's file/URL -> Markdown converter) - deliberately NOT
# nix-packaged (nixpkgs' python3Packages.markitdown pulls a huge,
# currently-broken dependency closure - pandas/pdfplumber/arrow-cpp).
# Required instead via `uvx`, which is already on $PATH via
# suites.dev-tools.uv (default-on) and caches its own tool install
# after the first (slow, ~30s) run.
require_uvx() {
    if ! command -v uvx >/dev/null 2>&1; then
        echo "Error: 'uvx' not found on \$PATH. 'vk import file/page' needs MarkItDown, run via 'uvx markitdown' (see suites.dev-tools.uv, default-enabled) - install uv if this is a minimal host without it." >&2
        exit 1
    fi
}

# Helper: does vault $1 (a path) have any source file newer than its
# own _site output, or no _site at all yet? Drives serve-all's
# automatic per-vault rebuild-on-change - excludes quarto's own
# generated/cache dirs (and .git) from the comparison so a stale _site
# doesn't "self-trigger" a rebuild forever once one has run.
vault_needs_build() {
    local path="$1"
    [ -d "$path/_site" ] || return 0
    find "$path" -mindepth 1 \
        \( -path "$path/_site" -o -path "$path/.quarto" -o -path "$path/site_libs" -o -path "$path/.git" \) -prune -o \
        -type f -newer "$path/_site" -print -quit 2>/dev/null | grep -q .
}

# Helper: (re)generate the Vaults-root itself as a small quarto project
# for 'vk serve-all' - its own _quarto.yml + index.md (fully re-derived
# every call) plus a render of every top-level *.md page there
# (imprint.md and any other global page the user drops in
# $VAULTS_DIR - e.g. about.md, changelog.md - are all discovered and
# rendered generically, not just imprint.md specifically). Also builds
# (or rebuilds, on any source-file change - see vault_needs_build())
# every real vault automatically, then refreshes the per-vault _site
# symlinks - so the whole thing picks up *any* change (new/edited
# notes, brand-new never-built vaults, removed vaults, global
# pages/assets) with no manual 'vk build' step. Called once up front
# and then repeatedly from serve-all's background watch loop (pass
# quiet=1 there to suppress quarto's normally-verbose render log and
# per-vault build failures on every poll).
serve_all_rebuild() {
    local quiet="${1:-0}"
    local name bn disp f path

    mkdir -p "$VAULTS_DIR/assets"
    if [ ! -f "$VAULTS_DIR/imprint.md" ]; then
        cp "$IMPRINT_MD_SRC" "$VAULTS_DIR/imprint.md"
    fi

    # `resources: assets/**` copies $VAULTS_DIR/assets verbatim into
    # _site/assets, regardless of whether every file in it is actually
    # referenced from a rendered page.
    cat <<QUARTOEOF > "$VAULTS_DIR/_quarto.yml"
project:
  type: website
  output-dir: _site
  resources:
    - assets/**

website:
  title: "Vaults"
  search: true
  page-footer:
    right: "[Imprint](/imprint.html)"

format:
  html:
    theme: cosmo
    toc: false
    code-fold: true
QUARTOEOF

    # Real vaults: subdirectories owning their own _quarto.yml.
    # list_vaults() is already sorted alphabetically, so splitting it
    # below preserves that order without a separate sort pass.
    local all_vaults=()
    while IFS= read -r name; do
        [ -n "$name" ] && all_vaults+=("$name")
    done < <(list_vaults)

    # Build (or rebuild, if any of its own source files changed since
    # its last render) every real vault automatically. This is the
    # step that makes serve-all's background loop pick up *any* change
    # rather than just newly-appearing global pages/assets at the
    # Vaults root - a note edit, a brand-new never-built vault, etc.
    # all get (re)rendered on the next poll with no manual 'vk build'.
    for name in "${all_vaults[@]}"; do
        path="$VAULTS_DIR/$name"
        # Regenerate category listings first (a note added/removed since
        # the last poll counts as "a source file changed" too) - only
        # actually rewrites index.md when content differs, so this alone
        # never spuriously triggers vault_needs_build() below.
        regen_category_indexes "$path"
        # Keep filters/shortcodes current too (a vk.sh upgrade that adds
        # or changes one should reach already-running vaults on the next
        # poll, not just brand-new 'vk new' vaults) - cheap, unconditional
        # file copies, so no mtime-guard needed here (unlike
        # regen_category_indexes's cmp -s check above).
        sync_vk_filters "$path"
        if vault_needs_build "$path"; then
            if [ "$quiet" = "1" ]; then
                (cd "$path" && "$QUARTO_BIN" render >/dev/null 2>&1) || true
            else
                (cd "$path" && "$QUARTO_BIN" render >/dev/null) ||
                    echo "⚠ Failed to build vault '$name' - see 'vk build $name' for details" >&2
            fi
        fi
    done

    BUILT=()
    UNBUILT=()
    for name in "${all_vaults[@]}"; do
        if [ -d "$VAULTS_DIR/$name/_site" ]; then
            BUILT+=("$name")
        else
            UNBUILT+=("$name")
        fi
    done

    # Every top-level *.md file except the generated index.md itself is
    # a "global page" - rendered and linked from the root index, in
    # addition to imprint.md's dedicated footer link. Sorted
    # alphabetically like every other vk listing.
    GLOBAL_PAGES=()
    for f in "$VAULTS_DIR"/*.md; do
        [ -e "$f" ] || continue
        bn=$(basename "$f")
        [ "$bn" = "index.md" ] && continue
        GLOBAL_PAGES+=("$bn")
    done
    if [ "${#GLOBAL_PAGES[@]}" -gt 0 ]; then
        mapfile -t GLOBAL_PAGES < <(printf '%s\n' "${GLOBAL_PAGES[@]}" | sort)
    fi

    {
        echo '---'
        echo 'title: "Vaults"'
        echo '---'
        echo
        # No body heading here - front matter's "title" above already
        # renders as the page header via quarto's title block.
        for name in "${BUILT[@]}"; do
            echo "- [$name](/$name/)"
        done
        if [ "${#UNBUILT[@]}" -gt 0 ]; then
            echo
            echo '## Failed to Build'
            echo
            echo "These vaults have a build error - see \`vk build <vault>\` for details:"
            echo
            for name in "${UNBUILT[@]}"; do
                echo "- $name"
            done
        fi
        if [ "${#GLOBAL_PAGES[@]}" -gt 0 ]; then
            echo
            echo '## Pages'
            echo
            for bn in "${GLOBAL_PAGES[@]}"; do
                disp="${bn%.md}"
                disp="${disp//_/ }"
                echo "- [$disp](/${bn%.md}.html)"
            done
        fi
    } > "$VAULTS_DIR/index.md"

    if [ "$quiet" = "1" ]; then
        (cd "$VAULTS_DIR" && "$QUARTO_BIN" render index.md >/dev/null 2>&1) || true
        for bn in "${GLOBAL_PAGES[@]}"; do
            (cd "$VAULTS_DIR" && "$QUARTO_BIN" render "$bn" >/dev/null 2>&1) || true
        done
    else
        (cd "$VAULTS_DIR" && "$QUARTO_BIN" render index.md >/dev/null)
        for bn in "${GLOBAL_PAGES[@]}"; do
            (cd "$VAULTS_DIR" && "$QUARTO_BIN" render "$bn" >/dev/null)
        done
    fi

    # Symlink each built vault's _site into the just-rendered root
    # _site, named after the vault itself (so "/<vault-name>/" serves it
    # directly, no /_site suffix needed) - drop any stale symlinks first
    # (e.g. a vault renamed/removed since the last rebuild).
    find "$VAULTS_DIR/_site" -maxdepth 1 -type l -delete
    for name in "${BUILT[@]}"; do
        ln -s "$VAULTS_DIR/$name/_site" "$VAULTS_DIR/_site/$name"
    done

    if [ "$quiet" != "1" ] && [ "${#UNBUILT[@]}" -gt 0 ]; then
        echo "⚠ Failed to build (see 'vk build <vault>'): ${UNBUILT[*]}" >&2
    fi
}

print_usage() {
    cat <<USAGEEOF
vk - Terminal-first wiki & Zettelkasten engine

Usage:
  vk new                                    Create a new vault (interactive)
  vk note [vault]                           Create/edit/delete/search notes (interactive)
  vk import [vault]                         Import content into a note: File/Code/Clipboard/
                                             Bibentry/Link/Page (interactive)
  vk search [vault|all]                     Substring-search one vault, or every vault at once
  vk rename [old] [new]                     Rename a vault (dir + baked-in title strings)
  vk watch [vault] [-p|--port PORT] [-b|--bind ADDR]
                                             Live Quarto preview + dufs server
  vk build [vault] [file PATH] [-p|--port PORT] [-b|--bind ADDR]
                                             Render the vault (or a single file) with Quarto
  vk serve-all [-p|--port PORT] [-b|--bind ADDR]
                                             Host all vaults at once: / lists them, /<vault> serves it
  vk help | -h | --help                     Show this message

[vault] may be omitted anywhere it's accepted - vk will prompt via gum.
-p/--port and -b/--bind (aliases: --host) are passed straight through to
dufs; both may also be given as --port=VALUE/--bind=VALUE, in any order,
before or after the vault name. Left unset, vk defaults to port 5050
(bind falls back to dufs' own default, 0.0.0.0).
USAGEEOF
}

# Main Command Router
case "${1:-}" in
    -h|--help|help)
        print_usage
        ;;

    new)
        VAULT_NAME=$("$GUM_BIN" input --placeholder "Enter new vault name (e.g., core-knowledge)...")
        if [ -z "$VAULT_NAME" ]; then exit 1; fi
        VAULT_PATH="$VAULTS_DIR/$VAULT_NAME"

        if [ -d "$VAULT_PATH" ]; then
            echo "Error: Vault already exists." && exit 1
        fi

        mkdir -p "$VAULT_PATH"/{texts,materials,records,_extensions,assets}
        ensure_main_md "$VAULT_PATH"

        # 1. Generate Base Index Configuration (categories listed
        # alphabetically, like every other listing in vk). The landing
        # page starts with main.md's hand-edited content (included live
        # via quarto's shortcode, so later edits to main.md show up
        # without regenerating index.md), followed by the one-link-per-
        # category list.
        cat <<NOTEEOF > "$VAULT_PATH/index.md"
---
title: "$VAULT_NAME"
---
{{< include main.md >}}

- [[materials/index.md|Materials]]
- [[records/index.md|Records]]
- [[texts/index.md|Texts]]
NOTEEOF
        touch "$VAULT_PATH/texts/index.md" "$VAULT_PATH/materials/index.md" "$VAULT_PATH/records/index.md"

        # 2. Generate Quarto Config (sidebar sections alphabetical too).
        # page-footer's Imprint link is an absolute path - it only
        # resolves when this vault is reached through 'vk serve-all'
        # (which also renders the Vaults-root project's own imprint.md
        # at that same absolute path), not when a vault's _site is
        # opened standalone. `resources: assets/**` copies the vault's
        # own assets/ dir into _site verbatim regardless of whether
        # every file in it happens to be referenced from a page.
        cat <<QUARTOEOF > "$VAULT_PATH/_quarto.yml"
project:
  type: website
  output-dir: _site
  resources:
    - assets/**

website:
  title: "$VAULT_NAME"
  search: true
  sidebar:
    style: "docked"
    search: true
    contents:
      - index.md
      - section: "Materials"
        contents: "materials/*.md"
      - section: "Records"
        contents: "records/*.md"
      - section: "Texts"
        contents: "texts/*.md"
  page-footer:
    right: "[Imprint](/imprint.html)"

format:
  html:
    theme: cosmo
    toc: true
    toc-location: right
    code-fold: true
    filters:
QUARTOEOF

        # 3. Install every vk-managed filter/shortcode (shared, static -
        # not regenerated per-vault from a heredoc, so every vault always
        # gets the exact same, already-tested set - see sync_vk_filters()
        # for how the plain-filter/shortcode-extension distinction works
        # and how it back-fills format.html.filters: above), and seed a
        # per-vault Imprint stub (only written once, at vault creation -
        # never overwritten by vk afterwards, since it's meant to be
        # hand-edited).
        sync_vk_filters "$VAULT_PATH"
        cp "$IMPRINT_MD_SRC" "$VAULT_PATH/imprint.md"

        (cd "$VAULT_PATH" && "$GIT_BIN" init -q && echo "_site/" > .gitignore && "$GIT_BIN" add . && "$GIT_BIN" commit -q -m "Init vault")
        echo "✓ Vault initialized successfully at $VAULT_PATH"
        ;;

    note)
        VAULT_NAME=$(get_vault "${2:-}")
        cd_vault "$VAULT_NAME"

        ACTION=$("$GUM_BIN" choose "Create Note" "Edit Note" "Delete Note" "Fuzzy Search Text")

        case "$ACTION" in
            "Create Note")
                prompt_category_type
                TITLE=$("$GUM_BIN" input --placeholder "Note filename (e.g., compiler_optimizations)...")
                if [ -z "$TITLE" ]; then exit 1; fi
                write_note "$CAT" "$TYPE" "$TITLE" <<< $'# '"${TITLE//_/ }"$'\n\n'
                "$HX_BIN" "$NOTE_FILE"
                ;;

            "Edit Note")
                FILE=$(find . -name "*.md" ! -path "./_site/*" | "$GUM_BIN" filter --placeholder "Select note to edit...")
                if [ -z "$FILE" ]; then exit 1; fi
                "$HX_BIN" "$FILE"
                ;;

            "Delete Note")
                FILE=$(find . -name "*.md" ! -path "./_site/*" | "$GUM_BIN" filter --placeholder "Select note to DESTROY...")
                if [ -z "$FILE" ]; then exit 1; fi
                "$GUM_BIN" confirm "Are you sure you want to permanently delete $FILE?" && rm "$FILE" && echo "Deleted."
                ;;

            "Fuzzy Search Text")
                search_content "." "Search $VAULT_NAME..."
                ;;
        esac
        ;;

    import)
        VAULT_NAME=$(get_vault "${2:-}")
        cd_vault "$VAULT_NAME"

        MODE=$("$GUM_BIN" choose "File" "Code" "Clipboard" "Bibentry" "Link" "Page")

        case "$MODE" in
            "File")
                require_uvx
                SRC_PATH=$("$GUM_BIN" file --header "Select file to import...")
                if [ -z "$SRC_PATH" ]; then exit 1; fi
                BODY=$(uvx markitdown "$SRC_PATH")
                DEFAULT_TITLE=$(basename "$SRC_PATH")
                DEFAULT_TITLE="${DEFAULT_TITLE%.*}"
                TITLE=$("$GUM_BIN" input --placeholder "Note filename..." --value "$DEFAULT_TITLE")
                if [ -z "$TITLE" ]; then exit 1; fi
                prompt_category_type
                write_note "$CAT" "$TYPE" "$TITLE" <<< "# ${TITLE//_/ }

$BODY"
                "$HX_BIN" "$NOTE_FILE"
                ;;

            "Code")
                SRC_PATH="${3:-}"
                if [ -n "$SRC_PATH" ] && [ -f "$SRC_PATH" ]; then
                    CODE=$(cat "$SRC_PATH")
                    # Infer the fenced-block language from the file
                    # extension - falls back to no language tag (a
                    # plain ``` block still renders fine, just without
                    # syntax highlighting) for anything unrecognized.
                    case "${SRC_PATH##*.}" in
                        py) LANG=python ;; js) LANG=javascript ;; ts) LANG=typescript ;;
                        sh|bash) LANG=bash ;; nix) LANG=nix ;; rs) LANG=rust ;; go) LANG=go ;;
                        c) LANG=c ;; cpp|cc|cxx) LANG=cpp ;; java) LANG=java ;; rb) LANG=ruby ;;
                        yml|yaml) LANG=yaml ;; json) LANG=json ;; toml) LANG=toml ;;
                        md) LANG=markdown ;; sql) LANG=sql ;; lua) LANG=lua ;;
                        *) LANG="" ;;
                    esac
                    DEFAULT_TITLE=$(basename "$SRC_PATH")
                    DEFAULT_TITLE="${DEFAULT_TITLE%.*}"
                else
                    CODE=$("$GUM_BIN" write --header "Paste or type code to import...")
                    if [ -z "$CODE" ]; then exit 1; fi
                    LANG=$("$GUM_BIN" input --placeholder "Language (for syntax highlighting, optional)...")
                    DEFAULT_TITLE=""
                fi
                TITLE=$("$GUM_BIN" input --placeholder "Note filename..." --value "$DEFAULT_TITLE")
                if [ -z "$TITLE" ]; then exit 1; fi
                prompt_category_type
                write_note "$CAT" "$TYPE" "$TITLE" <<< "# ${TITLE//_/ }

\`\`\`$LANG
$CODE
\`\`\`"
                "$HX_BIN" "$NOTE_FILE"
                ;;

            "Clipboard")
                if [ "${#CLIP_PASTE_CMD[@]}" -eq 0 ]; then
                    echo "Error: no clipboard backend configured (config.core.platformBackend is null - CLI-only host, no compositor/WSL). 'vk import clipboard' needs a graphical backend." >&2
                    exit 1
                fi
                CONTENT=$("${CLIP_PASTE_CMD[@]}")
                if [ -z "$CONTENT" ]; then
                    echo "Error: clipboard is empty." >&2
                    exit 1
                fi
                TITLE=$("$GUM_BIN" input --placeholder "Note filename...")
                if [ -z "$TITLE" ]; then exit 1; fi
                prompt_category_type
                write_note "$CAT" "$TYPE" "$TITLE" <<< "# ${TITLE//_/ }

\`\`\`
$CONTENT
\`\`\`"
                "$HX_BIN" "$NOTE_FILE"
                ;;

            "Bibentry")
                ENTRY=$("$GUM_BIN" write --header "Paste BibTeX entry...")
                if [ -z "$ENTRY" ]; then exit 1; fi
                # Citekey (e.g. "@article{smith2024foo," -> "smith2024foo")
                # is only used as the default note filename here - the
                # formatted citation itself is built field-by-field, see
                # format_bib_entry().
                CITEKEY=$(echo "$ENTRY" | "$RG_BIN" -o -N '^@\w+\{([^,]+),' -r '$1' | head -1)
                FORMATTED=$(format_bib_entry "$ENTRY")
                TITLE=$("$GUM_BIN" input --placeholder "Note filename..." --value "$CITEKEY")
                if [ -z "$TITLE" ]; then exit 1; fi
                prompt_category_type
                write_note "$CAT" "$TYPE" "$TITLE" <<< "# ${TITLE//_/ }

$FORMATTED

\`\`\`bibtex
$ENTRY
\`\`\`"
                "$HX_BIN" "$NOTE_FILE"
                ;;

            "Link"|"Page")
                URL=$("$GUM_BIN" input --placeholder "Enter URL...")
                if [ -z "$URL" ]; then exit 1; fi
                TMP_HTML=$(mktemp)
                "$CURL_BIN" -sL -A "Mozilla/5.0" "$URL" -o "$TMP_HTML" || true

                META_TITLE=$(extract_meta_tag "$TMP_HTML" "og:title")
                if [ -z "$META_TITLE" ]; then
                    META_TITLE=$("$RG_BIN" -o -N '<title[^>]*>([^<]*)</title>' -r '$1' "$TMP_HTML" 2>/dev/null | head -1) || true
                fi
                META_DESC=$(extract_meta_tag "$TMP_HTML" "og:description")
                if [ -z "$META_DESC" ]; then
                    META_DESC=$(extract_meta_tag "$TMP_HTML" "description")
                fi
                META_SITE=$(extract_meta_tag "$TMP_HTML" "og:site_name")
                META_AUTHOR=$(extract_meta_tag "$TMP_HTML" "author")
                META_PUBLISHED=$(extract_meta_tag "$TMP_HTML" "article:published_time")
                rm -f "$TMP_HTML"

                DEFAULT_TITLE="${META_TITLE:-$URL}"
                TITLE=$("$GUM_BIN" input --placeholder "Note filename..." --value "$DEFAULT_TITLE")
                if [ -z "$TITLE" ]; then exit 1; fi
                prompt_category_type

                META_BLOCK="## Metadata

- **Source**: <$URL>"
                [ -n "$META_SITE" ] && META_BLOCK="$META_BLOCK
- **Site**: $META_SITE"
                [ -n "$META_AUTHOR" ] && META_BLOCK="$META_BLOCK
- **Author**: $META_AUTHOR"
                [ -n "$META_PUBLISHED" ] && META_BLOCK="$META_BLOCK
- **Published**: $META_PUBLISHED"
                [ -n "$META_DESC" ] && META_BLOCK="$META_BLOCK
- **Description**: $META_DESC"

                if [ "$MODE" = "Page" ]; then
                    require_uvx
                    PAGE_BODY=$(uvx markitdown "$URL")
                    write_note "$CAT" "$TYPE" "$TITLE" <<< "# ${TITLE//_/ }

$META_BLOCK

## Content

$PAGE_BODY"
                else
                    write_note "$CAT" "$TYPE" "$TITLE" <<< "# ${TITLE//_/ }

$META_BLOCK"
                fi
                "$HX_BIN" "$NOTE_FILE"
                ;;
        esac
        ;;

    search)
        TARGET="${2:-}"
        if [ -z "$TARGET" ]; then
            VAULTS_LIST=$(list_vaults)
            if [ -n "$VAULTS_LIST" ]; then
                TARGET=$( { echo "All vaults"; echo "$VAULTS_LIST"; } | "$GUM_BIN" choose --header "Search scope:")
            else
                echo "No vaults found." >&2
                exit 1
            fi
        fi
        if [ "$TARGET" = "All vaults" ] || [ "$TARGET" = "all" ] || [ "$TARGET" = "--all" ]; then
            search_content "$VAULTS_DIR" "Search all vaults..."
        else
            cd_vault "$TARGET"
            search_content "." "Search $TARGET..."
        fi
        ;;

    rename)
        OLD_NAME=$(get_vault "${2:-}")
        OLD_PATH="$VAULTS_DIR/$OLD_NAME"
        if [ ! -d "$OLD_PATH" ]; then
            echo "Error: vault '$OLD_NAME' does not exist at $OLD_PATH." >&2
            exit 1
        fi
        NEW_NAME="${3:-}"
        if [ -z "$NEW_NAME" ]; then
            NEW_NAME=$("$GUM_BIN" input --placeholder "New name for '$OLD_NAME'...")
        fi
        if [ -z "$NEW_NAME" ]; then exit 1; fi
        NEW_PATH="$VAULTS_DIR/$NEW_NAME"
        if [ -d "$NEW_PATH" ]; then
            echo "Error: a vault named '$NEW_NAME' already exists." >&2
            exit 1
        fi

        # A vault is identified purely by its directory name at every
        # call site (get_vault/cd_vault/watch/build/serve-all all resolve
        # $VAULTS_DIR/<dirname> at runtime, no separate registry file) -
        # so a plain directory move is sufficient to make vk itself
        # recognize the vault under its new name, .git history included.
        mv "$OLD_PATH" "$NEW_PATH"

        # index.md's title and _quarto.yml's website.title are baked in
        # verbatim at 'vk new' time and never re-derived afterwards - a
        # bare mv would otherwise leave the rendered site/index still
        # showing the old name.
        if [ -f "$NEW_PATH/index.md" ]; then
            sed -i "s/^title: \".*\"/title: \"$NEW_NAME\"/" "$NEW_PATH/index.md"
        fi
        if [ -f "$NEW_PATH/_quarto.yml" ]; then
            sed -i "s/^  title: \".*\"/  title: \"$NEW_NAME\"/" "$NEW_PATH/_quarto.yml"
        fi

        if [ -d "$NEW_PATH/.git" ]; then
            (cd "$NEW_PATH" && "$GIT_BIN" add -A && "$GIT_BIN" commit -q -m "Rename vault: $OLD_NAME -> $NEW_NAME" --allow-empty)
        fi
        echo "✓ Renamed vault '$OLD_NAME' to '$NEW_NAME' at $NEW_PATH"
        ;;

    watch)
        shift
        parse_serve_flags "$@"
        VAULT_NAME=$(get_vault "${POSITIONAL[0]:-}")
        cd_vault "$VAULT_NAME"
        build_dufs_args
        echo "👀 Starting hot-reloading Quarto pipeline..."
        "$QUARTO_BIN" preview --no-serve --no-browser &
        Q_PID=$!
        # Bind the background Quarto watcher to this shell's lifetime -
        # prevents orphaned processes holding the preview port across
        # subsequent 'vk watch' restarts.
        trap 'kill "$Q_PID" 2>/dev/null || true' EXIT
        echo "⚡ Dufs web interface running at $(dufs_url)"
        "$DUFS_BIN" _site --render-index -A "${DUFS_ARGS[@]}"
        ;;

    build)
        shift
        parse_serve_flags "$@"
        VAULT_NAME=$(get_vault "${POSITIONAL[0]:-}")
        cd_vault "$VAULT_NAME"
        if [ "${POSITIONAL[1]:-}" = "file" ] && [ -n "${POSITIONAL[2]:-}" ]; then
            "$QUARTO_BIN" render "${POSITIONAL[2]}"
        else
            "$QUARTO_BIN" render
        fi
        ;;

    serve-all)
        shift
        parse_serve_flags "$@"
        build_dufs_args

        serve_all_rebuild
        echo "👀 Watching $VAULTS_DIR for global page/asset changes and newly built vaults..."
        (
            while true; do
                sleep 3
                serve_all_rebuild 1
            done
        ) &
        REBUILD_LOOP_PID=$!
        trap 'kill "$REBUILD_LOOP_PID" 2>/dev/null || true' EXIT

        echo "⚡ Active multi-vault core instance running at $(dufs_url)"
        echo "Access paths via: $(dufs_url)/<vault-name>/"
        "$DUFS_BIN" "$VAULTS_DIR/_site" --render-index --allow-symlink -A "${DUFS_ARGS[@]}"
        ;;

    *)
        if [ -n "${1:-}" ]; then
            echo "Unknown command: $1" >&2
            print_usage >&2
            exit 1
        fi
        echo "Interactive CLI Management Hub"
        ACTION=$("$GUM_BIN" choose "new (Create Vault)" "note (CRUD Operations)" "search (Find Across Vaults)" "rename (Rename Vault)" "watch (Live Edit Preview)" "serve-all (Host Hub)")
        CMD=$(echo "$ACTION" | cut -d' ' -f1)
        exec "$0" "$CMD"
        ;;
esac
