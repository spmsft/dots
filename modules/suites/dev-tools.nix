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

  leanStarterSrc = ../features/lean/lean-starter;

  # Shared by mk-lean and update-lean: sync the project's lean-toolchain
  # to whatever its resolved dependencies actually agree on. A freshly
  # scaffolded project's `lean-toolchain` pins a floating `stable` alias,
  # but a dependency (e.g. CSLib, and transitively Mathlib) usually pins
  # a specific release/rc - lake refuses to auto-overwrite an explicit
  # pin with a dependency's, so it just warns forever and skips
  # `lake exe cache get`. Majority-vote across every resolved
  # dependency's own lean-toolchain (mirrors lake's own "multiple
  # candidates" list) and adopt that instead - virtually always
  # unanimous once Mathlib-adjacent deps are involved, and works for any
  # Lean project, not just ones scaffolded via mk-lean.
  leanToolchainSyncSnippet = ''
    if [ -d .lake/packages ]; then
      RESOLVED=$(cat .lake/packages/*/lean-toolchain 2>/dev/null | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
      CURRENT=$(cat lean-toolchain 2>/dev/null || true)
      if [ -n "$RESOLVED" ] && [ "$RESOLVED" != "$CURRENT" ]; then
        echo "$RESOLVED" > lean-toolchain
      fi
    fi
  '';

  # mdformat + mdformat-myst, bundled into one Python env so mdformat's
  # plugin auto-discovery (entry points) picks up the MyST target spec
  # automatically. mdformat-myst only understands MyST's *backtick*
  # fence directive syntax though - it corrupts colon-fenced directives
  # (`:::{name}`, the form our vaults actually use throughout, e.g.
  # demo-vault/texts/vk-demo-guide.md's tab-set/grid/card blocks) by
  # escaping the brace (see executablebooks/mdformat-myst#13, an
  # unfixed upstream gap). mdformat-vk.py wraps plain mdformat, shields
  # every colon-fenced block (using the exact same nesting rule
  # mdit-py-plugins' colon_fence rule itself uses) before formatting
  # and splices each one back in verbatim afterwards - see that file's
  # own docstring. Exposed under the name `mdformat` itself (not
  # `mdformat-vk`) so languages.toml's `formatter = { command =
  # "mdformat"; ... }` doesn't need to know about the wrapper.
  mdformatEnv = pkgs.python3.withPackages (ps: [ ps.mdformat ps.mdformat-myst ]);
  mdformatMyst = pkgs.runCommand "mdformat-vk"
    { meta = mdformatEnv.meta; }
    ''
      mkdir -p "$out/bin"
      cat > "$out/bin/mdformat" <<EOF
      #!${pkgs.runtimeShell}
      export MDFORMAT_VK_REAL_BIN="${mdformatEnv}/bin/mdformat"
      exec "${mdformatEnv}/bin/python3" "${./mdformat-vk.py}" "\$@"
      EOF
      chmod +x "$out/bin/mdformat"
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

    # Shell aliases for one-off `uvx <package>` invocations - each
    # `name = "package"` entry below becomes
    # `programs.bash.shellAliases.<name> = "uvx <package>"`, so running
    # a rarely-needed Python CLI tool doesn't require its own
    # home.packages entry (or a whole nixpkgs derivation, which may not
    # even exist/build - see vk's MarkItDown decision in
    # memory-bank/decisions.md) - just `uvx`'s own per-tool cache
    # (fast after the first, ~30s cold, run). Add more entries here
    # (repo-wide) or via dotsLocal.shell.shellAliases (single-machine)
    # rather than hand-writing a `programs.bash.shellAliases.foo = "uvx
    # bar";` line each time.
    uvxAliases = lib.mkOption {
      type = with lib.types; attrsOf str;
      default = {
        markitdown = "markitdown";
        trafilatura = "trafilatura";
      };
      description = ''
        `alias-name = "uvx-package-name"` pairs, each turned into a
        `programs.bash.shellAliases.<alias-name> = "uvx <package>"`
        entry (only when `suites.dev-tools.uv` is enabled - default
        on). Trailing arguments still pass through normally (e.g.
        `markitdown foo.pdf` -> `uvx markitdown foo.pdf`).
      '';
    };

    # marksman is helix's Markdown LSP (bash-language-server, helix's
    # other core LSP dep, already ships unconditionally in
    # modules/core/default.nix) - defaults on for the same reason.
    marksman = coreLib.mkDefaultEnabledOption "marksman (Markdown language server)";
    snippetsLs = coreLib.mkDefaultEnabledOption "snippets-ls (snippet language server)";

    # JSON tooling
    json = coreLib.mkDefaultEnabledOption "JSON toolchain";

    # XML tooling
    xml = coreLib.mkDefaultEnabledOption "XML toolchain";

    # Markdown formatter for Helix (see languages.toml's markdown
    # `formatter` entry). mdformat-myst (not a generic CommonMark
    # formatter like prettier) is MyST-aware - it understands
    # directives, roles, dollar-math, frontmatter and footnotes, which
    # matters for vk vaults specifically but applies to any Markdown.
    markdownFormat = coreLib.mkDefaultEnabledOption "mdformat + mdformat-myst (MyST-aware Markdown formatter for Helix)";

    # Haskell tooling
    haskell = coreLib.mkDefaultDisabledOption "Haskell toolchain (ghc, cabal, stack)";

    # Lean 4 tooling. `elan` (the rustup-equivalent version manager) is
    # installed rather than a bare pkgs.lean4 - real Lean projects pin
    # their own toolchain via a `lean-toolchain` file (especially once
    # they depend on Batteries/Aesop/Mathlib/etc., each of which pins
    # its own version), and elan transparently fetches/switches to the
    # right one per-project. Helix 25.07.1 already ships a working Lean
    # `language-server.lean = { command = "lake", args = ["serve"] }`
    # entry out of the box (see `hx --health lean`) - elan only needs
    # to put `lake`/`lean` themselves on PATH, no languages.toml
    # customization is required. See `mk-lean` below for a starter
    # project template (Batteries/Aesop/Qq/CSLib pre-declared).
    lean = coreLib.mkDefaultEnabledOption "Lean 4 toolchain (elan)";

    # lean-helix-view: terminal-native Lean goal/diagnostics viewer for
    # Helix (which has no InfoView-equivalent) - a transparent `lake
    # serve` proxy plus a ratatui side-pane viewer. Packaged in
    # pkgs/lean-helix-view.nix (not in nixpkgs). Off by default since it
    # requires a manual languages.toml LSP-command override (see
    # settings/chromaden/home/.config/helix/languages.toml) and a
    # separate tmux/zellij pane to actually show anything.
    leanHelixView = coreLib.mkDefaultDisabledOption "lean-helix-view (terminal Lean goal/diagnostics viewer for Helix)";
    
    # HMR tooling
    entr = coreLib.mkDefaultEnabledOption "entr (file watcher for auto-rebuilds)";

    # Web development tools
    mkcert = coreLib.mkDefaultDisabledOption "mkcert (locally-trusted development certificates)";

    # Document/Publishing tools moved to suites.dtp-tools (mystmd/typst/
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
      (lib.mkIf cfg.markdownFormat mdformatMyst)
      (lib.mkIf cfg.snippetsLs external.snippets-ls)
      (lib.mkIf cfg.haskell ghc)
      (lib.mkIf cfg.haskell cabal-install)
      (lib.mkIf cfg.haskell stack)
      (lib.mkIf cfg.lean elan)
      (lib.mkIf cfg.leanHelixView external.lean-helix-view)
      (lib.mkIf cfg.entr entr)
      (lib.mkIf cfg.lua lua5_4)
      (lib.mkIf cfg.luajit luajitNoLuaSymlink)
      (lib.mkIf cfg.egglog egglog)
      (lib.mkIf cfg.steel steel)
      (lib.mkIf cfg.prettier prettier)
    ]) ++ appSet.packages
      ++ lib.optional cfg.lean (pkgs.writeShellScriptBin "mk-lean" ''
        #!/usr/bin/env bash
        # mk-lean - scaffold a new Lean 4 project from the lean-starter
        # template (Batteries/Aesop/Qq/CSLib pre-declared), then resolve
        # dependencies and sync the toolchain so it builds cleanly out
        # of the box.
        # Usage: mk-lean <target-dir>
        set -e
        if [ -z "$1" ]; then
          echo "Usage: mk-lean <target-dir>" >&2
          exit 1
        fi
        TARGET="$1"
        if [ -e "$TARGET" ]; then
          echo "mk-lean: '$TARGET' already exists" >&2
          exit 1
        fi
        cp -r ${leanStarterSrc} "$TARGET"
        chmod -R u+w "$TARGET"
        echo "Created $TARGET from lean-starter. Resolving dependencies (lake update)..."
        (
          cd "$TARGET"
          lake update
          ${leanToolchainSyncSnippet}
        )
        LEAN_TOOLCHAIN=$(cat "$TARGET/lean-toolchain" 2>/dev/null || echo "(unknown)")
        echo "✓ $TARGET is ready on $LEAN_TOOLCHAIN. Next: cd $TARGET && lake exe cache get && lake build"
      '')
      ++ lib.optional cfg.lean (pkgs.writeShellScriptBin "update-lean" ''
        #!/usr/bin/env bash
        # update-lean - refresh an existing Lean 4 project's dependencies
        # (lake update) and keep its lean-toolchain synced to whatever
        # they resolve to - the same fix mk-lean applies at scaffold
        # time (see leanToolchainSyncSnippet's own comment in
        # dev-tools.nix), just re-runnable against an existing project
        # any time dependencies move to a new toolchain.
        # Usage: update-lean [project-dir]  (defaults to .)
        set -e
        TARGET="''${1:-.}"
        if [ ! -f "$TARGET/lakefile.toml" ] && [ ! -f "$TARGET/lakefile.lean" ]; then
          echo "update-lean: '$TARGET' doesn't look like a Lean project (no lakefile.toml/lakefile.lean)" >&2
          exit 1
        fi
        (
          cd "$TARGET"
          lake update
          ${leanToolchainSyncSnippet}
        )
        LEAN_TOOLCHAIN=$(cat "$TARGET/lean-toolchain" 2>/dev/null || echo "(unknown)")
        echo "✓ Updated $TARGET, now on $LEAN_TOOLCHAIN. Next: cd $TARGET && lake exe cache get && lake build"
      '');

    alienPackages.enabledPackages = appSet.alienEnabled;

    programs.bash.shellAliases = lib.mkIf cfg.uv
      (lib.mapAttrs (_: pkg: "uvx ${pkg}") cfg.uvxAliases);

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
