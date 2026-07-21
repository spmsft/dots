#!/usr/bin/env bash

# Exit on error
set -e

DOTS_DIR="${DOTS_DIR:-$(cd "$(dirname "$0")" && pwd)}"
CONTEXTS_DIR="$DOTS_DIR/modules/contexts"

# List every available context - a real, existing modules/contexts/<name>.nix
# file, `common.nix` excluded since it's the always-imported baseline, not
# something to pick standalone.
list_contexts() {
    echo "Available contexts:"
    for f in "$CONTEXTS_DIR"/*.nix; do
        name=$(basename "$f" .nix)
        [ "$name" = "common" ] && continue
        echo "  - $name"
    done
}

CONTEXT=$1

if [ "$CONTEXT" = "-l" ] || [ "$CONTEXT" = "--list" ] || [ "$CONTEXT" = "list" ]; then
    list_contexts
    exit 0
fi

if [ -z "$CONTEXT" ]; then
    echo "Usage: ./setup.sh <context>"
    echo "       ./setup.sh --list    # show available contexts"
    echo "Example: ./setup.sh work"
    echo ""
    list_contexts
    exit 1
fi

DOTS_LOCAL="$HOME/dots-local"
TEMPLATE_DIR="$DOTS_DIR/templates/local"

# Determine hostname (use short hostname by default)
HOSTNAME="$HOSTNAME"
SYSTEM="x86_64-linux"
MARCH="native"
BARCH="x86_64-v3"
DISTRO="cachyos"
# Supported distro values: cachyos | opensuse | azurelinux3 | azurelinux4 | debian
# (selects the alien-package backend - see `dots-local-options distro`,
# or modules/local/schema.nix's `distro` option description directly,
# for the full list)

# 1. Create dots-local if it doesn't exist
if [ ! -d "$DOTS_LOCAL" ]; then
    echo "Creating private identity repo at $DOTS_LOCAL..."

    if [ ! -d "$TEMPLATE_DIR" ]; then
        echo "ERROR: Template directory not found: $TEMPLATE_DIR" >&2
        echo "Expected setup.sh to be run from inside the dots repo (or DOTS_DIR set correctly)." >&2
        exit 1
    fi

    mkdir -p "$DOTS_LOCAL"
    chmod 700 "$DOTS_LOCAL"
    cd "$DOTS_LOCAL"
    git init

    # Copy the template files as-is, then fill in the @@TOKEN@@
    # placeholders below with real values. The templates
    # (dots/templates/local/) are real, standalone, syntactically
    # valid Nix files - not a bash heredoc mixed with Nix escaping - so
    # they're easy to read/edit/diff on their own, independent of this
    # script.
    cp "$TEMPLATE_DIR/gitignore" .gitignore
    cp "$TEMPLATE_DIR/appimages.nix" appimages.nix
    cp "$TEMPLATE_DIR/flake.nix" flake.nix
    cp "$TEMPLATE_DIR/host.nix" host.nix

    # Pre-generate a random Taskwarrior sync credential (dotsLocal.taskSync.
    # credential - see modules/local/schema.nix) into the template's
    # commented-out example, so a user turning on task sync later doesn't
    # have to invent a secure secret by hand. Harmless if never used - the
    # taskSync block stays commented out until explicitly enabled.
    if command -v openssl >/dev/null 2>&1; then
        TASK_SYNC_CREDENTIAL=$(openssl rand -hex 32)
    else
        TASK_SYNC_CREDENTIAL=$(head -c32 /dev/urandom | od -An -tx1 | tr -d ' \n')
    fi

    # Pre-generate a client_id too (dotsLocal.taskSync.clientId). Must be
    # a valid UUID (per task-sync(5)/taskchampion-sync-server), and -
    # unlike a per-device secret - this SAME value has to be copied to
    # every machine/app (lazytask included) that should share this one
    # task list, not regenerated per machine. See
    # modules/features/task-sync.nix's 2026-07-21 correction note for
    # why: client_id identifies the shared list, not a device identity.
    if [ -r /proc/sys/kernel/random/uuid ]; then
        TASK_SYNC_CLIENT_ID=$(cat /proc/sys/kernel/random/uuid)
    elif command -v uuidgen >/dev/null 2>&1; then
        TASK_SYNC_CLIENT_ID=$(uuidgen)
    else
        TASK_SYNC_CLIENT_ID=$(head -c16 /dev/urandom | od -An -tx1 | tr -d ' \n' | sed -E 's/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/')
    fi

    sed -i \
        -e "s|@@SYSTEM@@|${SYSTEM}|g" \
        -e "s|@@BARCH@@|${BARCH}|g" \
        -e "s|@@MARCH@@|${MARCH}|g" \
        -e "s|@@DISTRO@@|${DISTRO}|g" \
        -e "s|@@HOSTNAME@@|${HOSTNAME}|g" \
        -e "s|@@USERNAME@@|$(whoami)|g" \
        -e "s|@@UID@@|$(id -u)|g" \
        -e "s|@@GID@@|$(id -g)|g" \
        -e "s|@@HOMEDIR@@|${HOME}|g" \
        -e "s|@@CONTEXT@@|${CONTEXT}|g" \
        -e "s|@@TASK_SYNC_CREDENTIAL@@|${TASK_SYNC_CREDENTIAL}|g" \
        -e "s|@@TASK_SYNC_CLIENT_ID@@|${TASK_SYNC_CLIENT_ID}|g" \
        flake.nix

    git add flake.nix .gitignore appimages.nix host.nix
    git commit -m "Initial identity for ${CONTEXT}"
    cd - > /dev/null
else
    echo "Using existing identity at ${DOTS_LOCAL}"
fi

# 2. Perform the initial bootstrap
# NOTE: the flake output is always "default" - which context (priv/work/
# ...) you get is fully determined by dots-local's `context` field above,
# not by the flake output name.
echo "Running initial Home Manager bootstrap for context: ${CONTEXT}..."

nix run home-manager -- switch \
  --flake .#default \
  --override-input dots-local git+file://"${DOTS_LOCAL}"

echo "--------------------------------------------------"
echo "Setup complete! Restart your shell to use 'apply-dots'."
echo ""
echo "Next steps:"
echo "1. Edit ~/dots-local/flake.nix to set your name, email, and (optionally) tune flag overrides"
echo "2. Decide on nixonDefault (true = nix-managed shell by default, false = pure host shell -"
echo "   toggle anytime with the nixon/nixoff aliases regardless of this default)"
echo "3. Run 'dots-local-options' to see every available field (gpu/compositor/isWsl/machine/"
echo "   sync/etc.) with its type/default/description, generated live from the real schema"
echo "4. Add AppImages to ~/dots-local/appimages.nix"
echo "5. Put anything too bespoke to generalize (exact CUDA flags, one-off"
echo "   packages, ...) in ~/dots-local/host.nix - already wired in via extraModules"
echo "6. Run apply-dots to activate changes"
echo "7. (Optional) Uncomment 'taskSync' in ~/dots-local/flake.nix to enable Taskwarrior"
echo "   sync (auto-spawned server and/or a client hook into ~/.taskrc) - a random"
echo "   sync credential AND client_id were already pre-generated into that"
echo "   commented-out block. If sharing one task list across multiple machines/apps"
echo "   (e.g. lazytask), copy the SAME credential and clientId to each of them."
