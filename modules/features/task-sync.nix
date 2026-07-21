# Taskwarrior/TaskChampion sync tooling: always installs the
# taskchampion-sync-server binary (available on PATH regardless of
# autoSpawnServer, mirroring features.vk's "always available" precedent),
# optionally runs it as a systemd --user service, optionally runs `task
# sync` on a timer, and - the part that actually wires a client up to a
# server - hooks `sync.server.url`/`sync.encryption_secret` into
# ~/.taskrc via a filter+append model (strip any previously-written
# dots-managed block, then re-append a fresh one) so none of the user's
# own hand-written taskrc settings (or Taskwarrior's own first-run
# auto-init of data.location/news.version) are ever clobbered.
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

  # Sync is only actually wired into ~/.taskrc once both a server URL and
  # the shared encryption credential are known - either alone is
  # meaningless (a URL with no credential can't authenticate/decrypt;
  # a credential with no URL has nowhere to sync to).
  syncConfigured = ts.credential != null && effectiveUrl != null;

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
          awk -v b=${lib.escapeShellArg beginMarker} -v e=${lib.escapeShellArg endMarker} '
            $0==b {skip=1; next}
            $0==e {skip=0; next}
            !skip {print}
          ' "$TASKRC" > "$TASKRC.dots-tmp" && mv "$TASKRC.dots-tmp" "$TASKRC"
        fi
        ${lib.optionalString syncConfigured ''
        cat >> "$TASKRC" <<'TASKRC_EOF'
${beginMarker}
sync.server.url=${effectiveUrl}
sync.encryption_secret=${ts.credential}
${endMarker}
TASKRC_EOF
        ''}
      fi
    '';
  };
}
