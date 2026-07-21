# "rescue-lua": a statically-linked (musl) Lua toolkit that keeps
# working even if the host's dynamic linker/glibc is broken (the whole
# reason for using pkgsStatic here instead of the ordinary
# suites.dev-tools.lua/luajit, which are plain dynamically-linked
# builds meant for everyday use, not disaster recovery).
#
# Ported from a rough ChatGPT/Gemini outline the user supplied, with two
# deviations forced by real build/collision failures found while
# implementing it (see memory-bank/decisions.md's dated entry for the
# full investigation):
#
# 1. `pkgsStatic.lua5_4.withPackages`/`pkgsStatic.luajit.withPackages`
#    (to bundle luafilesystem/luaposix/dkjson statically, as the
#    original outline called for) are broken upstream in nixpkgs as of
#    this writing: the static stdenv adapter unconditionally injects
#    `--enable-static --disable-shared` into every autotools-style
#    `configure` invocation, but `luarocks_bootstrap`'s own configure
#    script doesn't understand that flag and fails outright - so NO
#    static Lua library can currently be bundled via `.withPackages`,
#    regardless of which libraries are requested. Confirmed by building
#    `pkgsStatic.lua5_4.withPackages (ps: [ ps.luafilesystem ])` in
#    isolation and getting the identical "Unknown flag: --enable-static"
#    failure. Given this is an upstream nixpkgs bug (not something this
#    repo can reasonably patch around for a niche emergency toolkit),
#    the user chose to ship rescue-lua WITHOUT bundled Lua libraries -
#    bare `pkgsStatic.lua5_4`/`pkgsStatic.luajit` build and work fine on
#    their own, just without `require("lfs")`/`require("dkjson")`/etc.
#
# 2. Neither the static interpreters nor pkgsStatic.busybox/jq are
#    exposed directly under their upstream binary names in
#    home.packages, unlike the original outline's "Direct access to
#    individual static binaries if preferred" section:
#    - pkgsStatic.lua5_4 and pkgsStatic.luajit BOTH ship a `bin/lua`
#      (luajit's is a symlink to itself) - installing both raw would
#      collide with each other, AND with the ordinary dynamically-linked
#      `lua` from suites.dev-tools.lua if that's also enabled (it is, by
#      default - see modules/suites/dev-tools.nix).
#    - pkgsStatic.busybox ships ~400 applet symlinks (ls, cat, grep,
#      awk, sh, ...) that would collide catastrophically with
#      coreutils/findutils/gnugrep/gawk/etc, already installed
#      everywhere else in this repo.
#    - pkgsStatic.jq's `bin/jq` would collide with the ordinary
#      `pkgs.jq` already installed unconditionally in
#      modules/core/default.nix.
#    Since the whole point is a single memorable entrypoint anyway, only
#    the `rescue-lua` wrapper (which reaches both static interpreters via
#    absolute store paths internally, no PATH lookup involved) and
#    distinctly-renamed `rescue-busybox`/`rescue-jq` wrappers (exposing
#    busybox as its one multi-call binary - invoke applets as
#    `rescue-busybox <applet> ...`) are actually installed.
{ config, lib, pkgs, ... }:

let
  coreLib = import ../core/lib.nix { inherit lib; };
  cfg = config.features.rescue-lua;

  staticLua54 = pkgs.pkgsStatic.lua5_4;
  staticLuaJIT = pkgs.pkgsStatic.luajit;

  # Single command, `-jit`/`--jit` (anywhere in argv) switches from the
  # default Lua 5.4 engine to LuaJIT; both interpreters are reached via
  # their absolute store paths, so this never depends on $PATH at all -
  # exactly the "keep working even if everything else is broken"
  # property a rescue tool needs.
  rescueLuaWrapper = pkgs.writeShellScriptBin "rescue-lua" ''
    set -euo pipefail
    use_jit=0
    args=()
    for arg in "$@"; do
      case "$arg" in
        -jit|--jit) use_jit=1 ;;
        *) args+=("$arg") ;;
      esac
    done
    if [ "$use_jit" -eq 1 ]; then
      exec "${staticLuaJIT}/bin/luajit" "''${args[@]+"''${args[@]}"}"
    else
      exec "${staticLua54}/bin/lua" "''${args[@]+"''${args[@]}"}"
    fi
  '';

  # See the file-header comment (point 2) for why only busybox's own
  # multi-call binary is exposed, renamed, rather than its ~400 applet
  # symlinks.
  rescueBusybox = pkgs.runCommand "rescue-busybox" { } ''
    mkdir -p "$out/bin"
    ln -s "${pkgs.pkgsStatic.busybox}/bin/busybox" "$out/bin/rescue-busybox"
  '';

  # Renamed for the same collision reason (see file-header comment,
  # point 2) - pkgs.jq is already installed unconditionally elsewhere.
  rescueJq = pkgs.runCommand "rescue-jq" { } ''
    mkdir -p "$out/bin"
    ln -s "${pkgs.pkgsStatic.jq}/bin/jq" "$out/bin/rescue-jq"
  '';
in
{
  options.features.rescue-lua = {
    enable = coreLib.mkDefaultEnabledOption "rescue-lua: statically-linked (musl) Lua 5.4 + LuaJIT emergency toolkit, plus rlua/rluajit aliases";
    emergencyUtils = coreLib.mkDefaultEnabledOption "Also bundle rescue-busybox/rescue-jq (statically-linked) alongside rescue-lua";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ rescueLuaWrapper ]
      ++ lib.optionals cfg.emergencyUtils [ rescueBusybox rescueJq ];

    programs.bash.shellAliases = {
      rlua = "rescue-lua";
      rluajit = "rescue-lua --jit";
    };
  };
}
