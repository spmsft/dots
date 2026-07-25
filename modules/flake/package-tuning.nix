{ lib, dotsLocal }:

let
  collectTuneSpecsFiles = dir:
    let
      entries = builtins.readDir dir;
      names = builtins.attrNames entries;
    in builtins.concatLists (map (name:
      let ty = entries.${name}; p = dir + "/${name}";
      in if ty == "directory" then collectTuneSpecsFiles p
         else if ty == "regular" && lib.hasSuffix ".tune-specs.nix" name then [ p ]
         else [ ]
    ) names);

  # Shared with modules/core/tune-support.nix via modules/core/tune-defaults.nix.
  moduleDefaults = march: import ./../core/tune-defaults.nix { inherit march; };

in {
  mkTuneOverlay = tunePackages: rootDir:
    let
      tuneSpecsFiles = collectTuneSpecsFiles rootDir;
      tuneSpecs = lib.foldl' (acc: p: acc // (import p)) {} tuneSpecsFiles;
      enabled = lib.filterAttrs (_: v: (v.enable or false) == true) tunePackages;
      enabledWithSpecs = lib.mapAttrs (name: v: (tuneSpecs.${name} or {}) // (builtins.removeAttrs v [ "enable" ])) enabled;
      # Reads dotsLocal.march directly, which the schema defaults to
      # "native" - dots-local machines that set march explicitly (e.g.
      # chromaden's "znver5") get that; machines that don't get the safer
      # "native" default instead of a specific-CPU string that would fail
      # to build on anything but that exact chip.
      march = dotsLocal.march;
      defaults = moduleDefaults march;
    in
    if enabledWithSpecs == {} then null
    else final: prev:
      lib.mapAttrs (name: opt:
        let
          # Falls back to prev.external.<name> for from-source packages
          # that live under that namespace (e.g. lazytask, textinfer)
          # rather than as a plain top-level nixpkgs attribute.
          pkg = prev.${name} or (prev.external.${name} or null);
          getFlags = lang: mode: (dotsLocal.tune.flags.${lang}.${mode} or defaults.${lang}.${mode});
          # Matches tune-support.nix's detectLang, so global-scope tuning
          # can auto-detect Go/Haskell packages too, not just Rust.
          detectLang = p:
            if p ? cargoDeps then "rust"
            else if p ? goPackagePath then "go"
            else if p ? isHaskellPackage then "haskell"
            else "c";
          lang = opt.lang or (if pkg != null then detectLang pkg else "c");
          mode = opt.mode or "default";
          flagStr = if (opt.flags or null) != null then opt.flags else (getFlags lang mode);
        in
        if pkg == null || !lib.isDerivation pkg then pkg
        else pkg.overrideAttrs (old: if lang == "rust" then { RUSTFLAGS = flagStr; } else { NIX_CFLAGS_COMPILE = (old.NIX_CFLAGS_COMPILE or "") + " " + flagStr; })
      ) enabledWithSpecs;
}