{ config, lib, pkgs, ... }:

let
  coreLib = import ../core/lib.nix { inherit lib; };
  cfg = config.features.vk;

  # Shared, derived value (modules/core/platform.nix) - read directly
  # rather than depending on features.clipboard.enable: that feature's
  # own paste logic only exists as bash functions in
  # programs.bash.initExtra, not callable from vk's separate script
  # process, and vk should still offer 'vk import clipboard' regardless
  # of whether the user happens to have features.clipboard enabled too.
  # null on a CLI-only host (no compositor, not WSL) - handled below by
  # leaving pasteCmdArray null, which yields an empty CLIP_PASTE_CMD
  # bash array; vk.sh checks that at runtime and errors with a clear
  # message rather than failing to build.
  backend = config.core.platformBackend;
  pasteCmdArray =
    if backend == null then null
    else {
      wayland = ''"${pkgs.wl-clipboard}/bin/wl-paste"'';
      x11     = ''"${pkgs.xclip}/bin/xclip" "-selection" "clipboard" "-o"'';
      wsl     = ''"powershell.exe" "-NoProfile" "-Command" "Get-Clipboard -Raw"'';
      macos   = ''"pbpaste"'';
    }.${backend};

  # Real script logic lives in a static, shellcheck-able file (vk.sh) -
  # this preamble only resolves Nix-level package paths / options into
  # plain shell variables it references (mirrors viewer.nix/clipboard.nix).
  # gum/helix/dufs are already core packages (modules/core/default.nix);
  # quarto/ripgrep are pulled in explicitly here so `vk` works regardless
  # of which suites happen to be enabled. `git` is deliberately NOT
  # bundled here (unlike the others) - `suites.git-tools.git` is always
  # enabled (default-on, and relied upon), and routes `git` through
  # `alien.mkEntry` so it can be tdnf/dnf5-backed on Azure Linux instead
  # of Nix's - adding `pkgs.git` here too, unconditionally, would
  # re-introduce a Nix-built `git` into `~/.nix-profile/bin`, shadowing
  # the alien one on `$PATH` regardless of that logic (confirmed as a
  # real, live bug via `git-tools.nix`'s alien-aware `programs.git.package`
  # correctly evaluating to `null` on Azure Linux, yet `git` still
  # resolving to `~/.nix-profile/bin/git` - traced to this file). Keep
  # referencing `${pkgs.git}/bin/git` by its absolute store path below,
  # though - that's a self-contained reference the script alone uses
  # internally, not a `$PATH`/`home.packages` entry, so it can't shadow
  # anything.
  vkScript = pkgs.writeShellScriptBin "vk" (''
    #!/usr/bin/env bash
    VAULTS_DIR="${cfg.vaultsDir}"
    WIKILINKS_LUA_SRC="${./vk/wikilinks.lua}"
    IMPRINT_MD_SRC="${./vk/imprint.md}"
    GUM_BIN="${pkgs.gum}/bin/gum"
    HX_BIN="${pkgs.helix}/bin/hx"
    QUARTO_BIN="${pkgs.quarto}/bin/quarto"
    DUFS_BIN="${pkgs.dufs}/bin/dufs"
    RG_BIN="${pkgs.ripgrep}/bin/rg"
    GIT_BIN="${pkgs.git}/bin/git"
    CURL_BIN="${pkgs.curl}/bin/curl"
    PANDOC_BIN="${pkgs.pandoc}/bin/pandoc"
    CLIP_PASTE_CMD=(${lib.optionalString (pasteCmdArray != null) pasteCmdArray})
  '' + builtins.readFile ./vk/vk.sh);

in
{
  options.features.vk = {
    enable = coreLib.mkDefaultEnabledOption "vk: terminal-first wiki & Zettelkasten engine (gum + helix + quarto + dufs)";

    vaultsDir = lib.mkOption {
      type = lib.types.str;
      default = "$HOME/Vaults";
      description = "Root directory containing every vk vault (each a self-contained Git-ready Zettelkasten repo).";
    };
  };

  config = lib.mkIf cfg.enable {
    # wl-clipboard/xclip are only needed for 'vk import clipboard' - CURL_BIN
    # is not (curl itself is already an unconditional core package, see
    # modules/core/default.nix, so it's not repeated here); pandoc is
    # pulled in explicitly for 'vk import bibentry's --citeproc rendering
    # rather than reaching for quarto's own internal pandoc copy (quarto's
    # nixpkgs derivation doesn't expose a simple standalone pandoc binary
    # path - confirmed by inspecting its store output - whereas
    # pkgs.pandoc is nixpkgs' own stable, self-contained package).
    home.packages = [
      vkScript
      pkgs.quarto
      pkgs.pandoc
    ]
    ++ lib.optionals (backend == "wayland") [ pkgs.wl-clipboard ]
    ++ lib.optionals (backend == "x11") [ pkgs.xclip ];
  };
}
