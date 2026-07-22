#!/usr/bin/env bash
set -e

# Installs Nix via the Determinate Systems installer with
# --no-modify-profile: no /etc/profile.d/nix.sh or ~/.bash_profile hook
# gets created, since this repo's own nixon/nixoff (modules/core/
# nixon.nix) manages nix-loading itself rather than relying on the
# installer's shell integration - see memory-bank/decisions.md's
# 2026-07-22 nixon/nixoff entry for the full rationale (a system-wide,
# unconditional profile hook was found to be the root cause of nix
# state leaking into `nixoff`'s otherwise-clean shell). `./setup.sh`
# already knows to fall back to /nix/var/nix/profiles/default/bin
# directly if `nix` isn't on PATH yet, so no shell restart or manual
# PATH/profile setup is required before running it.
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | \
  sh -s -- install --no-modify-profile
