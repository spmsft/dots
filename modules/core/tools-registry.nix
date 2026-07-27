# Generic registry for "non-standard" tools: hand-rolled commands/
# scripts/functions installed by features or suites (writeShellScriptBin,
# home.file executables, bash functions in initExtra, ...) as opposed to
# plain packaged binaries that already come from a nix package or its
# alien equivalent (those are self-describing via `--help`/man pages and
# don't need a separate entry here).
#
# Any feature/suite that installs one of these should append an entry to
# `dots.tools` alongside wherever it currently installs the script itself
# (`home.packages`/`home.file`/etc.), e.g.:
#
#   config = lib.mkIf cfg.enable {
#     home.packages = [ myScript ];
#     dots.tools = [{
#       name = "my-script";
#       synopsis = "One line describing what it does.";
#       feature = "features.my-feature";
#       dotsLocalSettings = [ "machine.someField" ];  # optional
#     }];
#   };
#
# This list powers the `dots-tools` command (modules/core/scripts.nix) -
# see memory-bank/architecture.md section 12 for the "keep in sync" rule
# this establishes.
{ config, lib, ... }:

let
  toolSubmodule = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Command/function name as typed on the shell.";
      };
      synopsis = lib.mkOption {
        type = lib.types.str;
        description = "One-line description of what this tool does.";
      };
      feature = lib.mkOption {
        type = lib.types.str;
        description = ''
          Dotted config path of the feature/suite that installs this
          tool, e.g. "features.vk" or "suites.ai-apps".
        '';
      };
      dotsLocalSettings = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          dotsLocal.* fields that affect this tool's behavior or
          availability, if any (e.g. "machine.display",
          "machine.mklSupport"). Purely informational.
        '';
      };
    };
  };
in
{
  options.dots.tools = lib.mkOption {
    type = lib.types.listOf toolSubmodule;
    default = [ ];
    description = ''
      Registry of non-standard (hand-rolled, not backed by a nix package
      or its alien equivalent) commands/scripts/functions installed by
      currently active features/suites. Powers the `dots-tools` command.
    '';
  };

  config = {
    assertions = [
      {
        assertion =
          let names = map (t: t.name) config.dots.tools;
          in lib.length names == lib.length (lib.unique names);
        message =
          let
            names = map (t: t.name) config.dots.tools;
            dupes = lib.unique (lib.filter (n: lib.length (lib.filter (x: x == n) names) > 1) names);
          in "dots.tools has duplicate tool name(s), each tool must register exactly once: ${toString dupes}";
      }
    ];
  };
}
