{ config, lib, pkgs, alien, dotsLocal, ... }:

let
  cfg = config.suites.dev-tools;
  coreLib = import ../core/lib.nix { inherit lib; };
  # Only the alien-managed subset (marksman/mkcert) - everything else
  # in this feature is a plain, always-Nix-installed package with no alien
  # counterpart, so it stays as a hand-written lib.mkIf list below.
  appSet = coreLib.mkAppSet {
    inherit alien;
    apps = {
      marksman = { enable = cfg.marksman; pkg = pkgs.marksman; };
      mkcert = { enable = cfg.mkcert; pkg = pkgs.mkcert; };
    };
  };

  # nixpkgs' luajit derivation ships its own `bin/lua` symlink (pointing
  # at luajit itself) alongside `bin/luajit` - which collides with
  # pkgs.lua5_4's own `bin/lua` if both packages are installed together
  # (see dotsLocal.lua.jit's doc comment). Re-expose only `luajit`,
  # dropping that symlink, so `lua` (from cfg.lua/pkgs.lua5_4, installed
  # independently below) and `luajit` can always coexist without a
  # home-manager file collision, regardless of which combination of the
  # two toggles is on.
  luajitNoLuaSymlink = pkgs.runCommand "luajit-no-lua-symlink"
    { meta = pkgs.luajit.meta; }
    ''
      mkdir -p "$out/bin"
      ln -s "${pkgs.luajit}/bin/luajit" "$out/bin/luajit"
    '';
in
{
  options.suites.dev-tools = {
    enable = coreLib.mkDefaultEnabledOption "Enable dev tools";

    # Nix tooling
    nixd = coreLib.mkDefaultEnabledOption "nixd (Nix language server)";

    # Rust tooling
    rust = coreLib.mkDefaultEnabledOption "Rust toolchain (mold, clang, sccache)";
    
    # Python tooling
    python= coreLib.mkDefaultEnabledOption "Python toolchain";

    # General tooling
    uv = coreLib.mkDefaultEnabledOption "uv (Python package/project manager)";
    # marksman is helix's Markdown LSP (bash-language-server, helix's
    # other core LSP dep, already ships unconditionally in
    # modules/core/default.nix) - defaults on for the same reason.
    marksman = coreLib.mkDefaultEnabledOption "marksman (Markdown language server)";
    snippetsLs = coreLib.mkDefaultEnabledOption "snippets-ls (snippet language server)";

    # JSON tooling
    json = coreLib.mkDefaultEnabledOption "JSON toolchain";

    # XML tooling
    xml = coreLib.mkDefaultEnabledOption "XML toolchain";

    # Haskell tooling
    haskell = coreLib.mkDefaultDisabledOption "Haskell toolchain (ghc, cabal, stack)";
    
    # HMR tooling
    entr = coreLib.mkDefaultEnabledOption "entr (file watcher for auto-rebuilds)";

    # Web development tools
    mkcert = coreLib.mkDefaultDisabledOption "mkcert (locally-trusted development certificates)";

    # Document/Publishing tools moved to suites.dtp-tools (quarto/typst/
    # pandoc) - see that suite's own module for the full rationale.

    # Lua tooling - defaults come from dotsLocal.lua.* (see
    # modules/local/schema.nix) rather than a hardcoded true/false, so
    # each machine can opt into/out of LuaJIT without editing this repo.
    lua = lib.mkEnableOption "Lua interpreter (pkgs.lua5_4 - provides `lua`/`luac`)" // {
      default = dotsLocal.lua.enable;
    };
    luajit = lib.mkEnableOption "LuaJIT (JIT-compiled Lua 5.1 with FFI - provides `luajit`)" // {
      default = dotsLocal.lua.jit;
    };

    # Other tools
    egglog = coreLib.mkDefaultDisabledOption "egglog (e-graph toolkit)";
    steel = coreLib.mkDefaultDisabledOption "steel (Scheme interpreter)";
    prettier = coreLib.mkDefaultDisabledOption "prettier (code formatter)";
  };

  config = lib.mkIf cfg.enable {
    # Nix tooling
    home.packages = (with pkgs; builtins.filter (p: p != null) [
      (lib.mkIf cfg.nixd nixd)
      (lib.mkIf cfg.nixd alejandra)
      (lib.mkIf cfg.rust mold)
      (lib.mkIf cfg.rust clang)
      (lib.mkIf cfg.rust sccache)
      (lib.mkIf cfg.rust rust-analyzer)
      (lib.mkIf cfg.json vscode-json-languageserver)
      (lib.mkIf cfg.python basedpyright)
      (lib.mkIf cfg.python ruff)
      (lib.mkIf cfg.uv uv)
      (lib.mkIf cfg.xml lemminx)
      (lib.mkIf cfg.snippetsLs external.snippets-ls)
      (lib.mkIf cfg.haskell ghc)
      (lib.mkIf cfg.haskell cabal-install)
      (lib.mkIf cfg.haskell stack)
      (lib.mkIf cfg.entr entr)
      (lib.mkIf cfg.lua lua5_4)
      (lib.mkIf cfg.luajit luajitNoLuaSymlink)
      (lib.mkIf cfg.egglog egglog)
      (lib.mkIf cfg.steel steel)
      (lib.mkIf cfg.prettier prettier)
    ]) ++ appSet.packages;

    alienPackages.enabledPackages = appSet.alienEnabled;

    # nixd config
    # NOTE: uses config.home.homeDirectory (resolved from dotsLocal in
    # flake.nix) and assumes `dots` is checked out directly in
    # $HOME/dots (matches DOTS_DIR's own default in scripts.nix) - not
    # fully general if someone uses a custom DOTS_DIR.
    home.file.".nixd.json" = lib.mkIf cfg.nixd {
      text = builtins.toJSON {
        options = {
          home-manager = {
            # `default` is the real flake output name (see flake.nix) -
            # homeConfigurations has never been keyed by username in this
            # repo (it went priv/work -> default/default-opt across the
            # re-architecture, never username-based) - this was a stale
            # reference that predates even that split, confirmed via
            # `git log -p` showing it unchanged since the file's first
            # version. nixd's option-completion was likely never working
            # correctly before this fix.
            expr = "(builtins.getFlake \"${config.home.homeDirectory}/dots\").homeConfigurations.default.options";
          };
        };
        
        nixpkgs = {
          expr = "import (builtins.getFlake \"${config.home.homeDirectory}/dots\").inputs.nixpkgs { }";
        };

        formatting = {
          command = [ "alejandra" ];
        };
      };
    };

    # Rust config
    programs.cargo = lib.mkIf cfg.rust {
      enable = true;
      settings = {
        target."x86_64-unknown-linux-gnu" = {
          linker = "${pkgs.clang}/bin/clang";
          rustflags = ["-C" "link-arg=-fuse-ld=${pkgs.mold}/bin/mold"];
        };
      };
    };

    home.sessionVariables = lib.mkIf cfg.rust {
      RUSTC_WRAPPER = "${pkgs.sccache}/bin/sccache";
    };
  };
}
