{ config, lib, pkgs, alien, dotsLocal, ... }:

let
  cfg = config.suites.pim-apps;
  coreLib = import ../core/lib.nix { inherit lib; };

  # Mirrors modules/features/task-sync.nix's own url-resolution logic
  # (kept in sync manually - see that file for the canonical/fuller
  # version with its own comments) purely to decide what to print into
  # lazytask's launcher below.
  ts = dotsLocal.taskSync;
  effectiveUrl =
    if ts.url != null then ts.url
    else if ts.autoSpawnServer then "http://127.0.0.1:${toString ts.port}"
    else null;
  syncConfigured = ts.credential != null && effectiveUrl != null;

  # lazytask (v0.1.0, pinned in pkgs/lazytask.nix) has no native way to
  # load sync settings from its own config.toml, CLI flags, or env vars
  # at startup - confirmed by full source read (src/config.rs's
  # TaskwarriorConfig fields are dead/unused; TaskChampionIntegration::new
  # hardcodes sync_settings: None always; the only place sync gets
  # configured is the interactive Shift+S modal calling
  # TaskChampionIntegration::configure_sync()). Rather than just printing
  # the values for manual copy-paste every session, we vendor a small
  # patch (pkgs/patches/lazytask-env-sync.patch, applied in
  # pkgs/lazytask.nix) that makes App::new() call that same
  # configure_sync() automatically, opt-in, when three env vars are all
  # present: LAZYTASK_SYNC_SERVER_URL, LAZYTASK_SYNC_CLIENT_ID,
  # LAZYTASK_SYNC_ENCRYPTION_SECRET. See memory-bank/decisions.md for the
  # full investigation trail and rationale.
  #
  # lazytask keeps its own standalone TaskChampion replica, separate from
  # Taskwarrior CLI's ~/.task data, so it needs its own device client_id
  # (must parse as a UUID) - distinct from sync.server.client_id in
  # ~/.taskrc. We generate one on first use and persist it so it's
  # stable across launches (important for the sync server's per-device
  # snapshot/versioning), rather than regenerating a fresh one every run.
  lazytaskPkg =
    if syncConfigured then
      pkgs.writeShellScriptBin "lazytask" ''
        #!/usr/bin/env bash
        set -euo pipefail
        client_id_file="$HOME/.local/share/lazytask/client_id"
        mkdir -p "$(dirname "$client_id_file")"
        if [ ! -s "$client_id_file" ]; then
          cat /proc/sys/kernel/random/uuid > "$client_id_file"
        fi
        export LAZYTASK_SYNC_SERVER_URL=${lib.escapeShellArg effectiveUrl}
        export LAZYTASK_SYNC_CLIENT_ID="$(cat "$client_id_file")"
        export LAZYTASK_SYNC_ENCRYPTION_SECRET=${lib.escapeShellArg ts.credential}
        exec ${pkgs.external.lazytask}/bin/lazytask "$@"
      ''
    else pkgs.external.lazytask;

  appSet = coreLib.mkAppSet {
    inherit alien;
    apps = {
      khal = { enable = cfg.khal; pkg = pkgs.khal; };
      todoman = { enable = cfg.todoman; pkg = pkgs.todoman; };
      pimsync = { enable = cfg.pimsync; pkg = pkgs.pimsync; };
      khard = { enable = cfg.khard; pkg = pkgs.khard; };
      # nixpkgs renamed/replaced the old `taskwarrior` attribute with
      # `taskwarrior3` (the current 3.x series, backed by TaskChampion/
      # SQLite storage - `taskwarrior2` also exists for the legacy 2.x
      # data format, but 3.x is what's wanted here). `tasksh` only talks
      # to `task` via its CLI, not its on-disk format, so it stays
      # compatible across both series.
      taskwarrior = { enable = cfg.taskwarrior; pkg = pkgs.taskwarrior3; };
      tasksh = { enable = cfg.tasksh; pkg = pkgs.tasksh; };
      timewarrior = { enable = cfg.timewarrior; pkg = pkgs.timewarrior; };
      taskwarrior-tui = { enable = cfg.taskwarrior-tui; pkg = pkgs.taskwarrior-tui; };
      superproductivity = { enable = cfg.superproductivity; pkg = pkgs.superproductivity; };
    };
  };
in {
  options.suites.pim-apps = {
    enable = coreLib.mkDefaultDisabledOption "Enable PIM (Personal Information Management) tools";
    
    khal = coreLib.mkDefaultDisabledOption "khal - calendar CLI";
    
    todoman = coreLib.mkDefaultDisabledOption "todoman - todo manager for CalDAV";
    
    pimsync = coreLib.mkDefaultDisabledOption "pimsync - sync CalDAV/CardDAV with vdirsyncer";
    
    khard = coreLib.mkDefaultDisabledOption "khard - console CardDAV client";
    
    taskwarrior = coreLib.mkDefaultEnabledOption "Taskwarrior - command line task manager";

    # taskshell (tasksh) - interactive Taskwarrior REPL/shell.
    tasksh = coreLib.mkDefaultDisabledOption "tasksh (taskshell) - interactive Taskwarrior REPL";

    timewarrior = coreLib.mkDefaultDisabledOption "Timewarrior - command line time tracker (Taskwarrior companion)";

    # taskwarrior-tui (github.com/kdheepak/taskwarrior-tui) - a full-screen
    # TUI dashboard for Taskwarrior (task list/filter/edit/context views),
    # distinct from tasksh's REPL-style interactive shell above.
    taskwarrior-tui = coreLib.mkDefaultDisabledOption "taskwarrior-tui - full-screen TUI dashboard for Taskwarrior";

    # lazytask (github.com/OsamaMahmood/lazytask) - a standalone lazygit-
    # style TUI for TaskChampion/Taskwarrior-compatible storage. Not in
    # nixpkgs and no AUR package exists either - built from source
    # (pkgs/lazytask.nix via rustPlatform.buildRustPackage, wired in via
    # flake.nix's externalOverlay as pkgs.external.lazytask), same
    # override mechanism as quarkdown/bookokrat/snippets-ls.
    lazytask = coreLib.mkDefaultDisabledOption "lazytask - lazygit-style TUI for TaskChampion/Taskwarrior";
    
    superproductivity = coreLib.mkDefaultDisabledOption "SuperProductivity - GUI todo app with timeboxing";
  };

  config = lib.mkIf cfg.enable {
    home.packages = appSet.packages
      ++ lib.optional cfg.lazytask lazytaskPkg;

    # Declare alien packages as enabled
    alienPackages.enabledPackages = appSet.alienEnabled;
  };
}
