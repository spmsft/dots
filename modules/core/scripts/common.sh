#!/usr/bin/env bash
# Shared bash boilerplate (colors/headers/gum-detection) for dots'
# generated scripts. Every `pkgs.writeShellScriptBin` in dots that wants
# this should `source ${./common.sh}` (Nix path interpolation - embeds
# this file's store path) instead of redefining it.
#
# This file is a real, standalone, shellcheck-able bash file (not a Nix
# string) - sourced at runtime, not baked in via string interpolation, so
# it has no access to Nix values. Anything needing a Nix-evaluated value
# (package paths, config) still has to be interpolated by the calling
# script itself.

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m'
BOLD='\033[1m'

USE_GUM=0
if command -v gum >/dev/null 2>&1; then
  USE_GUM=1
fi

print_header() {
  local icon="$1"
  local title="$2"
  echo ""
  if [ "$USE_GUM" -eq 1 ]; then
    gum style --border rounded --border-foreground 62 --padding "0 1" --bold "$icon  $title"
  else
    echo "=============================================================="
    echo "$title"
    echo "=============================================================="
  fi
  echo ""
}

print_section() {
  local icon="$1"
  local text="$2"
  if [ "$USE_GUM" -eq 1 ]; then
    gum style --foreground 51 --bold "$icon $text"
  else
    echo -e "${CYAN}${text}${NC}"
  fi
}

print_error() {
  local text="$1"
  if [ "$USE_GUM" -eq 1 ]; then
    gum style --foreground 196 --bold "✗ $text"
  else
    echo -e "${RED}✗ ${text}${NC}"
  fi
}

# log_* helpers - a second, simpler style used by update-appimages/the new
# setup-* scripts (kept as a distinct, shorter convention rather than
# forcing print_header/print_section everywhere - not every script needs a
# bordered header)
log_info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

BULLET="*"
if [ "$USE_GUM" -eq 1 ]; then
  BULLET="•"
fi
