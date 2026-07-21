# Taskwarrior/TaskChampion sync tooling: always installs the
# taskchampion-sync-server binary (available on PATH regardless of
# autoSpawnServer, mirroring features.vk's "always available" precedent),
# optionally runs it as a systemd --user service, optionally runs `task
# sync` on a timer, and - the part that actually wires a client up to a
# server - hooks `sync.server.url`/`sync.server.client_id`/
# `sync.encryption_secret` into ~/.taskrc via a filter+append model
# (strip any previously-written dots-managed block, then re-append a
# fresh one) so none of the user's own hand-written taskrc settings (or
# Taskwarrior's own first-run auto-init of data.location/news.version)
# are ever clobbered.
#
# CORRECTION (2026-07-21, take 2): the first correction here (see
# memory-bank/decisions.md) fixed the "client_id required" error by
# generating a random per-machine UUID - but that was ALSO wrong.
# `sync.server.client_id` identifies your shared TASK LIST, not a
# device/replica (see task-sync(5): "a client ID identifying your
# tasks" - singular/possessive). Every replica that should merge into
# the same task list - another machine's `task` CLI, or lazytask's own
# separate local replica on THIS machine - must use the SAME client_id
# (now dotsLocal.taskSync.clientId, generated once by setup.sh, copied
# manually to every dotsLocal that should share this list), not a
# freshly-generated one per machine/app. Confirmed by observing
# `task sync` report "Success!" yet `task list` stay empty even after
# lazytask had pushed real data to the same server: the CLI and
# lazytask were syncing under two different client_ids, so the server
# treated them as two entirely separate, unrelated task lists despite
# sharing a URL and encryption_secret.
{ config, lib, pkgs, dotsLocal, ... }:

let
  coreLib = import ../core/lib.nix { inherit lib; };
  cfg = config.features.task-sync;
  ts = dotsLocal.taskSync;

  # See dotsLocal.taskSync.url's description: null defers to a computed
  # loopback default only when this machine hosts its own server (the
  # client and server are the same host in that case, so loopback is
  # always correct here regardless of what `interface` the server itself
  # binds to for OTHER machines).
  effectiveUrl =
    if ts.url != null then ts.url
    else if ts.autoSpawnServer then "http://127.0.0.1:${toString ts.port}"
    else null;

  # Sync is only actually wired into ~/.taskrc once a server URL, the
  # shared client id, AND the shared encryption credential are all
  # known - any one alone is meaningless (see dotsLocal.taskSync's
  # option descriptions for why all three are required together).
  syncConfigured = ts.credential != null && ts.clientId != null && effectiveUrl != null;

  beginMarker = "# >>> dots-managed taskwarrior sync (modules/features/task-sync.nix) >>>";
  endMarker = "# <<< dots-managed taskwarrior sync <<<";
in
{
  options.features.task-sync = {
    enable = coreLib.mkDefaultEnabledOption "Taskwarrior/TaskChampion sync tooling (taskchampion-sync-server binary, optional auto-spawned server + periodic sync timer, and the ~/.taskrc sync hook)";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.taskchampion-sync-server ];

    # Auto-launched via systemd --user (WantedBy default.target), not a
    # shell-startup hook - comes up automatically on login/session start
    # and is supervised/restarted by systemd like any other user service.
    systemd.user.services.taskchampion-sync-server = lib.mkIf ts.autoSpawnServer {
      Unit = {
        Description = "TaskChampion sync server (Taskwarrior sync backend)";
        After = [ "network.target" ];
      };
      Service = {
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %h/.local/share/taskchampion-sync-server";
        ExecStart = "${pkgs.taskchampion-sync-server}/bin/taskchampion-sync-server --listen ${ts.interface}:${toString ts.port} --data-dir %h/.local/share/taskchampion-sync-server";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "default.target" ];
    };

    # Periodic `task sync` - only installed at all when an interval is
    # actually requested ("never" is the default and installs nothing).
    # References pkgs.taskwarrior3 directly (rather than relying on
    # `task` already being on $PATH) so the timer works even if
    # suites.pim-apps.taskwarrior happens to be disabled somewhere, or
    # systemd --user's minimal environment doesn't include home-manager's
    # session PATH.
    systemd.user.services.task-sync = lib.mkIf (ts.syncInterval != "never") {
      Unit.Description = "Run `task sync` (Taskwarrior/TaskChampion)";
      Service = {
        Type = "oneshot";
        ExecStart = "${pkgs.taskwarrior3}/bin/task sync";
      };
    };

    systemd.user.timers.task-sync = lib.mkIf (ts.syncInterval != "never") {
      Unit.Description = "Periodic Taskwarrior sync timer";
      Timer = {
        OnStartupSec = "5m";
        OnUnitActiveSec = ts.syncInterval;
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };

    home.activation.hookTaskrcSync = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      TASKRC="$HOME/.taskrc"
      # Only touch a taskrc that already exists - if Taskwarrior has
      # never been run on this machine yet, ~/.taskrc doesn't exist, and
      # creating one ourselves would pre-empt Taskwarrior's own
      # first-run auto-init (which writes data.location/news.version,
      # among other things, ONLY when the file is entirely missing).
      # Run `task` once to let it create its own default taskrc, then
      # the next `apply-dots` activation will pick it up here.
      if [ -f "$TASKRC" ]; then
        if grep -qF ${lib.escapeShellArg beginMarker} "$TASKRC"; then
          # NOTE: home-manager's activation script PATH is a minimal,
          # hand-picked set (bash/coreutils/diffutils/findutils/gettext/
          # gnugrep/gnused/jq/ncurses - see the generated activate
          # script's own `export PATH=` line) that does NOT include
          # `awk` at all. Referencing bare `awk` here silently failed
          # every real activation ("command not found" -> empty
          # redirect target -> `&&` short-circuits the `mv`, so the
          # strip step was a silent no-op while the append below kept
          # running regardless) - discovered by comparing a manual
          # interactive-shell run (which has a normal $PATH and "worked")
          # against the real activation-script run (which didn't), and
          # confirmed by finding a stray empty "$TASKRC.dots-tmp" left
          # behind. Reference gawk's absolute store path instead of
          # relying on $PATH, to avoid depending on activation's PATH
          # ever growing an `awk` again.
          ${pkgs.gawk}/bin/awk -v b=${lib.escapeShellArg beginMarker} -v e=${lib.escapeShellArg endMarker} '
            $0==b {skip=1; next}
            $0==e {skip=0; next}
            !skip {print}
          ' "$TASKRC" > "$TASKRC.dots-tmp" && mv "$TASKRC.dots-tmp" "$TASKRC"
        fi
        ${lib.optionalString syncConfigured ''
        cat >> "$TASKRC" <<TASKRC_EOF
${beginMarker}
sync.server.url=${effectiveUrl}
sync.server.client_id=${ts.clientId}
sync.encryption_secret=${ts.credential}
${endMarker}
TASKRC_EOF
        ''}
      fi
    '';
  };
}

