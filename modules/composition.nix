# The composition entry point.
#
# Always imports the common baseline + core, then:
#   1. Imports exactly one modules/contexts/<dotsLocal.context>.nix bundle
#      (the bulk, hand-authored per-context config).
#   2. Folds rules.nix's declarative axis-based rules on top,
#      as *defaults* (an explicit setting anywhere else always wins).
#   3. Imports dotsLocal.extraModules (already appended at the flake.nix
#      level too, for anything not folded through here - see flake.nix).
#
# No per-host file is required to exist for any machine - host-specific
# config is expressed via dotsLocal fields (machine.*, gpu, compositor,
# ...) consumed generically by feature modules (features/power-toggle.nix,
# features/network.nix's sshIdentityFile, rules.nix, ...), or,
# for truly bespoke needs too specific to generalize, via
# dotsLocal.extraModules (kept in the private dots-local repo, never in
# this shared one).
{ config, lib, dotsLocal, ... }:

let
  rules = import ./rules.nix { inherit lib dotsLocal; };

  contextFile = ./contexts + "/${dotsLocal.context}.nix";
  contextExists = builtins.pathExists contextFile;

  # Recursively wraps every LEAF value of a nested attrset in
  # `lib.mkDefault`, so rules.nix's `set` attrsets behave as
  # defaults at every option path they touch - not as one single
  # low-priority definition for an entire nested tree (which is not how
  # the module system's per-leaf priority resolution works). Skips
  # attrsets that are already a module-system "override" value (e.g. if a
  # rule author already wrapped a leaf explicitly with mkForce) so we don't
  # double-wrap or corrupt an existing priority annotation.
  deepMkDefault = x:
    if builtins.isAttrs x && !(x ? _type) then lib.mapAttrs (_: deepMkDefault) x
    else lib.mkDefault x;
in {
  imports = [
    ./core
    ./core/dots-local.nix
    ./core/dots-local-shell.nix
    ./core/nix-tools.nix
    ./core/scripts.nix
    ./core/alien-packages.nix
    ./core/tools-registry.nix
    ./core/tune-support.nix
    ./core/platform.nix
    ./contexts/common.nix

    # Universally imported - each module's own `enable` option, defaulting
    # to false/off, controls whether anything actually happens. Enabled
    # either by a rules.nix rule (e.g. compositor == "niri" ->
    # niri-noctalia) or directly by dotsLocal.extraModules for anything
    # more bespoke.
    ./features/power-toggle.nix
    ./features/niri-noctalia.nix
    ./features/llama-cpp.nix
    # ai-paratext: default-enabled (unlike llama-cpp above) - a core CLI
    # tool, not a machine-specific opt-in, so it's universal rather than
    # per-context.
    ./features/ai-paratext.nix
    ./features/butterfish.nix
    ./features/sd-switch.nix
    ./features/wsl-shell-integration.nix
    # opener/clipboard/notify: universal because rules.nix's `isWsl`
    # rule references features.opener/features.clipboard/features.notify
    # regardless of which context is active - a NixOS/HM module option
    # must be declared (module imported) for ANY module to set values
    # under that path, even a conditionally-false lib.mkIf.
    # contexts/work.nix doesn't import these, contexts/priv.nix does (and
    # still sets their enable/backend config there, just not the import).
    ./features/opener.nix
    ./features/clipboard.nix
    ./features/notify.nix
    ./suites/scanning.nix
    ./suites/cloud-tools.nix
    # ai-apps: same reasoning as opener/clipboard above - referenced by
    # rules.nix's `gpu == "nvidia"` rule regardless of context.
    ./suites/ai-apps.nix
    # fonts: same reasoning again - niri-noctalia.nix contributes to
    # features.fonts.required, and niri-noctalia is itself universal.
    ./features/fonts.nix
  ] ++ lib.optional contextExists contextFile;

  config = lib.mkMerge ([
    {
      assertions = [
        {
          assertion = contextExists;
          message = ''
            dotsLocal.context = "${dotsLocal.context}" has no matching
            modules/contexts/${dotsLocal.context}.nix file. Known contexts:
            ${lib.concatStringsSep ", " (builtins.attrNames (lib.filterAttrs
              (n: _: lib.hasSuffix ".nix" n) (builtins.readDir ./contexts)))}.
            Add one (see modules/contexts/work.nix for a minimal starting
            point) or fix dotsLocal.context in your dots-local/flake.nix.
          '';
        }
      ];
    }
  ] ++ (map
    (rule: lib.mkIf (rule.when dotsLocal) (deepMkDefault (rule.set dotsLocal)))
    rules));
}
