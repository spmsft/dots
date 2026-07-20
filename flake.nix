{
  description = "A custom multi-machine home manager setup";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    # Pinned nixpkgs revision providing quarto 1.8.26 - re-verified
    # 2026-07-19: current nixos-unstable's quarto 1.9.37 has a genuine,
    # reproducible functional break with the pandoc version in the SAME
    # nixpkgs revision (3.7.0.2) - `quarto check`'s basic markdown render
    # step fails with `Aeson exception: Unknown option
    # "syntax-highlighting"` (quarto 1.9.37 passes a pandoc CLI flag that
    # doesn't exist until pandoc 3.8+). quarto 1.8.26 doesn't use that
    # flag and renders cleanly with the exact same pandoc 3.7.0.2 -
    # confirmed by building both quarto versions directly and running
    # `quarto check` against each. This is purely a QUARTO version-pin
    # (older quarto compatible with current pandoc) - NOT a pandoc
    # version pin (pandoc is 3.7.0.2 in both this revision and unstable;
    # an earlier version of this comment incorrectly claimed "pandoc
    # 3.1.11.1" - that was already stale/inaccurate before this fix, see
    # memory-bank/learnings.md).
    nixpkgs-quarto-pin.url = "github:nixos/nixpkgs/15f4ee454b1dce334612fa6843b3e05cf546efab";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # `nur`/`nixgl` - confirmed unused anywhere in `dots` or `dots-local`
    # (2026-07-19 flake.nix audit: no module reads `pkgs.nur.*`, `nixgl`
    # wasn't even applied as an overlay). Commented out rather than
    # deleted outright, per explicit user decision, in case either is
    # wanted again later (nixgl in particular is the standard fix for
    # OpenGL-dependent Nix packages on non-NixOS hosts, which this
    # project's whole premise - Nix atop a real FHS distro - could
    # plausibly need someday). Re-enable by uncommenting here, adding
    # back to the `outputs` function's argument list below, and (for
    # `nur`) re-adding `nur.overlays.default` to the `overlays` list in
    # `mkHomeConfig`.
    # nur.url = "github:nix-community/NUR";
    # nixgl = { url = "github:nix-community/nixGL"; inputs.nixpkgs.follows = "nixpkgs"; };
    niri = { url = "github:sodiboo/niri-flake"; inputs.nixpkgs.follows = "nixpkgs"; };
    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
      # NOTE: no `inputs.noctalia-qs.follows` here (there used to be one,
      # which produced a permanent "has an override for a non-existent
      # input" warning on every eval) - confirmed by fetching upstream's
      # own flake.nix directly that `noctalia-shell` has only ever
      # declared `nixpkgs` as an input, never `noctalia-qs`. The
      # standalone `noctalia-qs` input right below is a completely
      # separate, genuinely-used flake input in its own right (see
      # `noctalia-qs.enable`/`noctalia-qs.overlays.default` usages further
      # down) - only the now-removed *cross-reference* between the two
      # was dead.
    };
    noctalia-qs = { url = "github:noctalia-dev/noctalia-qs"; inputs.nixpkgs.follows = "nixpkgs"; };
    snippets-ls = { url = "github:quantonganh/snippets-ls"; inputs.nixpkgs.follows = "nixpkgs"; };
    bookokrat = { url = "github:bugzmanov/bookokrat"; inputs.nixpkgs.follows = "nixpkgs"; };
    dots-local = { url = "path:../dots-local"; };
  };

  outputs = { self, nixpkgs, nixpkgs-quarto-pin, home-manager, niri, noctalia, noctalia-qs, snippets-ls, bookokrat, dots-local, ... } @ inputs:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;

      # Formal, typed dots-local schema. Evaluates the raw dots-local flake
      # output against modules/local/schema.nix, giving every field a
      # documented default. `dotsLocal` (the evaluated config) is passed to
      # all Home Manager modules via extraSpecialArgs below, alongside (not
      # instead of) `inputs`, since some non-dots-local inputs (niri,
      # noctalia, nixgl, ...) are still read directly.
      # `dots-local` (the flake input) carries flake-introspection metadata
      # alongside its actual data fields (_type, inputs, outPath, outputs,
      # rev, sourceInfo, ...) - these must be stripped before handing it to
      # evalModules, which otherwise tries to validate them as declared
      # options and fails ("The option `_type' does not exist").
      dotsLocalData = builtins.removeAttrs dots-local [
        "_type" "inputs" "lastModified" "lastModifiedDate" "narHash"
        "outPath" "outputs" "rev" "revCount" "shortRev" "sourceInfo"
        "submodules" "dirtyRev" "dirtyShortRev"
      ];

      dotsLocalEval = lib.evalModules {
        # Wrapped as `{ config = dotsLocalData; }` (rather than passed
        # bare) to make the intent explicit to evalModules: these are
        # config values, not a module function.
        modules = [ ./modules/local/schema.nix { config = dotsLocalData; } ];
      };
      dotsLocal = dotsLocalEval.config;

      # Full, always-in-sync option reference for dots-local/flake.nix -
      # every field you can set, with its type/default/description, read
      # straight from modules/local/schema.nix's option declarations via
      # nixpkgs's own `lib.optionAttrSetToDocList` (the same machinery
      # NixOS/Home Manager use to generate their own option docs) - not a
      # hand-maintained parallel .md file that can drift from the real
      # schema. See the `dots-local-options` command
      # (modules/core/scripts.nix) for a human-readable CLI view of this.
      dotsLocalOptionsDoc =
        let
          rawDocs = lib.optionAttrSetToDocList dotsLocalEval.options;
          # Drop internal module-system plumbing every submodule level
          # carries (_module.args/check/freeformType/specialArgs) - noise,
          # not anything a dots-local author would ever set.
          isReal = o: !(lib.elem "_module" o.loc);
        in
          map (o: {
            path = lib.concatStringsSep "." o.loc;
            type = o.type;
            default = if o ? default then (o.default.text or (builtins.toJSON o.default)) else null;
            description = lib.trim (o.description or "");
          }) (builtins.filter isReal rawDocs);

        externalOverlay = final: prev: {
           external.snippets-ls = snippets-ls.packages.${prev.stdenv.hostPlatform.system}.snippets-ls;
           external.bookokrat = bookokrat.packages.${prev.stdenv.hostPlatform.system}.default.overrideAttrs (oldAttrs: {
             doCheck = false;
           });
           external.quarkdown = prev.callPackage ./pkgs/quarkdown.nix {};
           external.lazytask = prev.callPackage ./pkgs/lazytask.nix {};
           # Only quarto itself needs pinning (see the nixpkgs-quarto-pin
           # input comment above for the actual, verified reason) - pandoc
           # is NOT separately overridden here, since its version is
           # identical between this pinned revision and current unstable
           # anyway; plain `pkgs.pandoc` (main nixpkgs) is used everywhere
           # else already (tui-apps.nix, dev-tools.nix), no need to special-
           # case it.
           quarto = inputs.nixpkgs-quarto-pin.legacyPackages.${prev.stdenv.hostPlatform.system}.quarto;
         };
      tuning = import ./modules/flake/package-tuning.nix { inherit lib dotsLocal; };
      
      # Alien package helpers (need to be available early for imports)
      alien = import ./modules/flake/alien-package-specs.nix { 
          inherit lib dotsLocal; 
      };

      # Global-scope tuning packages, keyed by dotsLocal.context - the same
      # value that modules/composition.nix uses to pick a
      # contexts/<context>.nix bundle. Add an entry here if a new context
      # needs specific global-scope tuning.
      tunePackagesByContext = {
        priv = {
          ripgrep.enable = true; fd.enable = true;
          # niri.enable = true;  # Disabled - RUSTFLAGS conflict
          noctalia-qs.enable = true; ghostty.enable = true; tesseract.enable = true;
        };
        work = {};
      };
      tunePackages = tunePackagesByContext.${dotsLocal.context} or {};

      # Just an optimized/baseline build-perf axis - everything
      # context-specific is resolved internally from dotsLocal by
      # modules/composition.nix itself.
      mkHomeConfig = { optimized ? false }:
        let
          tuneOverlay = tuning.mkTuneOverlay tunePackages ./modules;
          overlays = [
            # nur.overlays.default - see the `nur`/`nixgl` comment on the
            # flake input declarations above.
            niri.overlays.niri
            noctalia-qs.overlays.default
            externalOverlay
          ]  ++ (lib.optional (tuneOverlay != null) tuneOverlay)
             ++ dotsLocal.extraOverlays;
          
          pkgs' = import nixpkgs (if optimized then { 
            # Parametrized from dotsLocal.march, so the -opt build targets
            # this machine's actual configured architecture.
            localSystem = { inherit system; gcc.arch = dotsLocal.march; gcc.tune = dotsLocal.march; }; 
            config.allowUnfree = true; inherit overlays; 
          } else { 
            config.allowUnfree = true; inherit system overlays; 
          });

          baseModules = [
            { _module.args.pkgs = lib.mkForce pkgs'; }
            noctalia.homeModules.default
            ./modules/composition.nix
            {
              home.username = dotsLocal.username;
              home.homeDirectory = dotsLocal.homeDirectory;
              programs.bash.enable = true;
              targets.genericLinux.enable = true;
            }
          ] ++ dotsLocal.extraModules;

          # Gutter Eval to capture clean HM bashrc/profile
          gutterEval = home-manager.lib.homeManagerConfiguration {
            pkgs = pkgs';
            modules = baseModules;
            extraSpecialArgs = { inherit inputs pkgs' alien dotsLocal; };
          };

        in
        home-manager.lib.homeManagerConfiguration {
          pkgs = pkgs';
          modules = baseModules ++ [
            ./modules/core/nixon.nix
          ];
          extraSpecialArgs = { 
            inherit inputs pkgs' alien dotsLocal; 
            bashrcDerivation = gutterEval.config.home.file.".bashrc".source;
            profileDerivation = gutterEval.config.home.file.".profile".source;
          };
        };

      # Bound once so both `homeConfigurations.default` and
      # `dotsContextOptionsDoc` (below) share the exact same evaluation -
      # the doc's "current" column is this machine's real, fully-resolved
      # config (not the tuned `-opt` variant, which is build-perf-only and
      # never differs in features./suites. values).
      defaultHomeConfig = mkHomeConfig { optimized = false; };

      # Full features.*/suites.* option reference - the toggle-level
      # companion to dotsLocalOptionsDoc above, generated the same way
      # (nixpkgs's own `lib.optionAttrSetToDocList`, this time over the
      # full evaluated Home Manager module tree rather than just
      # modules/local/schema.nix) so it can never drift from the real
      # options either. Unlike dotsLocalOptionsDoc, each entry also
      # carries `current` - this machine's actual resolved value (as
      # picked up from `dots-local`/rules.nix/contexts), not just the
      # option's own static declared default - since many of these
      # (suites.gui-apps.enable, features.appimages.enable, ...) are
      # `mkDefault`s computed from dotsLocal axes rather than plain
      # literals, so the declared default text alone (e.g.
      # "config.core.enableGuiDefaults") wouldn't tell you what's
      # actually enabled on this machine. See the `dots-context-options`
      # command (modules/core/scripts.nix) for a human-readable CLI view.
      dotsContextOptionsDoc =
        let
          rawDocs = lib.optionAttrSetToDocList defaultHomeConfig.options;
          # Only features.*/suites.* - everything else (home-manager's
          # own programs.*/home.*/... options) is out of scope for this
          # doc, and there's a LOT of it.
          isFeatureOrSuite = o:
            o.loc != [] &&
            builtins.elem (builtins.head o.loc) [ "features" "suites" ] &&
            !(lib.elem "_module" o.loc);
          # Some option values (functions, infinite/self-referential
          # attrsets, packages with unevaluated placeholders) can't be
          # rendered as JSON - swallow those rather than failing the
          # whole doc build.
          safeJson = v:
            let r = builtins.tryEval (builtins.toJSON v);
            in if r.success then r.value else "\"<unrepresentable>\"";
        in
          map (o: {
            path = lib.concatStringsSep "." o.loc;
            type = o.type;
            default = if o ? default then (o.default.text or (builtins.toJSON o.default)) else null;
            current = safeJson (lib.attrByPath o.loc null defaultHomeConfig.config);
            description = lib.trim (if (o.description or null) == null then "" else o.description);
          }) (builtins.filter isFeatureOrSuite rawDocs);

    in {
      # There's no "context choice" to make on the command line - it's
      # fully determined by whatever dots-local.flake.nix's `context` (and
      # other axis fields) say. `apply-dots` (no argument) / `apply-dots
      # opt` select baseline vs. optimized.
      homeConfigurations = {
        default = defaultHomeConfig;
        default-opt = mkHomeConfig { optimized = true; };
      };

      # Exposes the fully-resolved dots-local schema (all defaults filled
      # in) for introspection/debugging, e.g.:
      #   nix eval .#dotsLocal --override-input dots-local git+file://$HOME/dots-local
      #   nix eval .#dotsLocal.march --override-input dots-local git+file://$HOME/dots-local
      dotsLocal = dotsLocal;

      # Full dots-local/flake.nix option reference (path/type/default/
      # description) - see `dots-local-options` command for a formatted
      # CLI view, or query directly:
      #   nix eval --json .#dotsLocalOptionsDoc --override-input dots-local git+file://$HOME/dots-local
      dotsLocalOptionsDoc = dotsLocalOptionsDoc;

      # Full features.*/suites.* option reference (path/type/default/
      # current/description) - see `dots-context-options` command for a
      # formatted CLI view, or query directly:
      #   nix eval --json .#dotsContextOptionsDoc --override-input dots-local git+file://$HOME/dots-local
      dotsContextOptionsDoc = dotsContextOptionsDoc;
    };
}
