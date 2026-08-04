# Host-specific config too bespoke to generalize into dots itself -
# anything not covered by a dotsLocal field (run `dots-local-options` to
# see the full list) that this one machine specifically needs. Wired in
# via `extraModules` in flake.nix.
#
# Deliberately almost empty - only add to this once you hit something
# concrete that doesn't fit any existing dotsLocal field. See a real
# example's shape (CUDA/llama.cpp cmake flags, extra packages, session
# variables, alien-package protection, ...) via `dots-local-options` or
# by asking around - there's nothing host.nix *must* contain.
{ config, pkgs, lib, dotsLocal, ... }:

{
  # Example: extra packages just for this machine
  # home.packages = with pkgs; [ ];

  # Example: a feature/suite tweak too specific to set via
  # modules/contexts/<context>.nix or modules/rules.nix
  # features.llama-cpp.enable = true;

  # Example: suite/tool enables specific to this machine (run
  # `dots-context-options` for the full list of suites/features and
  # their toggles - this is just a representative sample, not exhaustive).
  # suites.gui-apps.enable = true;
  # suites.dev-tools.rust = true;
  # suites.dtp-tools.mystmd = true;
  # suites.network-tools.bandwhich = true;
  # suites.cloud-tools.azure = true;

  # Example: session variables specific to this machine
  # home.sessionVariables = { };
}
