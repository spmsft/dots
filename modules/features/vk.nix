{ config, lib, pkgs, ... }:

let
  coreLib = import ../core/lib.nix { inherit lib; };
  cfg = config.features.vk;

  # Real script logic lives in a static, shellcheck-able file (vk.sh) -
  # this preamble only resolves Nix-level package paths / options into
  # plain shell variables it references (mirrors viewer.nix/clipboard.nix).
  # gum/helix/dufs are already core packages (modules/core/default.nix);
  # quarto/git/ripgrep are pulled in explicitly here so `vk` works
  # regardless of which suites happen to be enabled.
  vkScript = pkgs.writeShellScriptBin "vk" (''
    #!/usr/bin/env bash
    VAULTS_DIR="${cfg.vaultsDir}"
    WIKILINKS_LUA_SRC="${./vk/wikilinks.lua}"
    GUM_BIN="${pkgs.gum}/bin/gum"
    HX_BIN="${pkgs.helix}/bin/hx"
    QUARTO_BIN="${pkgs.quarto}/bin/quarto"
    DUFS_BIN="${pkgs.dufs}/bin/dufs"
    RG_BIN="${pkgs.ripgrep}/bin/rg"
    GIT_BIN="${pkgs.git}/bin/git"
  '' + builtins.readFile ./vk/vk.sh);

in
{
  options.features.vk = {
    enable = coreLib.mkDefaultDisabledOption "vk: terminal-first wiki & Zettelkasten engine (gum + helix + quarto + dufs)";

    vaultsDir = lib.mkOption {
      type = lib.types.str;
      default = "$HOME/Vaults";
      description = "Root directory containing every vk vault (each a self-contained Git-ready Zettelkasten repo).";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      vkScript
      pkgs.quarto
      pkgs.git
    ];
  };
}
