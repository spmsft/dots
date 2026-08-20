#!/usr/bin/env bash
# check-versions.sh - Compare pinned Lean toolchain and lean-lsp-mcp
# versions against their latest available releases.
#
# Exit codes:
#   0 - all versions current or check completed
#   1 - usage error
#
# This script is read-only: it never modifies files.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

usage() {
  echo "Usage: $0"
  echo "Run from the repository root (or anywhere inside it)."
  exit 1
}

# Extract the Lean toolchain version from lean-toolchain.
# Input format:  leanprover/lean4:v4.34.0-rc1
# Output:        4.34.0-rc1
current_lean_version() {
  local raw
  raw="$(cat "$REPO_ROOT/lean-toolchain" 2>/dev/null)" || return 1
  # Strip the "leanprover/lean4:" prefix and "v" prefix
  echo "$raw" | sed 's|leanprover/lean4:||' | sed 's|^v||'
}

# Extract lean-lsp-mcp version from .github/mcp.json or opencode.json.
# Looks for the first "lean-lsp-mcp" string followed by a version.
current_mcp_version() {
  local file
  for file in "$REPO_ROOT/.github/mcp.json" "$REPO_ROOT/opencode.json"; do
    if [ -f "$file" ]; then
      grep -oP 'lean-lsp-mcp==\K[0-9]+\.[0-9]+\.[0-9]+' "$file" 2>/dev/null && return 0
    fi
  done
  return 1
}

# Query PyPI for the latest version of a package.
# Returns the version string or "unavailable" on failure.
latest_pypi_version() {
  local pkg="$1"
  curl -sfL "https://pypi.org/pypi/$pkg/json" 2>/dev/null \
    | grep -oP '"version"\s*:\s*"\K[^"]+' 2>/dev/null \
    | head -1 \
    || echo "unavailable"
}

# Query elan for the latest stable Lean 4 release.
# Returns the version string (without "v" prefix) or "unavailable" on failure.
latest_lean_version() {
  # GitHub releases API: latest release tag_name
  curl -sfL "https://api.github.com/repos/leanprover/lean4/releases/latest" 2>/dev/null \
    | grep -oP '"tag_name"\s*:\s*"\K[^"]+' 2>/dev/null \
    | sed 's|^v||' \
    || echo "unavailable"
}

# Compare two version strings. Sets CMP_RESULT to:
#   "eq" if equal, "gt" if first > second, "lt" if first < second
# Handles pre-release suffixes like -rc1 via sort -V.
CMP_RESULT=""
version_cmp() {
  local a="$1" b="$2"
  if [ "$a" = "$b" ]; then
    CMP_RESULT="eq"
    return
  fi
  # Use sort -V if available (GNU coreutils), else fall back to lexicographic
  if printf '%s\n%s\n' "$a" "$b" | sort -V -C 2>/dev/null; then
    CMP_RESULT="lt"  # a < b
  else
    CMP_RESULT="gt"  # a > b
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

[ $# -gt 0 ] && usage

echo "=== Lean Toolchain Version Check ==="
CURRENT_LEAN="$(current_lean_version)" || { echo "ERROR: cannot read lean-toolchain"; exit 1; }
echo "  Pinned:   $CURRENT_LEAN"
LATEST_LEAN="$(latest_lean_version)"
echo "  Latest:   $LATEST_LEAN"

if [ "$LATEST_LEAN" = "unavailable" ]; then
  echo "  Status:   could not reach GitHub (offline?)"
elif [ "$CURRENT_LEAN" = "$LATEST_LEAN" ]; then
  echo "  Status:   up to date"
else
  version_cmp "$CURRENT_LEAN" "$LATEST_LEAN"
  if [ "$CMP_RESULT" = "gt" ]; then
    echo "  Status:   AHEAD of latest ($LATEST_LEAN)"
  else
    echo "  Status:   BEHIND latest ($LATEST_LEAN)"
  fi
fi

echo ""
echo "=== lean-lsp-mcp Version Check ==="
CURRENT_MCP="$(current_mcp_version)" || { echo "ERROR: cannot read lean-lsp-mcp version from config"; exit 1; }
echo "  Pinned:   $CURRENT_MCP"
LATEST_MCP="$(latest_pypi_version lean-lsp-mcp)"
echo "  Latest:   $LATEST_MCP"

if [ "$LATEST_MCP" = "unavailable" ]; then
  echo "  Status:   could not reach PyPI (offline?)"
elif [ "$CURRENT_MCP" = "$LATEST_MCP" ]; then
  echo "  Status:   up to date"
else
  version_cmp "$CURRENT_MCP" "$LATEST_MCP"
  if [ "$CMP_RESULT" = "gt" ]; then
    echo "  Status:   AHEAD of latest ($LATEST_MCP)"
  else
    echo "  Status:   BEHIND latest ($LATEST_MCP)"
  fi
fi

echo ""
echo "=== Done ==="
