{ config, lib, pkgs, dotsLocal, ... }:
let
  coreLib = import ./lib.nix { inherit lib; };
  cfg = config.features.tune;

  # Architecture from dots-local (schema-defaulted to "native")
  march = dotsLocal.march;
  
  # Module defaults per language and mode - shared with
  # modules/flake/package-tuning.nix via modules/core/tune-defaults.nix
  moduleDefaults = import ./tune-defaults.nix { inherit march; };
  
  # Get flags: check dots-local first, fallback to module defaults
  getFlags = lang: mode:
    (dotsLocal.tune.flags.${lang}.${mode} or moduleDefaults.${lang}.${mode});
  
  # Simple language detection (KISS)
  detectLang = pkg:
    if pkg ? cargoDeps then "rust"
    else if pkg ? goPackagePath then "go"
    else if pkg ? isHaskellPackage then "haskell"
    else "c";
  
  # Package optimization function
  optimizePkg = pkg: opt:
    let
      lang = opt.lang or (detectLang pkg);
      mode = opt.mode or "default";
      # flags wins completely if set (even empty string), otherwise use mode-based flags
      flagStr = if (opt.flags or null) != null then opt.flags else (getFlags lang mode);
      
      # Apply flags based on language
      applyFlags = old: 
        if lang == "rust" then {
          RUSTFLAGS = flagStr;
        }
        else if lang == "go" then {
          GOFLAGS = flagStr;
        }
        else if lang == "haskell" then {
          configureFlags = (old.configureFlags or []) ++ [ flagStr ];
        }
        else {
          # C/C++ and default
          NIX_CFLAGS_COMPILE = flagStr;
        };
    in
      if flagStr == "" then pkg
      else pkg.overrideAttrs (old: applyFlags old);
  
  # Split packages by scope
  localPackages = lib.filterAttrs (name: opt: opt.enable && opt.scope == "local") cfg.packages;
  wrappedPackages = lib.filterAttrs (name: opt: opt.enable && opt.scope == "wrapped") cfg.packages;
  
  # Create local tuned packages list
  # Falls back to pkgs.external.<name> for from-source packages that live
  # under that namespace (e.g. lazytask, paratext) rather than as a
  # plain top-level nixpkgs attribute.
  localTunedPackages = lib.mapAttrsToList (name: opt:
    let
      pkg = pkgs.${name} or (pkgs.external.${name} or null);
    in
    if pkg == null then builtins.trace "Warning: Package '${name}' not found." null
    else optimizePkg pkg opt
  ) localPackages;
  
  # Create wrapped packages with suffix
  wrappedTunedPackages = lib.mapAttrsToList (name: opt:
    let
      pkg = pkgs.${name} or (pkgs.external.${name} or null);
      tunedPkg = optimizePkg pkg opt;
      suffix = opt.suffix or "-tuned";
      mainProgram = pkg.meta.mainProgram or name;
    in
    if pkg == null then builtins.trace "Warning: Package '${name}' not found." null
    else pkgs.runCommand "${name}${suffix}" { } ''
      mkdir -p $out/bin
      ln -s ${tunedPkg}/bin/${mainProgram} $out/bin/${mainProgram}${suffix}
      # Symlink other executables if they exist
      for exe in ${tunedPkg}/bin/*; do
        exeName=$(basename "$exe")
        if [ "$exeName" != "${mainProgram}" ]; then
          ln -s "$exe" $out/bin/"$exeName"${suffix} || true
        fi
      done
    ''
  ) wrappedPackages;
  
in {
  options.features.tune = {
    enable = coreLib.mkDefaultEnabledOption "package-specific performance tuning";
    
    packages = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          enable = coreLib.mkDefaultDisabledOption "tune this package";
          mode = lib.mkOption {
            type = lib.types.enum [ "safe" "default" "fast" ];
            default = "default";
            description = "Optimization mode";
          };
          flags = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Explicit flags (overrides mode)";
          };
          lang = lib.mkOption {
            type = lib.types.enum [ "c" "c++" "rust" "go" "haskell" "zig" ];
            default = "c";
            description = "Language for default flag selection";
          };
          scope = lib.mkOption {
            type = lib.types.enum [ "global" "local" "wrapped" ];
            default = "global";
            description = ''
              "global": Package is tuned via overlay at flake level (see flake.nix).
              "local": Package is added to home.packages with tuning (PATH shadowing).
              "wrapped": Package is wrapped with suffix (e.g., 'yazi-tuned'). 
                         Both baseline and tuned version available. Baseline wins on PATH.
              Note: For baseline profiles, global scope packages must be listed in flake.nix tunePackages.
            '';
          };
          suffix = lib.mkOption {
            type = lib.types.str;
            default = "-tuned";
            description = ''
              Suffix for wrapped scope packages (e.g., "-tuned", "-opt", "-fast").
              Only used when scope = "wrapped".
            '';
          };
        };
      });
      default = {};
      description = ''
        Packages to tune with optimization flags.
        - Global scope: Uses overlays (configured in flake.nix).
        - Local scope: Adds tuned version to home.packages (appears last for PATH priority).
        - Wrapped scope: Creates suffixed wrapper (e.g., 'yazi-tuned') for explicit use.
      '';
    };
  };
  
  config = lib.mkIf cfg.enable {
    # Add local and wrapped tuned packages to home.packages
    # Wrapped packages added last (baseline wins on PATH, explicit call needed)
    home.packages = lib.filter (x: x != null) (localTunedPackages ++ wrappedTunedPackages);
  };
}
