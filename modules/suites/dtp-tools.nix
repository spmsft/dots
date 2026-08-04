# DTP (Desktop/Document ToolPublishing) tools - diagram/image rendering
# and document typesetting/conversion. Previously split awkwardly across
# two other suites (imagemagick/graphviz lived in suites.tui-apps under
# its own "DTP" heading; quarto/typst/pandoc lived in suites.dev-tools) -
# pulled into its own suite so all five travel together, with a single
# place to look for "what renders/converts documents and diagrams".
{ config, lib, pkgs, alien, ... }:

let
  cfg = config.suites.dtp-tools;
  coreLib = import ../core/lib.nix { inherit lib; };
  appSet = coreLib.mkAppSet {
    inherit alien;
    apps = {
      imagemagick = { enable = cfg.imagemagick; pkg = pkgs.imagemagick; };
      graphviz = { enable = cfg.graphviz; pkg = pkgs.graphviz; };
      pandoc = { enable = cfg.pandoc; pkg = pkgs.pandoc; };
      typst = { enable = cfg.typst; pkg = pkgs.typst; };
      mystmd = { enable = cfg.mystmd; pkg = pkgs.mystmd; };
    };
  };
in
{
  options.suites.dtp-tools = {
    enable = coreLib.mkDefaultDisabledOption "Enable DTP (document/diagram publishing) tools";

    imagemagick = coreLib.mkDefaultDisabledOption "ImageMagick";
    graphviz = coreLib.mkDefaultDisabledOption "Graphviz";
    pandoc = coreLib.mkDefaultDisabledOption "Pandoc (universal document converter)";
    typst = coreLib.mkDefaultDisabledOption "Typst (modern markup-based typesetting)";
    # mystmd replaces the former quarto option (removed 2026-08 - see
    # memory-bank/decisions.md) - MyST is the primary renderer for
    # vk's HTML/Typst/PDF output, no separate pin needed (plain
    # nixpkgs, unlike quarto's old nixpkgs-quarto-pin).
    mystmd = coreLib.mkDefaultDisabledOption "MyST (mystmd - Markdown/Typst/PDF document engine)";
  };

  config = lib.mkMerge [
    # Consolidate with suites.tui-apps: this suite's own `enable` defaults
    # to whatever tui-apps.enable resolves to (cross-suite mkDefault,
    # same pattern as tui-apps.gping tracking network-tools.enable below)
    # - DTP tools are "everyday terminal-adjacent tools" in the same
    # spirit as tui-apps, just split into their own file rather than
    # bloating that one further. Still just a mkDefault - an explicit
    # `suites.dtp-tools.enable` anywhere else always wins.
    { suites.dtp-tools.enable = lib.mkDefault config.suites.tui-apps.enable; }

    # mystmd/typst/pandoc are lightweight, broadly useful document tools -
    # default them on whenever the suite itself is on. graphviz/
    # imagemagick are mostly useful alongside an actual GUI (rendering
    # diagrams/images you'll then look at) - same global condition
    # gui-apps.nix uses for its own baseline (config.core.
    # enableGuiDefaults, purely dotsLocal-derived - see modules/core/
    # platform.nix).
    {
      suites.dtp-tools.mystmd = lib.mkDefault cfg.enable;
      suites.dtp-tools.typst = lib.mkDefault cfg.enable;
      suites.dtp-tools.pandoc = lib.mkDefault cfg.enable;
      suites.dtp-tools.graphviz = lib.mkDefault config.core.enableGuiDefaults;
      suites.dtp-tools.imagemagick = lib.mkDefault config.core.enableGuiDefaults;
    }

    (lib.mkIf cfg.enable {
      home.packages = appSet.packages;

      alienPackages.enabledPackages = appSet.alienEnabled;
    })
  ];
}
