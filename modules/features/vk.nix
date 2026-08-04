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

  # Nix-managed Python for vk's own staging-time analysis (frontmatter/
  # config parsing - see vk/scripts/vault_enhance.py). PyYAML is the
  # only extra dependency; deliberately no venv/direnv anywhere under
  # $HOME/Vaults (see memory-bank/decisions.md) - the interpreter and
  # every package it needs are fully resolved by Nix at build time, so
  # 'vk' works identically regardless of what's installed system-wide.
  vkPython = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);

  # Managed MyST plugin bundle: two small, self-contained ESM files fetched
  # from pinned upstream sources (never fetched at MyST build/serve time,
  # never loaded from a CDN in the browser). NOTE: tabs/cards/grids/buttons
  # are NOT plugins at all - they're native mystmd directives/roles as of
  # 1.9.x (confirmed against https://mystmd.org/guide/dropdowns-cards-and-tabs),
  # so there is nothing to package for those. Only substitutions and
  # collect-references are genuine external plugins:
  #  - myst-substitutions: has a real tagged release (v0.2); fetched from
  #    its GitHub release asset.
  #  - myst-collect-references: no tagged release exists upstream (main-
  #    branch only) - pinned to a specific commit SHA's raw source file
  #    instead, which is self-contained (only Node's fs/path builtins,
  #    verified by inspection) so it doesn't need bundling.
  vkPluginSubstitutions = pkgs.fetchurl {
    url = "https://github.com/myst-contrib/myst-substitutions/releases/download/v0.2/index.mjs";
    sha256 = "0wz6qbpcsby6q1w6arvhwnsqjs67lnv0r6aa3zi49524j4bidcpp";
  };
  vkPluginCollectReferences = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/myst-contrib/myst-collect-references/2573edfcef83326f52ab42f2b4755a8b2976db24/src/aggregate-references.mjs";
    sha256 = "05cs5kiyv1l7a1nr3axalhy1brlxwp14a8z5s2wrmk5vj1k44slm";
  };

  # Referenced as one whole directory (not per individual file, unlike
  # ./vk/filters and ./vk/assets below) - vault_check.py imports
  # vault_enhance/graphviz_preprocess as ordinary Python sibling
  # modules (`import vault_enhance`), which only resolves when they
  # share a single Nix store path/directory. Interpolating each script
  # separately (as this repo does for the CSS/Lua/asset files) would
  # copy every file into its *own* isolated store path instead, which
  # silently breaks that import at runtime - confirmed via
  # `nix eval --impure` while implementing vk-enhance-authoring-checks.
  vkScriptsDir = ./vk/scripts;

  # Build-input fingerprint: changes whenever any staging-pipeline input
  # (this Nix file, the enhancer script, managed CSS/assets, the plugin
  # bundle) changes, even if no vault source file did - vault_needs_build()
  # compares this against the marker baked into a vault's last build so a
  # vk upgrade alone triggers a rebuild. Deliberately store-path based
  # (not a hash of file contents) - any content change already produces a
  # new Nix store path, so this is both simpler and free.
  vkFingerprint = builtins.hashString "sha256" (builtins.concatStringsSep "\n" [
    (toString vkScriptsDir)
    (toString ./vk/filters/taskwarrior.lua)
    (toString ./vk/assets/vk-theme.css)
    (toString ./vk/assets/vk-logo.svg)
    (toString vkPluginSubstitutions)
    (toString vkPluginCollectReferences)
    (toString pkgs.graphviz)
  ]);

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
  # mystmd/pandoc/typst/ripgrep/python3 are pulled in explicitly here so
  # `vk` works regardless of which suites happen to be enabled. `git` is
  # deliberately NOT bundled here (unlike the others) - `suites.git-tools.git`
  # is always enabled (default-on, and relied upon), and routes `git`
  # through `alien.mkEntry` so it can be tdnf/dnf5-backed on Azure Linux
  # instead of Nix's - adding `pkgs.git` here too, unconditionally, would
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
    IMPRINT_MD_SRC="${./vk/imprint.md}"
    VK_TASKWARRIOR_LUA="${./vk/filters/taskwarrior.lua}"
    VK_TASKWARRIOR_PREPROCESS="${vkScriptsDir}/taskwarrior_preprocess.py"
    VK_VAULT_ENHANCE="${vkScriptsDir}/vault_enhance.py"
    VK_VAULT_CHECK="${vkScriptsDir}/vault_check.py"
    VK_NOTE_RENAME="${vkScriptsDir}/note_rename.py"
    VK_THEME_CSS="${./vk/assets/vk-theme.css}"
    VK_LOGO_SVG="${./vk/assets/vk-logo.svg}"
    VK_PLUGIN_SUBSTITUTIONS="${vkPluginSubstitutions}"
    VK_PLUGIN_COLLECT_REFERENCES="${vkPluginCollectReferences}"
    VK_GRAPHVIZ_PREPROCESS="${vkScriptsDir}/graphviz_preprocess.py"
    GRAPHVIZ_DOT_BIN="${pkgs.graphviz}/bin/dot"
    GRAPHVIZ_NEATO_BIN="${pkgs.graphviz}/bin/neato"
    GRAPHVIZ_FDP_BIN="${pkgs.graphviz}/bin/fdp"
    GRAPHVIZ_SFDP_BIN="${pkgs.graphviz}/bin/sfdp"
    GRAPHVIZ_CIRCO_BIN="${pkgs.graphviz}/bin/circo"
    GRAPHVIZ_TWOPI_BIN="${pkgs.graphviz}/bin/twopi"
    VK_FINGERPRINT="${vkFingerprint}"
    GUM_BIN="${pkgs.gum}/bin/gum"
    HX_BIN="${pkgs.helix}/bin/hx"
    MYST_BIN="${pkgs.mystmd}/bin/myst"
    DUFS_BIN="${pkgs.dufs}/bin/dufs"
    RG_BIN="${pkgs.ripgrep}/bin/rg"
    GIT_BIN="${pkgs.git}/bin/git"
    CURL_BIN="${pkgs.curl}/bin/curl"
    PANDOC_BIN="${pkgs.pandoc}/bin/pandoc"
    TYPST_BIN="${pkgs.typst}/bin/typst"
    PYTHON_BIN="${vkPython}/bin/python3"
    # myst shells out to a plain `typst` command by name (no path option
    # of its own) for --typst/--pdf exports - prepend typst's own bin dir
    # so that resolves regardless of which suites happen to be enabled,
    # same rationale as bundling every other *_BIN above.
    export PATH="${pkgs.typst}/bin:$PATH"
    CLIP_PASTE_CMD=(${lib.optionalString (pasteCmdArray != null) pasteCmdArray})
  '' + builtins.readFile ./vk/vk.sh);

in
{
  options.features.vk = {
    enable = coreLib.mkDefaultEnabledOption "vk: terminal-first wiki & Zettelkasten engine (gum + helix + mystmd + pandoc + dufs)";

    vaultsDir = lib.mkOption {
      type = lib.types.str;
      default = "$HOME/Vaults";
      description = "Root directory containing every vk vault (each a self-contained Git-ready Zettelkasten repo).";
    };
  };

  config = lib.mkIf cfg.enable {
    # wl-clipboard/xclip are only needed for 'vk import clipboard' - CURL_BIN
    # is not (curl itself is already an unconditional core package, see
    # modules/core/default.nix, so it's not repeated here). pandoc is
    # pulled in explicitly for two narrow, non-MyST uses: 'vk import
    # bibentry's --citeproc rendering, and the taskwarrior directive's
    # Pandoc+Lua preprocessing step (see modules/features/vk/filters/
    # taskwarrior.lua and vk/scripts/taskwarrior_preprocess.py) - MyST
    # itself is vk's only Markdown renderer/site builder.
    home.packages = [
      vkScript
      pkgs.mystmd
      pkgs.pandoc
      pkgs.typst
    ]
    ++ lib.optionals (backend == "wayland") [ pkgs.wl-clipboard ]
    ++ lib.optionals (backend == "x11") [ pkgs.xclip ];

    dots.tools = [
      {
        name = "vk";
        synopsis = "Vault-of-Knowledge note tool - import/convert content into a local knowledge base.";
        feature = "features.vk";
      }
    ];
  };
}
