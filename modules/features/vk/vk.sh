#!/usr/bin/env bash
# vk - Terminal-first wiki & Zettelkasten engine.
#
# The Nix-level preamble (modules/features/vk.nix) resolves every external
# binary this script needs into the *_BIN variables below, and sets
# VAULTS_DIR/IMPRINT_MD_SRC/VK_TASKWARRIOR_LUA/VK_TASKWARRIOR_PREPROCESS
# before sourcing this file - keeping this static, shellcheck-able body
# free of any Nix syntax (mirrors the viewer.nix/clipboard.nix pattern:
# small Nix preamble + real shell file).
#
# Rendering architecture (migrated 2026-08 from Quarto - see
# memory-bank/decisions.md): MyST (mystmd) is vk's only Markdown parser
# and site/document renderer. Pandoc is used only as a narrow,
# preprocessing-only step for `taskwarrior` directive blocks (see
# stage_vault() below and filters/taskwarrior.lua) - the rest of every
# document is untouched MyST syntax that only MyST ever sees.
set -euo pipefail

mkdir -p "$VAULTS_DIR"

# Helper: list every real vault's name, one per line, sorted
# alphabetically. A "real" vault is any $VAULTS_DIR subdirectory that
# owns its own myst.yml (written by 'vk new') - this deliberately
# excludes $VAULTS_DIR's own root-project artifacts ('vk serve-all'
# regenerates its _build/, myst.yml, index.md, imprint.md directly
# inside $VAULTS_DIR itself, none of which are vaults) from ever
# appearing in a vault picker or listing.
list_vaults() {
    local v name
    for v in "$VAULTS_DIR"/*/; do
        v="${v%/}"
        [ -f "$v/myst.yml" ] || continue
        name=$(basename "$v")
        echo "$name"
    done | sort
}

# Persisted "last vault used" - written by remember_vault()/read by
# get_vault() so the next prompt pre-selects it (Enter alone re-picks
# it, via gum choose's own --selected flag). Uses XDG_STATE_HOME rather
# than $VAULTS_DIR itself since this is vk's own UI state, not vault
# content.
VK_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/vk"
VK_LAST_VAULT_FILE="$VK_STATE_DIR/last-vault"

# Persisted "last search mode" (fuzzy|substring) - same remember/
# pre-select pattern as the vault picker above, so search_content()'s
# mode toggle only takes one keypress (Enter to keep, one arrow+Enter
# to switch) instead of having to pick a mode from scratch every time.
VK_SEARCH_MODE_FILE="$VK_STATE_DIR/search-mode"

remember_vault() {
    local name="$1"
    [ -z "$name" ] && return 0
    mkdir -p "$VK_STATE_DIR"
    printf '%s' "$name" > "$VK_LAST_VAULT_FILE"
}

last_vault() {
    [ -f "$VK_LAST_VAULT_FILE" ] && cat "$VK_LAST_VAULT_FILE"
}

# Helper: Ensure vault argument or select interactively via gum.
get_vault() {
    local name="${1:-}"
    if [ -z "$name" ]; then
        local vaults last
        vaults=$(list_vaults)
        if [ -n "$vaults" ]; then
            last=$(last_vault)
            if [ -n "$last" ] && echo "$vaults" | grep -qxF "$last"; then
                name=$(echo "$vaults" | "$GUM_BIN" choose --header "Select target vault:" --selected "$last")
            else
                name=$(echo "$vaults" | "$GUM_BIN" choose --header "Select target vault:")
            fi
        else
            name=$("$GUM_BIN" input --placeholder "No vaults found. Enter name for a new vault:")
        fi
    fi
    [ -n "$name" ] && remember_vault "$name"
    echo "$name"
}

# Helper: ensure a vault has its own main.md - the free-form, hand-edited
# landing-page content that index.md includes via MyST's native
# `{include}` directive (see 'new' and index.md's template below). Only
# ever generated when missing (never overwritten). Seeded empty:
# index.md's own front-matter "title" already renders the vault name as
# the page header, so an explicit "# $name" heading here would just
# duplicate it in the body.
ensure_main_md() {
    local path="$1"
    if [ ! -f "$path/main.md" ]; then
        : > "$path/main.md"
    fi
}

# Helper: ensure a vault has its own agent-instructions file and memory
# folder - seeded once from VK_VAULT_AGENTS_MD_SRC/never overwritten
# afterwards (same "only when missing" contract as ensure_main_md()
# above), so a user/agent is free to grow either one over time without
# vk ever clobbering it. Mirrors the global $VAULTS_DIR/AGENTS.md +
# memory-bank/ pair written in serve_all_rebuild(), but per-vault.
ensure_vault_agents_md() {
    local path="$1"
    if [ ! -f "$path/AGENTS.md" ]; then
        cp "$VK_VAULT_AGENTS_MD_SRC" "$path/AGENTS.md"
    fi
    mkdir -p "$path/memory-bank"
    if [ ! -f "$path/memory-bank/README.md" ]; then
        cat <<'MBEOF' > "$path/memory-bank/README.md"
# Memory bank

Durable, agent-relevant context for this vault - recurring themes,
in-flight projects, conventions specific here. Plain Markdown, no
frontmatter required. Never overwritten by `vk`; grow it freely.
MBEOF
    fi
}

# Helper: percent-encode the characters in a relative path/filename that
# are unsafe inside a bare (non-`<...>`-wrapped) CommonMark/MyST link
# destination - most importantly the literal space, which otherwise
# makes the whole `[Title](...)` construct parse as plain text instead
# of a link (confirmed live with note filenames like "Agentic Coding
# Tools.md"). Deliberately narrow (space only, plus '#'/'?' which would
# otherwise be misread as a fragment/query delimiter) rather than a full
# RFC 3986 encoder - vault note filenames are user-chosen but simple;
# this covers every character actually seen in practice without touching
# the '/' path separators callers rely on.
url_encode_path() {
    local s="$1"
    s="${s// /%20}"
    s="${s//#/%23}"
    s="${s//\?/%3F}"
    printf '%s' "$s"
}

# Helper: (re)generate one category's own index.md as an actual listing
# of every note inside it (title from the note's own front matter,
# falling back to the filename when a note has none), sorted
# alphabetically by that title - rather than the empty file 'vk new'
# touches into existence at vault-creation time. Writes only when the
# generated content actually differs, so an unrelated call (e.g. from
# serve-all's polling loop) doesn't spuriously bump this file's mtime
# and trigger vault_needs_build() to rebuild the vault every single
# poll even when nothing really changed. Links use plain CommonMark/MyST
# document links (no wikilink syntax - MyST doesn't support it and
# resolves relative .md links natively).
#
# Link destinations are run through url_encode_path() (below) since a
# literal space (or other CommonMark-unsafe character) in a link
# destination isn't valid Markdown syntax unless the destination is
# wrapped in `<...>` - a plain `[Title](My Note.md)` gets parsed as
# literal text rather than a link (confirmed live: notes with spaces in
# their filename, e.g. "Agentic Coding Tools.md", showed up unrendered
# in the built category listing page).
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
        # renders as the page header, so a "# $title" heading here
        # would just duplicate it.
        for f in "$dir"/*.md; do
            [ -e "$f" ] || continue
            base=$(basename "$f")
            [ "$base" = "index.md" ] && continue
            note_title=$(grep -m1 '^title:' "$f" 2>/dev/null | sed -E 's/^title:[[:space:]]*"?//; s/"?[[:space:]]*$//')
            [ -z "$note_title" ] && note_title="${base%.md}"
            printf '%s\t%s\n' "$note_title" "$base"
        done | sort | while IFS=$'\t' read -r note_title base; do
            echo "- [$note_title]($(url_encode_path "$base"))"
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

# Helper: does file $1 contain at least one MyST taskwarrior directive
# block? Cheap pre-check so stage_vault() only shells out to Python for
# files that actually need it.
file_has_taskwarrior_directive() {
    "$RG_BIN" -q '^:{3,}\{taskwarrior\}' "$1" 2>/dev/null
}

# Same cheap pre-check for the graphviz directive (see
# scripts/graphviz_preprocess.py).
file_has_graphviz_directive() {
    "$RG_BIN" -q '^:{3,}\{graphviz\}' "$1" 2>/dev/null
}

# Helper: (re)build vault $1's disposable staging tree at
# "$1/.vk-staging" - the tree MyST actually builds. Ordinary files are
# copied unchanged; any Markdown file containing a `taskwarrior`
# directive is first run through the Pandoc+Lua preprocessing step (see
# scripts/taskwarrior_preprocess.py and filters/taskwarrior.lua), which
# rewrites only those directive blocks and leaves everything else in the
# file byte-identical. MyST itself only ever sees the staged tree, so a
# full Pandoc round-trip - and any risk of it mangling MyST-only syntax
# elsewhere in a document - never happens.
#
# Every write is guarded by `cmp -s` before replacing the destination so
# an unchanged file's mtime never bumps - this both avoids spurious
# vault_needs_build() rebuilds and lets MyST's own incremental build
# cache (under .vk-staging/_build) actually help on repeat builds.
stage_vault() {
    local path="$1" staging="$1/.vk-staging"
    mkdir -p "$staging"
    local f rel dest tmp tmp2 cur changed
    while IFS= read -r -d '' f; do
        rel="${f#"$path"/}"
        dest="$staging/$rel"
        mkdir -p "$(dirname "$dest")"
        case "$rel" in
            *.md)
                # Chain both directive preprocessors (each is a no-op
                # pass-through when its directive is absent from the
                # file): taskwarrior first, then graphviz, so a note can
                # freely use either or both. `changed` tracks whether any
                # stage actually ran, so an unmodified file still takes
                # the cheap "copy only if different" path below instead
                # of always writing a temp file.
                cur="$f"
                changed=0
                if file_has_taskwarrior_directive "$f"; then
                    tmp="$dest.vk-tmp"
                    "$PYTHON_BIN" "$VK_TASKWARRIOR_PREPROCESS" "$cur" "$tmp" \
                        --pandoc "$PANDOC_BIN" --lua-filter "$VK_TASKWARRIOR_LUA"
                    cur="$tmp"
                    changed=1
                fi
                if file_has_graphviz_directive "$cur"; then
                    tmp2="$dest.vk-tmp2"
                    mkdir -p "$staging/assets"
                    "$PYTHON_BIN" "$VK_GRAPHVIZ_PREPROCESS" "$cur" "$tmp2" \
                        --staging-assets-dir "$staging/assets" \
                        --doc-rel-dir "$(dirname "$rel")" \
                        --dot "$GRAPHVIZ_DOT_BIN" --neato "$GRAPHVIZ_NEATO_BIN" \
                        --fdp "$GRAPHVIZ_FDP_BIN" --sfdp "$GRAPHVIZ_SFDP_BIN" \
                        --circo "$GRAPHVIZ_CIRCO_BIN" --twopi "$GRAPHVIZ_TWOPI_BIN"
                    [ "$cur" = "$dest.vk-tmp" ] && rm -f "$dest.vk-tmp"
                    mv "$tmp2" "$dest.vk-tmp"
                    cur="$dest.vk-tmp"
                    changed=1
                fi
                if [ "$changed" = "1" ]; then
                    if ! cmp -s "$cur" "$dest" 2>/dev/null; then mv -f "$cur" "$dest"; else rm -f "$cur"; fi
                else
                    cmp -s "$f" "$dest" 2>/dev/null || cp "$f" "$dest"
                fi
                ;;
            *)
                cmp -s "$f" "$dest" 2>/dev/null || cp "$f" "$dest"
                ;;
        esac
    done < <(find "$path" -mindepth 1 \
        \( -path "$path/.vk-staging" -o -path "$path/.git" -o -path "$path/exports" \) -prune -o \
        -type f -print0)

    # Managed visual layer: concatenate the shared Tokyo-Night/solarpunk
    # stylesheet with an optional per-vault assets/vk-custom.css override
    # (appended after, so vault-specific rules win any selector tie)
    # into one staged stylesheet. vault_enhance.py points
    # site.options.style at this file unless the vault's own myst.yml
    # already sets its own style. Diff-guarded like every other staged
    # write, so an unchanged result never bumps this file's mtime.
    mkdir -p "$staging/assets"
    tmp="$staging/assets/vk-managed.css.vk-tmp"
    cat "$VK_THEME_CSS" > "$tmp"
    if [ -f "$path/assets/vk-custom.css" ]; then
        printf '\n' >> "$tmp"
        cat "$path/assets/vk-custom.css" >> "$tmp"
    fi
    if ! cmp -s "$tmp" "$staging/assets/vk-managed.css" 2>/dev/null; then
        mv -f "$tmp" "$staging/assets/vk-managed.css"
    else
        rm -f "$tmp"
    fi
    # Default logo/favicon: only written when the vault has no asset of
    # its own at this path (the plain-copy loop above would already have
    # staged it) - a vault-provided assets/vk-logo.svg always wins.
    if [ ! -f "$staging/assets/vk-logo.svg" ]; then
        cp "$VK_LOGO_SVG" "$staging/assets/vk-logo.svg"
    fi

    # Second staging pass: frontmatter/config analysis (see
    # vault_enhance.py's own docstring for exactly what this does today
    # and what it's the deterministic seam for later). Runs after every
    # plain/Taskwarrior-preprocessed file - and the managed CSS/logo
    # assets above - are in place so it can read the final staged tree,
    # and before myst_build() so its staged myst.yml merge (including
    # the style/logo defaults pointing at the assets just written) is
    # what MyST actually builds.
    "$PYTHON_BIN" "$VK_VAULT_ENHANCE" "$path" "$staging" \
        --managed-plugin "$VK_PLUGIN_SUBSTITUTIONS" \
        --managed-plugin "$VK_PLUGIN_COLLECT_REFERENCES"
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
    ensure_vault_agents_md "$path"
    regen_category_indexes "$path"
    cd "$path"
}

# Helper: pull dufs' own -p/--port and -b/--bind/--host flags (plus their
# --flag=value forms) out of the remaining CLI args, for 'watch' and
# 'serve-all'. Anything left over is collected into POSITIONAL[] (e.g.
# the vault name for 'watch') so flags can be given in any order, before
# or after the vault name. PORT defaults to 5050 (vk's own default, not
# dufs' built-in 5000) unless overridden; BIND defaults to 127.0.0.1
# (loopback-only) rather than dufs' own default of 0.0.0.0, which would
# otherwise expose the vault's content to the whole network by default -
# pass -b/--bind/--host explicitly (e.g. 0.0.0.0), or the -0/--public
# shorthand below, to opt back into that.
parse_serve_flags() {
    PORT="5050"
    BIND="127.0.0.1"
    SERVE=0
    ALL=0
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
            -0|--public)
                # Shorthand for -b/--bind 0.0.0.0 - opts back into
                # exposing the server on every network interface,
                # overriding the loopback-only default above.
                BIND="0.0.0.0"
                shift
                ;;
            --serve)
                # Also start a dufs server after building (single-vault:
                # serves that vault's own site; --all: serves the whole
                # multi-vault hub, same as legacy serve-all/watch-all).
                SERVE=1
                shift
                ;;
            --all)
                # Scope 'build'/'watch' to every vault (+ the Vaults-root
                # hub page) instead of a single one - no vault
                # prompt/argument in this mode.
                ALL=1
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
# substitution, since it sets a global array. BIND is always non-empty
# now (parse_serve_flags defaults it to 127.0.0.1), so --bind is always
# passed explicitly rather than relying on dufs' own (world-open) default.
build_dufs_args() {
    DUFS_ARGS=()
    if [ -n "$PORT" ]; then DUFS_ARGS+=(--port "$PORT"); fi
    if [ -n "$BIND" ]; then DUFS_ARGS+=(--bind "$BIND"); fi
}

# Helper: the URL dufs will actually be reachable at, given PORT/BIND
# (PORT defaults to 5050, BIND defaults to 127.0.0.1 - both via
# parse_serve_flags).
dufs_url() {
    echo "http://${BIND:-127.0.0.1}:${PORT:-5050}"
}

# Helper: fuzzy/substring content search over $1 (a directory - either
# "." from inside an already-cd'd vault, or $VAULTS_DIR for a global,
# cross-vault search), shared by every 'vk search' scope. Passing the
# search root straight to rg (rather than cd-ing into it) means the
# paths rg prints are always valid from the caller's cwd - required for
# the global case, which runs before any cd_vault.
#
# gum's filter widget can only pick one matching mode (fuzzy vs
# start-of-word substring) per invocation - there's no keybind to swap
# it live mid-search - so the "toggle" is a one-keypress mode picker
# shown just before the search box, pre-selected on whichever mode was
# used last time (mirrors get_vault()'s last-vault memory): Enter alone
# keeps the current mode, one arrow+Enter switches it.
search_content() {
    local root="$1"
    local placeholder="${2:-Search body content...}"
    local mode selection fuzzy_flag
    mode=$(cat "$VK_SEARCH_MODE_FILE" 2>/dev/null || echo "Fuzzy")
    mode=$("$GUM_BIN" choose --header "Search mode:" --selected "$mode" "Fuzzy" "Substring")
    [ -z "$mode" ] && exit 1
    mkdir -p "$VK_STATE_DIR"
    printf '%s' "$mode" > "$VK_SEARCH_MODE_FILE"
    if [ "$mode" = "Fuzzy" ]; then fuzzy_flag="--fuzzy"; else fuzzy_flag="--no-fuzzy"; fi
    # gum >=0.14 dropped the old --ansi flag in favor of --strip-ansi/
    # --no-strip-ansi (default: don't strip), so no flag is needed here
    # to preserve rg's --color=always highlighting.
    selection=$("$RG_BIN" --line-number --no-heading --color=always --glob '!.vk-staging/**' --glob '!exports/**' --glob '!_build/**' . "$root" | "$GUM_BIN" filter "$fuzzy_flag" --placeholder "$placeholder ($mode)")
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

# Helper: slugify $1 into a lowercase, hyphen-separated token suitable
# for a stable frontmatter `id` - keeps only [a-z0-9-], collapses runs
# of separators, and trims leading/trailing hyphens.
slugify() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | sed -E 's/-+/-/g; s/^-|-$//g'
}

# Helper: write a new note file at "$CAT/$TITLE.md" with standard
# front matter - a stable `id` (category-type-slug), `title`, `type`,
# `tags` derived from category+type, and an ISO-compatible date/datetime
# (records get a full timestamp, others just a date - see 'vk note's
# original comment on why) - and a body read from stdin. `exports:`
# is deliberately NOT added here - it stays opt-in per vk's design (see
# 'vk export' below for a way to force a PDF/Typst export without
# touching a note's frontmatter). Sets NOTE_FILE to the written path.
# Shared by 'vk note's "Create Note" action and every 'vk import' mode.
write_note() {
    local cat="$1" type="$2" title="$3"
    local file="$cat/${title%.md}.md"
    local date_stamp id_slug
    if [ "$cat" = "records" ]; then
        date_stamp=$(date -Iseconds)
    else
        date_stamp=$(date -I)
    fi
    id_slug=$(slugify "${title%.md}")
    {
        echo "---"
        echo "id: ${cat}-${type}-${id_slug}"
        echo "title: \"${title//_/ }\""
        echo "type: $type"
        echo "tags: [$cat, $type]"
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

# Helper: does vault $1 (a path) have any source file newer than its own
# staged build output, or no build at all yet? Drives serve-all's
# automatic per-vault rebuild-on-change - excludes vk's own
# generated/cache dirs (and .git) from the comparison so a stale build
# doesn't "self-trigger" a rebuild forever once one has run.
#
# $2 is the base-url the build is expected to have been produced with
# (see myst_build() below) - "" for a standalone vault served at its own
# root, or "/<vault-name>" when nested under serve-all's hub. A mismatch
# (e.g. a vault previously built standalone via 'vk build' and now being
# picked up by 'vk serve-all', or vice versa) forces a rebuild even if no
# source file changed, since the two builds' baked-in asset/route paths
# are not interchangeable - reusing the wrong one is exactly what caused
# MyST's client-side router to throw "Cannot read properties of
# undefined (reading 'handle')" when a vault built for "/" was symlinked
# and navigated to under "/<vault-name>/" (confirmed live: BASE_URL
# controls the base path MyST's Remix-based client bundle assumes it is
# served from - unset, every asset/route is absolute from "/").
#
# Also forces a rebuild when $VK_FINGERPRINT (baked in by vk.nix from the
# enhancer script/CSS/plugin-bundle store paths - see vkFingerprint
# there) no longer matches the fingerprint recorded at the vault's last
# build, so a `vk` upgrade alone (no vault source file touched) still
# picks up new staging-pipeline behavior on the next poll/build.
vault_needs_build() {
    local path="$1" want_base="${2:-}"
    local marker="$path/.vk-staging/_build/.base_url"
    local fp_marker="$path/.vk-staging/_build/.vk_fingerprint"
    [ -d "$path/.vk-staging/_build/html" ] || return 0
    if [ ! -f "$marker" ] || [ "$(cat "$marker" 2>/dev/null)" != "$want_base" ]; then
        return 0
    fi
    if [ ! -f "$fp_marker" ] || [ "$(cat "$fp_marker" 2>/dev/null)" != "$VK_FINGERPRINT" ]; then
        return 0
    fi
    find "$path" -mindepth 1 \
        \( -path "$path/.vk-staging" -o -path "$path/exports" -o -path "$path/.git" \) -prune -o \
        -type f -newer "$path/.vk-staging/_build/html" -print -quit 2>/dev/null | grep -q .
}

# Helper: run `myst build` for vault $1's staging tree with extra args
# $3... (e.g. --html, or --typst for exports). MyST always fully
# completes a non-watch build and exits on its own (verified: `myst
# build --html` with no `--watch` writes the static site and returns) -
# no special process-management is needed, unlike Quarto's old
# preview-vs-render split for this particular case.
#
# $2 is the base-url to build with - "" for a standalone build served at
# its own root (plain 'vk build'/'vk watch'), or "/<vault-name>" when
# building for serve-all's nested "/<vault-name>/" path. MyST bakes the
# base path into every emitted asset href/route at build time via the
# BASE_URL env var (there is no --base-url build flag); the two outputs
# are not interchangeable, so the chosen base-url is recorded in a
# marker file that vault_needs_build() checks to force a rebuild on
# mismatch (e.g. switching a vault between standalone use and
# serve-all). The fingerprint marker is recorded alongside it for the
# same function's staging-pipeline-version check.
myst_build() {
    local path="$1" base_url="$2"
    shift 2
    if [ -n "$base_url" ]; then
        (cd "$path/.vk-staging" && BASE_URL="$base_url" "$MYST_BIN" build --ci "$@")
    else
        (cd "$path/.vk-staging" && "$MYST_BIN" build --ci "$@")
    fi
    mkdir -p "$path/.vk-staging/_build"
    printf '%s' "$base_url" > "$path/.vk-staging/_build/.base_url"
    printf '%s' "$VK_FINGERPRINT" > "$path/.vk-staging/_build/.vk_fingerprint"
}

# Helper: (re)generate one vault's own myst.yml at $1, titled $2. Shared
# by 'new' (initial creation) and 'rename' (title needs updating after a
# rename) so the project config is only ever written from one place.
write_vault_myst_yml() {
    local vault_path="$1" title="$2"
    cat <<MYSTEOF > "$vault_path/myst.yml"
version: 1
project:
  title: "$title"
  toc:
    - file: index.md
    - title: Materials
      children:
        - pattern: materials/*.md
    - title: Records
      children:
        - pattern: records/*.md
    - title: Texts
      children:
        - pattern: texts/*.md
site:
  template: book-theme
  options:
    logo_text: "$title"
MYSTEOF
}

# Helper: (re)generate the Vaults-root itself as a small MyST project for
# 'vk serve-all' - its own myst.yml + index.md (fully re-derived every
# call) plus a build of every top-level *.md page there (imprint.md and
# any other global page the user drops in $VAULTS_DIR - e.g. about.md,
# changelog.md - are all discovered and rendered generically, not just
# imprint.md specifically). Also builds (or rebuilds, on any source-file
# change - see vault_needs_build()) every real vault automatically, then
# refreshes the per-vault _build/html symlinks - so the whole thing
# picks up *any* change (new/edited notes, brand-new never-built vaults,
# removed vaults, global pages/assets) with no manual 'vk build' step.
# Called once up front and then repeatedly from serve-all's background
# watch loop (pass quiet=1 there to suppress MyST's normally-verbose
# build log and per-vault build failures on every poll).
serve_all_rebuild() {
    local quiet="${1:-0}"
    local name bn disp f path tmp

    mkdir -p "$VAULTS_DIR/assets"
    if [ ! -f "$VAULTS_DIR/imprint.md" ]; then
        cp "$IMPRINT_MD_SRC" "$VAULTS_DIR/imprint.md"
    fi

    # Agent-facing docs for the whole Vaults collection: unlike
    # imprint.md (user-editable, seeded once), this one is fully
    # managed - always kept in sync with VK_AGENTS_MD_SRC, the same way
    # vk-managed.css is below - so an `apply-dots` upgrade that changes
    # vk's own conventions doesn't leave a stale copy behind. Diff-
    # guarded so an unchanged result never bumps its own mtime.
    tmp="$VAULTS_DIR/AGENTS.md.vk-tmp"
    cat "$VK_AGENTS_MD_SRC" > "$tmp"
    if ! cmp -s "$tmp" "$VAULTS_DIR/AGENTS.md" 2>/dev/null; then
        mv -f "$tmp" "$VAULTS_DIR/AGENTS.md"
    else
        rm -f "$tmp"
    fi
    mkdir -p "$VAULTS_DIR/memory-bank"
    if [ ! -f "$VAULTS_DIR/memory-bank/README.md" ]; then
        cat <<'MBEOF' > "$VAULTS_DIR/memory-bank/README.md"
# Memory bank

Durable, agent-relevant context spanning more than one vault (or about
the vault collection as a whole). Plain Markdown, no frontmatter
required. Never overwritten by `vk`; grow it freely. Vault-specific
context belongs in that vault's own `memory-bank/` instead.
MBEOF
    fi

    # Same shared visual layer as every vault (see stage_vault()) -
    # written directly here rather than through vault_enhance.py's merge
    # since the hub's myst.yml is fully re-derived from scratch below on
    # every call, not authored/preserved. Diff-guarded so an unchanged
    # stylesheet never bumps its own mtime.
    tmp="$VAULTS_DIR/assets/vk-managed.css.vk-tmp"
    cat "$VK_THEME_CSS" > "$tmp"
    if ! cmp -s "$tmp" "$VAULTS_DIR/assets/vk-managed.css" 2>/dev/null; then
        mv -f "$tmp" "$VAULTS_DIR/assets/vk-managed.css"
    else
        rm -f "$tmp"
    fi
    if [ ! -f "$VAULTS_DIR/assets/vk-logo.svg" ]; then
        cp "$VK_LOGO_SVG" "$VAULTS_DIR/assets/vk-logo.svg"
    fi

    # Real vaults: subdirectories owning their own myst.yml.
    # list_vaults() is already sorted alphabetically, so splitting it
    # below preserves that order without a separate sort pass.
    local all_vaults=()
    while IFS= read -r name; do
        [ -n "$name" ] && all_vaults+=("$name")
    done < <(list_vaults)

    # Every top-level *.md file except the generated index.md and the
    # managed AGENTS.md (agent-facing, not meant for the human-facing
    # hub nav) is a "global page" - built and linked from the root
    # index, in addition to imprint.md's dedicated footer link. Sorted
    # alphabetically like every other vk listing.
    GLOBAL_PAGES=()
    for f in "$VAULTS_DIR"/*.md; do
        [ -e "$f" ] || continue
        bn=$(basename "$f")
        [ "$bn" = "index.md" ] && continue
        [ "$bn" = "AGENTS.md" ] && continue
        GLOBAL_PAGES+=("$bn")
    done
    if [ "${#GLOBAL_PAGES[@]}" -gt 0 ]; then
        mapfile -t GLOBAL_PAGES < <(printf '%s\n' "${GLOBAL_PAGES[@]}" | sort)
    fi

    # toc: index.md first, then every discovered global page (imprint.md
    # included generically, no special-casing beyond excluding index.md
    # itself above).
    {
        echo 'version: 1'
        echo 'project:'
        echo '  title: "Vaults"'
        echo '  toc:'
        echo '    - file: index.md'
        for bn in "${GLOBAL_PAGES[@]}"; do
            echo "    - file: $bn"
        done
        echo 'site:'
        echo '  template: book-theme'
        echo '  options:'
        echo '    logo_text: "Vaults"'
        echo '    logo: assets/vk-logo.svg'
        echo '    favicon: assets/vk-logo.svg'
        echo '    style: assets/vk-managed.css'
        echo '    folders: true'
    } > "$VAULTS_DIR/myst.yml"

    # Build (or rebuild, if any of its own source files changed since
    # its last build) every real vault automatically. This is the step
    # that makes serve-all's background loop pick up *any* change rather
    # than just newly-appearing global pages/assets at the Vaults root -
    # a note edit, a brand-new never-built vault, etc. all get
    # (re)built on the next poll with no manual 'vk build' step.
    for name in "${all_vaults[@]}"; do
        path="$VAULTS_DIR/$name"
        # Backfill AGENTS.md/memory-bank for any vault that predates this
        # feature (or was never opened via cd_vault/'vk new') - a no-op
        # once already present, same "only when missing" contract as
        # ensure_main_md().
        ensure_vault_agents_md "$path"
        # Regenerate category listings first (a note added/removed since
        # the last poll counts as "a source file changed" too) - only
        # actually rewrites index.md when content differs, so this alone
        # never spuriously triggers vault_needs_build() below.
        regen_category_indexes "$path"
        if vault_needs_build "$path" "/$name"; then
            stage_vault "$path"
            if [ "$quiet" = "1" ]; then
                myst_build "$path" "/$name" --html >/dev/null 2>&1 || true
            else
                myst_build "$path" "/$name" --html >/dev/null ||
                    echo "⚠ Failed to build vault '$name' - see 'vk build $name' for details" >&2
            fi
        fi
    done

    BUILT=()
    UNBUILT=()
    for name in "${all_vaults[@]}"; do
        if [ -d "$VAULTS_DIR/$name/.vk-staging/_build/html" ]; then
            BUILT+=("$name")
        else
            UNBUILT+=("$name")
        fi
    done

    {
        echo '---'
        echo 'title: "Vaults"'
        echo '---'
        echo
        # No body heading here - front matter's "title" above already
        # renders as the page header.
        for name in "${BUILT[@]}"; do
            echo "- [$name](/$(url_encode_path "$name")/)"
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
                echo "- [$disp](/$(url_encode_path "${bn%.md}")/)"
            done
        fi
    } > "$VAULTS_DIR/index.md"

    if [ "$quiet" = "1" ]; then
        (cd "$VAULTS_DIR" && "$MYST_BIN" build --ci --html >/dev/null 2>&1) || true
    else
        (cd "$VAULTS_DIR" && "$MYST_BIN" build --ci --html >/dev/null)
    fi

    # Symlink each built vault's staged _build/html into the just-built
    # root _build/html, named after the vault itself (so "/<vault-name>/"
    # serves it directly, no extra path segment needed). This runs every
    # ~1s from watch-all's poll loop while dufs is concurrently serving
    # requests, so it must never leave a name momentarily missing: swap
    # each symlink in with "create under a temp name, then mv onto the
    # real name" (mv is an atomic rename on the same filesystem), rather
    # than deleting every existing symlink up front and recreating them
    # one by one - the latter left a real window (previously hit in
    # practice) where dufs saw the target path as nonexistent and served
    # its own "folder will be created when a file is uploaded" page
    # instead of a 404 or the real vault, for any request during that
    # window. Stale symlinks (a vault renamed/removed since the last
    # rebuild) are still dropped, but only ones NOT in this rebuild's
    # vault set, and only after every current vault's symlink is already
    # back in place.
    mkdir -p "$VAULTS_DIR/_build/html"
    for name in "${BUILT[@]}"; do
        ln -sfn "$VAULTS_DIR/$name/.vk-staging/_build/html" \
            "$VAULTS_DIR/_build/html/$name.vk-tmp"
        mv -Tf "$VAULTS_DIR/_build/html/$name.vk-tmp" \
            "$VAULTS_DIR/_build/html/$name"
    done
    while IFS= read -r -d '' f; do
        bn=$(basename "$f")
        if ! printf '%s\n' "${BUILT[@]}" | grep -qxF "$bn"; then
            rm -f "$f"
        fi
    done < <(find "$VAULTS_DIR/_build/html" -maxdepth 1 -type l -print0)

    if [ "$quiet" != "1" ] && [ "${#UNBUILT[@]}" -gt 0 ]; then
        echo "⚠ Failed to build (see 'vk build <vault>'): ${UNBUILT[*]}" >&2
    fi
}

print_usage() {
    cat <<USAGEEOF
vk - Terminal-first wiki & Zettelkasten engine

Usage:
  vk new                                    Create a new vault (interactive)
  vk note [vault]                           Create/edit/rename/delete notes (interactive)
  vk import [vault]                         Import content into a note: File/Code/Clipboard/
                                             Bibentry/Link/Page (interactive)
  vk search [vault|all]                     Fuzzy/substring-search one vault, or every vault
                                             at once - prompts for scope if omitted, and for a
                                             search mode (remembers your last pick; Enter alone
                                             keeps it)
  vk rename [old] [new]                     Rename a vault (dir + baked-in title strings)
  vk build [vault] [--serve] [--all] [-p|--port PORT] [-b|--bind ADDR] [-0|--public]
                                             Build a static HTML site with MyST (one vault, or
                                             every vault + the Vaults-root hub with --all).
                                             --serve also starts a dufs server on it afterwards.
  vk watch [vault] [--serve] [--all] [-p|--port PORT] [-b|--bind ADDR] [-0|--public]
                                             Like build, but keeps rebuilding on every source
                                             change until Ctrl+C. --serve additionally starts a
                                             live-reloading server (single-vault: MyST's own dev
                                             server; --all: dufs, polling-refreshed).
  vk watch-all [-p|--port PORT] [-b|--bind ADDR] [-0|--public]
                                             Sugar for 'vk watch --all --serve'
  vk serve-all [-p|--port PORT] [-b|--bind ADDR] [-0|--public]
                                             Sugar for 'vk build --all --serve' (one-shot build,
                                             no watch loop - use watch-all for that)
  vk export [vault] [file] [--format pdf|typst]
                                             Export one note (or the whole vault's exports:
                                             frontmatter) to a PDF or Typst bundle
  vk check [vault|all] [--external]         Validate a vault (or every vault): strict MyST build
                                             + static checks (frontmatter, links, assets,
                                             directives, Graphviz DOT). --external also checks
                                             external links resolve (slower, needs network)
  vk help | -h | --help                     Show this message

[vault] may be omitted anywhere it's accepted - vk will prompt via gum,
pre-selecting whichever vault you last used (across any command) so
Enter alone re-picks it. -p/--port and -b/--bind (aliases: --host) are
passed straight through to dufs; both may also be given as
--port=VALUE/--bind=VALUE, in any order, before or after the vault name.
Left unset, vk defaults to port 5050, bind 127.0.0.1 (loopback-only).
Pass -0/--public as a quick shorthand for -b/--bind 0.0.0.0, to expose it
on every network interface instead.
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

        mkdir -p "$VAULT_PATH"/{texts,materials,records,assets}
        ensure_main_md "$VAULT_PATH"
        ensure_vault_agents_md "$VAULT_PATH"
        touch "$VAULT_PATH/references.bib"

        # 1. Generate Base Index Configuration (categories listed
        # alphabetically, like every other listing in vk). The landing
        # page starts with main.md's hand-edited content (included live
        # via MyST's native {include} directive, so later edits to
        # main.md show up without regenerating index.md), followed by
        # the one-link-per-category list (plain MyST/CommonMark links,
        # not wikilinks - MyST doesn't support that syntax).
        cat <<NOTEEOF > "$VAULT_PATH/index.md"
---
title: "$VAULT_NAME"
---

:::{include} main.md
:::

- [Materials](materials/index.md)
- [Records](records/index.md)
- [Texts](texts/index.md)
NOTEEOF
        touch "$VAULT_PATH/texts/index.md" "$VAULT_PATH/materials/index.md" "$VAULT_PATH/records/index.md"

        # 2. Generate MyST project config (toc sections alphabetical
        # too, shared with 'rename' via write_vault_myst_yml()).
        write_vault_myst_yml "$VAULT_PATH" "$VAULT_NAME"

        # 3. Seed a per-vault Imprint stub (only written once, at vault
        # creation - never overwritten by vk afterwards, since it's
        # meant to be hand-edited).
        cp "$IMPRINT_MD_SRC" "$VAULT_PATH/imprint.md"

        cat <<GITIGNOREEOF > "$VAULT_PATH/.gitignore"
.vk-staging/
exports/
GITIGNOREEOF

        (cd "$VAULT_PATH" && "$GIT_BIN" init -q && "$GIT_BIN" add . && "$GIT_BIN" commit -q -m "Init vault")
        echo "✓ Vault initialized successfully at $VAULT_PATH"
        ;;

    note)
        VAULT_NAME=$(get_vault "${2:-}")
        cd_vault "$VAULT_NAME"

        ACTION=$("$GUM_BIN" choose "Create Note" "Edit Note" "Rename/Move File" "Delete Note")

        case "$ACTION" in
            "Create Note")
                prompt_category_type
                TITLE=$("$GUM_BIN" input --placeholder "Note filename (e.g., compiler_optimizations)...")
                if [ -z "$TITLE" ]; then exit 1; fi
                write_note "$CAT" "$TYPE" "$TITLE" <<< $'# '"${TITLE//_/ }"$'\n\n'
                "$HX_BIN" "$NOTE_FILE"
                ;;

            "Edit Note")
                FILE=$(find . -name "*.md" ! -path "./.vk-staging/*" | "$GUM_BIN" filter --placeholder "Select note to edit...")
                if [ -z "$FILE" ]; then exit 1; fi
                "$HX_BIN" "$FILE"
                ;;

            "Delete Note")
                FILE=$(find . -name "*.md" ! -path "./.vk-staging/*" | "$GUM_BIN" filter --placeholder "Select note to DESTROY...")
                if [ -z "$FILE" ]; then exit 1; fi
                "$GUM_BIN" confirm "Are you sure you want to permanently delete $FILE?" && rm "$FILE" && echo "Deleted."
                ;;

            "Rename/Move File")
                # Conceptually a plain file move: for a note (.md),
                # preserves the stable id (added as an alias on the
                # note itself); for any other file (an asset - image,
                # PDF, ...) just moves it. Either way, exact Markdown/
                # image/{doc} references to it are rewritten across
                # this vault *and* any sibling vaults under the same
                # $VAULTS_DIR - see scripts/note_rename.py's own
                # docstring for exactly what is (and isn't) rewritten.
                FILE=$(find . \( -name "*.md" -o -path "./assets/*" \) ! -path "./.vk-staging/*" -type f | "$GUM_BIN" filter --placeholder "Select file to rename/move...")
                if [ -z "$FILE" ]; then exit 1; fi
                OLD_REL="${FILE#./}"
                NEW_REL=$("$GUM_BIN" input --placeholder "New path (relative to vault root, e.g. materials/new-name.md)..." --value "$OLD_REL")
                if [ -z "$NEW_REL" ] || [ "$NEW_REL" = "$OLD_REL" ]; then exit 1; fi
                "$PYTHON_BIN" "$VK_NOTE_RENAME" "$PWD" "$OLD_REL" "$NEW_REL"
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
                # both keys references.bib (so MyST/pandoc can resolve
                # native `[@citekey]` citations) and is used as the
                # default note filename.
                CITEKEY=$(echo "$ENTRY" | "$RG_BIN" -o -N '^@\w+\{([^,]+),' -r '$1' | head -1)
                if [ -z "$CITEKEY" ]; then
                    echo "Error: could not parse a citation key from the pasted BibTeX entry (expected '@type{citekey, ...}')." >&2
                    exit 1
                fi
                if [ -f "references.bib" ] && "$RG_BIN" -q -N "^@\w+\{$(printf '%s' "$CITEKEY" | sed 's/[.[\*^$/]/\\&/g'),\s*\$" "references.bib"; then
                    echo "Error: citation key '$CITEKEY' already exists in references.bib - use a different key or edit the existing entry directly." >&2
                    exit 1
                fi
                # Append (creating references.bib if this is the first
                # entry - older vaults created before 'vk new' started
                # seeding an empty one won't have it yet).
                {
                    [ -s "references.bib" ] && printf '\n'
                    printf '%s\n' "$ENTRY"
                } >> "references.bib"
                TITLE=$("$GUM_BIN" input --placeholder "Note filename..." --value "$CITEKEY")
                if [ -z "$TITLE" ]; then exit 1; fi
                prompt_category_type
                write_note "$CAT" "$TYPE" "$TITLE" <<< "# ${TITLE//_/ }

[@$CITEKEY]

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

        # index.md's title and myst.yml's project.title/site.options.
        # logo_text are baked in verbatim at 'vk new' time and never
        # re-derived afterwards - a bare mv would otherwise leave the
        # built site/index still showing the old name.
        if [ -f "$NEW_PATH/index.md" ]; then
            sed -i "s/^title: \".*\"/title: \"$NEW_NAME\"/" "$NEW_PATH/index.md"
        fi
        if [ -f "$NEW_PATH/myst.yml" ]; then
            write_vault_myst_yml "$NEW_PATH" "$NEW_NAME"
        fi

        if [ -d "$NEW_PATH/.git" ]; then
            (cd "$NEW_PATH" && "$GIT_BIN" add -A && "$GIT_BIN" commit -q -m "Rename vault: $OLD_NAME -> $NEW_NAME" --allow-empty)
        fi
        echo "✓ Renamed vault '$OLD_NAME' to '$NEW_NAME' at $NEW_PATH"
        ;;

    watch)
        shift
        parse_serve_flags "$@"

        if [ "$ALL" = "1" ]; then
            if [ "$SERVE" = "1" ]; then
                # watch-all (full combo): build+watch+serve every vault
                # at once - real watching (poll-based, same mechanism as
                # legacy serve-all) instead of a one-shot build.
                build_dufs_args
                serve_all_rebuild 0
                echo "👀 Watching $VAULTS_DIR for changes across every vault..."
                (
                    while true; do
                        sleep 1
                        serve_all_rebuild 1
                    done
                ) &
                REBUILD_LOOP_PID=$!
                trap 'kill "$REBUILD_LOOP_PID" 2>/dev/null || true' EXIT
                echo "⚡ Watching+serving all vaults at $(dufs_url)"
                echo "Access paths via: $(dufs_url)/<vault-name>/"
                "$DUFS_BIN" "$VAULTS_DIR/_build/html" --render-index --allow-symlink -A "${DUFS_ARGS[@]}"
            else
                # build+watch, every vault, no server.
                echo "👀 Watching $VAULTS_DIR for changes across every vault (no server - Ctrl+C to stop)..."
                while true; do
                    serve_all_rebuild 1
                    sleep 1
                done
            fi
            exit 0
        fi

        VAULT_NAME=$(get_vault "${POSITIONAL[0]:-}")
        cd_vault "$VAULT_NAME"
        stage_vault "$PWD"

        if [ "$SERVE" != "1" ]; then
            # build+watch, single vault, no server - just keep the
            # staging tree + static build up to date on every change.
            echo "👀 Watching $VAULT_NAME for changes (no server - Ctrl+C to stop)..."
            while true; do
                stage_vault "$PWD"
                myst_build "$PWD" "" --html >/dev/null 2>&1 || echo "⚠ Build failed - see 'vk build $VAULT_NAME' for details" >&2
                sleep 1
            done
            exit 0
        fi

        # `myst build --html --watch` does NOT actually watch/rebuild on
        # change (MyST itself prints "Site content will not be watched
        # and updated; use 'myst start' instead" - confirmed live) - so
        # watch mode uses MyST's own dev server instead of dufs. That
        # server needs two ports (an app server the browser talks to,
        # plus an internal content server) to get real live-reload;
        # `--headless` (content-server only) serves stale content after
        # an edit even though the rebuild itself does happen on disk -
        # confirmed live, not used here. The content server just needs
        # *a* free port of its own, never exposed/documented to the
        # user, so PORT+1 is fine.
        #
        # `HOST` (not a CLI flag) is what actually controls the bind
        # address - it's forced to localhost unless `--keep-host` is
        # also passed, which is why both are set here together (mirrors
        # dufs' own loopback-by-default/--bind-to-open-up contract).
        CONTENT_PORT=$((PORT + 1))
        echo "👀 Starting MyST's own dev server (hot-reloading)..."

        # Re-stage on every source-file change so edits to the vault's
        # real notes (not the staging copy MyST's dev server actually
        # watches) show up live - stage_vault()'s own cmp -s guards keep
        # this from ever writing a file (and thus triggering a rebuild)
        # that hasn't actually changed.
        (
            while true; do
                sleep 1
                stage_vault "$PWD" 2>/dev/null || true
            done
        ) &
        RESTAGE_PID=$!
        # Bind both the background MyST server and the restage loop to
        # this shell's lifetime - prevents orphaned processes holding the
        # preview port across subsequent 'vk watch' restarts.
        trap 'kill "$RESTAGE_PID" 2>/dev/null || true; kill "$MYST_PID" 2>/dev/null || true' EXIT
        echo "⚡ MyST dev server running at http://${BIND}:${PORT}"
        (cd "$PWD/.vk-staging" && HOST="$BIND" "$MYST_BIN" start --keep-host --port "$PORT" --server-port "$CONTENT_PORT") &
        MYST_PID=$!
        wait "$MYST_PID"
        ;;

    watch-all)
        shift
        # Sugar for `watch --all --serve` (see that case) - kept as its
        # own top-level command since it's also the interactive hub's
        # "watch-all" entry.
        exec "$0" watch --all --serve "$@"
        ;;

    build)
        shift
        parse_serve_flags "$@"

        if [ "$ALL" = "1" ]; then
            serve_all_rebuild 0
            TARGET_DIR="$VAULTS_DIR/_build/html"
            echo "✓ Built all vaults at $TARGET_DIR"
        else
            VAULT_NAME=$(get_vault "${POSITIONAL[0]:-}")
            cd_vault "$VAULT_NAME"
            stage_vault "$PWD"
            myst_build "$PWD" "" --html
            TARGET_DIR="$PWD/.vk-staging/_build/html"
            echo "✓ Built $VAULT_NAME at $TARGET_DIR"
        fi

        if [ "$SERVE" = "1" ]; then
            build_dufs_args
            echo "⚡ Serving $TARGET_DIR at $(dufs_url)"
            if [ "$ALL" = "1" ]; then
                echo "Access paths via: $(dufs_url)/<vault-name>/"
            fi
            "$DUFS_BIN" "$TARGET_DIR" --render-index --allow-symlink -A "${DUFS_ARGS[@]}"
        fi
        ;;

    export)
        shift
        VAULT_NAME=""
        FILE=""
        FORMAT="pdf"
        POSITIONAL=()
        while [ $# -gt 0 ]; do
            case "$1" in
                --format)
                    FORMAT="${2:?--format requires a value (pdf or typst)}"
                    shift 2
                    ;;
                --format=*)
                    FORMAT="${1#*=}"
                    shift
                    ;;
                *)
                    POSITIONAL+=("$1")
                    shift
                    ;;
            esac
        done
        case "$FORMAT" in
            pdf|typst) ;;
            *)
                echo "Error: --format must be 'pdf' or 'typst' (got '$FORMAT')." >&2
                exit 1
                ;;
        esac

        VAULT_NAME=$(get_vault "${POSITIONAL[0]:-}")
        cd_vault "$VAULT_NAME"

        FILE="${POSITIONAL[1]:-}"
        if [ -z "$FILE" ]; then
            FILE=$(find . -name "*.md" ! -path "./.vk-staging/*" | "$GUM_BIN" filter --placeholder "Select note to export...")
        fi
        if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
            echo "Error: no such note '$FILE'." >&2
            exit 1
        fi

        stage_vault "$PWD"
        STAGED_FILE=".vk-staging/${FILE#./}"

        # MyST slugifies the export's output basename from the note's
        # title/filename (e.g. "with_tasks.md" -> "with-tasks.pdf") using
        # rules not worth replicating here, so BASE (the source file's own
        # basename) can't be trusted to name-match the produced files.
        # Instead, mark the wall-clock time just before forcing the build,
        # then afterwards pick whichever .pdf/.typ under MyST's own output
        # dirs is newer than that mark - reliable since --force triggers
        # exactly one export per invocation.
        BASE=$(basename "$FILE" .md)
        MARK_FILE=$(mktemp)

        # `--force` builds a Typst export even when the note has no
        # `exports:` frontmatter of its own - vk's own design keeps
        # exports opt-in for authored notes, while still letting this
        # command force one on demand without editing the source note.
        (cd "$PWD/.vk-staging" && "$MYST_BIN" build --ci --force --typst "${STAGED_FILE#.vk-staging/}")

        mkdir -p "$PWD/exports"
        PDF_SRC=$(find "$PWD/.vk-staging/_build/exports" -type f -name '*.pdf' -newer "$MARK_FILE" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
        rm -f "$MARK_FILE"
        if [ -z "$PDF_SRC" ]; then
            echo "Error: MyST did not produce a PDF for '$FILE' - check the build output above." >&2
            exit 1
        fi
        cp "$PDF_SRC" "$PWD/exports/${BASE}.pdf"

        if [ "$FORMAT" = "typst" ]; then
            # The raw Typst bundle (.typ sources) lives under MyST's own
            # temp working dir rather than _build/exports - copy it
            # alongside the PDF so 'typst' format preserves the editable
            # source, not just the compiled PDF.
            TYP_DIR=$(find "$PWD/.vk-staging/_build/temp" -type f -name '*.typ' -newer "$PDF_SRC" -printf '%T@ %h\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2- || true)
            [ -z "$TYP_DIR" ] && TYP_DIR=$(find "$PWD/.vk-staging/_build/temp" -type f -name '*.typ' -printf '%T@ %h\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2- || true)
            if [ -n "$TYP_DIR" ]; then
                mkdir -p "$PWD/exports/${BASE}_typst"
                cp -r "$TYP_DIR/." "$PWD/exports/${BASE}_typst/"
                cp "$PDF_SRC" "$PWD/exports/${BASE}_typst/${BASE}.pdf"
            fi
        fi

        echo "✓ Exported $VAULT_NAME/$FILE to $PWD/exports/${BASE}.pdf"
        ;;

    check)
        shift
        EXTERNAL=0
        POSITIONAL=()
        while [ $# -gt 0 ]; do
            case "$1" in
                --external) EXTERNAL=1; shift ;;
                *) POSITIONAL+=("$1"); shift ;;
            esac
        done
        TARGET="${POSITIONAL[0]:-}"
        if [ -z "$TARGET" ]; then
            VAULTS_LIST=$(list_vaults)
            if [ -n "$VAULTS_LIST" ]; then
                TARGET=$( { echo "All vaults"; echo "$VAULTS_LIST"; } | "$GUM_BIN" choose --header "Check scope:")
            else
                echo "No vaults found." >&2
                exit 1
            fi
        fi
        if [ "$TARGET" = "All vaults" ] || [ "$TARGET" = "all" ] || [ "$TARGET" = "--all" ]; then
            CHECK_VAULTS=$(list_vaults)
        else
            CHECK_VAULTS="$TARGET"
        fi
        if [ -z "$CHECK_VAULTS" ]; then
            echo "No vaults found." >&2
            exit 1
        fi

        OVERALL_OK=1
        while IFS= read -r VNAME; do
            [ -z "$VNAME" ] && continue
            VPATH="$VAULTS_DIR/$VNAME"
            if [ ! -d "$VPATH" ]; then
                echo "✗ vault '$VNAME' does not exist at $VPATH." >&2
                OVERALL_OK=0
                continue
            fi
            echo "── Checking $VNAME ──"
            stage_vault "$VPATH"

            # 'check' only cares whether the build succeeds/fails, not
            # its output - but a plain `myst build --html` here writes
            # straight into ".vk-staging/_build", the same tree
            # myst_build()/vault_needs_build() track via ".base_url"/
            # ".vk_fingerprint" markers for build/watch/serve-all. Since
            # this build (unlike myst_build()) never sets BASE_URL or
            # updates those markers, running 'vk check' on a vault
            # currently served nested under serve-all (BASE_URL=
            # "/<vault-name>") would silently overwrite its cached build
            # with a standalone one while leaving the stale markers
            # claiming a match - serve-all would then keep serving the
            # now-broken build until some unrelated source file change
            # forced a real rebuild. Back up and restore "_build" around
            # the check so it never has a side effect on the cache.
            BUILD_DIR="$VPATH/.vk-staging/_build"
            BUILD_BACKUP=""
            if [ -d "$BUILD_DIR" ]; then
                BUILD_BACKUP=$(mktemp -d)
                mv "$BUILD_DIR" "$BUILD_BACKUP/_build"
            fi

            BUILD_ARGS=(--strict --html)
            [ "$EXTERNAL" = "1" ] && BUILD_ARGS+=(--check-links)
            if (cd "$VPATH/.vk-staging" && "$MYST_BIN" build --ci "${BUILD_ARGS[@]}"); then
                echo "✓ $VNAME: myst build passed"
            else
                echo "✗ $VNAME: myst build FAILED" >&2
                OVERALL_OK=0
            fi

            rm -rf "$BUILD_DIR"
            if [ -n "$BUILD_BACKUP" ]; then
                mv "$BUILD_BACKUP/_build" "$BUILD_DIR"
                rmdir "$BUILD_BACKUP" 2>/dev/null || true
            fi

            if "$PYTHON_BIN" "$VK_VAULT_CHECK" "$VPATH/.vk-staging" \
                --dot "$GRAPHVIZ_DOT_BIN" --neato "$GRAPHVIZ_NEATO_BIN" \
                --fdp "$GRAPHVIZ_FDP_BIN" --sfdp "$GRAPHVIZ_SFDP_BIN" \
                --circo "$GRAPHVIZ_CIRCO_BIN" --twopi "$GRAPHVIZ_TWOPI_BIN"; then
                echo "✓ $VNAME: static checks passed"
            else
                echo "✗ $VNAME: static checks FAILED" >&2
                OVERALL_OK=0
            fi
        done <<< "$CHECK_VAULTS"

        if [ "$OVERALL_OK" = "1" ]; then
            echo "✓ All checks passed."
            exit 0
        else
            echo "✗ One or more checks failed - see above." >&2
            exit 1
        fi
        ;;

    serve-all)
        shift
        # Sugar for `build --all --serve` (see that case) - a one-shot
        # build then static serve, no ongoing watch loop (use `watch-all`
        # for that). Kept as its own top-level command since it's also
        # the interactive hub's "serve-all" entry.
        exec "$0" build --all --serve "$@"
        ;;

    *)
        if [ -n "${1:-}" ]; then
            echo "Unknown command: $1" >&2
            print_usage >&2
            exit 1
        fi
        # Interactive hub: a plain loop (never `exec`s into a
        # subcommand) so cancelling/finishing anything - at any depth -
        # simply returns here instead of exiting the whole session.
        # Ctrl+C/Esc on the hub's own menu (caught by the `|| break`
        # below) is the one true "quit" out of this loop.
        while true; do
            ACTION=$("$GUM_BIN" choose --header "vk - Interactive CLI Management Hub" \
                "search (Search a Vault, or All Vaults)" \
                "note (Create/Edit/Rename/Delete Notes)" \
                "vault (New / Rename / Check a Vault)" \
                "watch-all (Live Preview - All Vaults)" \
                "serve-all (Host Built Vaults)") || break
            CMD=$(echo "$ACTION" | cut -d' ' -f1)
            if [ "$CMD" = "vault" ]; then
                SUB=$("$GUM_BIN" choose --header "Vault:" \
                    "new (Create Vault)" \
                    "rename (Rename Vault)" \
                    "check (Validate Vault)") || continue
                CMD=$(echo "$SUB" | cut -d' ' -f1)
            fi
            "$0" "$CMD" || true
        done
        ;;
esac
