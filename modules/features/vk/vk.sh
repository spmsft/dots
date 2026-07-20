#!/usr/bin/env bash
# vk - Terminal-first wiki & Zettelkasten engine.
#
# The Nix-level preamble (modules/features/vk.nix) resolves every external
# binary this script needs into the *_BIN variables below, and sets
# VAULTS_DIR/WIKILINKS_LUA_SRC before sourcing this file - keeping this
# static, shellcheck-able body free of any Nix syntax (mirrors the
# viewer.nix/clipboard.nix pattern: small Nix preamble + real shell file).
set -euo pipefail

mkdir -p "$VAULTS_DIR"

# Helper: Ensure vault argument or select interactively via gum.
get_vault() {
    local name="${1:-}"
    if [ -z "$name" ]; then
        if [ -d "$VAULTS_DIR" ] && [ -n "$(ls -A "$VAULTS_DIR" 2>/dev/null)" ]; then
            name=$(ls "$VAULTS_DIR" | "$GUM_BIN" choose --header "Select target vault:")
        else
            name=$("$GUM_BIN" input --placeholder "No vaults found. Enter name for a new vault:")
        fi
    fi
    echo "$name"
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
    cd "$path"
}

# Helper: pull dufs' own -p/--port and -b/--bind/--host flags (plus their
# --flag=value forms) out of the remaining CLI args, for 'watch' and
# 'serve-all'. Anything left over is collected into POSITIONAL[] (e.g.
# the vault name for 'watch') so flags can be given in any order, before
# or after the vault name. Left unset, PORT/BIND stay empty and dufs
# falls back to its own defaults (0.0.0.0:5000) - never hardcoded here.
parse_serve_flags() {
    PORT=""
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
# (falling back to dufs' own defaults, 0.0.0.0:5000, when unset).
dufs_url() {
    echo "http://${BIND:-0.0.0.0}:${PORT:-5000}"
}

print_usage() {
    cat <<USAGEEOF
vk - Terminal-first wiki & Zettelkasten engine

Usage:
  vk new                                    Create a new vault (interactive)
  vk note [vault]                           Create/edit/delete/search notes (interactive)
  vk watch [vault] [-p|--port PORT] [-b|--bind ADDR]
                                             Live Quarto preview + dufs server
  vk build [vault] [file PATH] [-p|--port PORT] [-b|--bind ADDR]
                                             Render the vault (or a single file) with Quarto
  vk serve-all [-p|--port PORT] [-b|--bind ADDR]
                                             Serve every vault's _site/ under one dufs instance
  vk help | -h | --help                     Show this message

[vault] may be omitted anywhere it's accepted - vk will prompt via gum.
-p/--port and -b/--bind (aliases: --host) are passed straight through to
dufs; both may also be given as --port=VALUE/--bind=VALUE, in any order,
before or after the vault name. Left unset, dufs uses its own defaults
(0.0.0.0:5000).
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

        mkdir -p "$VAULT_PATH"/{permanent,literature,daily,_extensions}

        # 1. Generate Base Index Configuration
        cat <<NOTEEOF > "$VAULT_PATH/index.md"
---
title: "Index // $VAULT_NAME"
---
# Welcome to your Knowledge Base

- [[permanent/index.md|Permanent Notes]]
- [[literature/index.md|Literature Notes]]
NOTEEOF
        touch "$VAULT_PATH/permanent/index.md" "$VAULT_PATH/literature/index.md"

        # 2. Generate Quarto Config
        cat <<QUARTOEOF > "$VAULT_PATH/_quarto.yml"
project:
  type: website
  output-dir: _site

website:
  title: "$VAULT_NAME"
  search: true
  sidebar:
    style: "docked"
    search: true
    contents:
      - index.md
      - section: "Permanent"
        contents: "permanent/*.md"
      - section: "Literature"
        contents: "literature/*.md"
      - section: "Daily"
        contents: "daily/*.md"

format:
  html:
    theme: cosmo
    toc: true
    toc-location: right
    code-fold: true
    filters:
      - wikilinks.lua
QUARTOEOF

        # 3. Install the AST Lua filter (shared, static - not regenerated
        # per-vault from a heredoc, so every vault always gets the exact
        # same, already-tested filter).
        cp "$WIKILINKS_LUA_SRC" "$VAULT_PATH/wikilinks.lua"

        (cd "$VAULT_PATH" && "$GIT_BIN" init -q && echo "_site/" > .gitignore && "$GIT_BIN" add . && "$GIT_BIN" commit -q -m "Init vault")
        echo "✓ Vault initialized successfully at $VAULT_PATH"
        ;;

    note)
        VAULT_NAME=$(get_vault "${2:-}")
        cd_vault "$VAULT_NAME"

        ACTION=$("$GUM_BIN" choose "Create Note" "Edit Note" "Delete Note" "Fuzzy Search Text")

        case "$ACTION" in
            "Create Note")
                CAT=$("$GUM_BIN" choose "permanent" "literature" "daily")
                TITLE=$("$GUM_BIN" input --placeholder "Note filename (e.g., compiler_optimizations)...")
                if [ -z "$TITLE" ]; then exit 1; fi
                FILE="$CAT/${TITLE%.md}.md"
                cat <<NOTEEOF > "$FILE"
---
title: "${TITLE//_/ }"
date: $(date +%Y-%m-%d)
---

# ${TITLE//_/ }

NOTEEOF
                "$HX_BIN" "$FILE"
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
                # Structural content discovery via ripgrep pipeline mapped
                # into a helix target sequence ("file:line" - hx jumps
                # straight to that line). _site/ is a git-ignored build
                # tree, but rg doesn't know that outside a git repo
                # context, so it's excluded explicitly too.
                SELECTION=$("$RG_BIN" --line-number --no-heading --color=always --glob '!_site/**' . | "$GUM_BIN" filter --ansi --placeholder "Search body content...")
                if [ -z "$SELECTION" ]; then exit 1; fi
                FILE=$(echo "$SELECTION" | cut -d: -f1)
                LINE=$(echo "$SELECTION" | cut -d: -f2)
                "$HX_BIN" "$FILE:$LINE"
                ;;
        esac
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
        echo "⚡ Active multi-vault core instance running at $(dufs_url)"
        echo "Access paths via: $(dufs_url)/<vault-name>/_site/"
        "$DUFS_BIN" "$VAULTS_DIR" --render-index -A "${DUFS_ARGS[@]}"
        ;;

    *)
        if [ -n "${1:-}" ]; then
            echo "Unknown command: $1" >&2
            print_usage >&2
            exit 1
        fi
        echo "Interactive CLI Management Hub"
        ACTION=$("$GUM_BIN" choose "new (Create Vault)" "note (CRUD Operations)" "watch (Live Edit Preview)" "serve-all (Host Hub)")
        CMD=$(echo "$ACTION" | cut -d' ' -f1)
        exec "$0" "$CMD"
        ;;
esac
