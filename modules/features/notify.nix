{ config, lib, pkgs, ... }:

let
  coreLib = import ../core/lib.nix { inherit lib; };
  cfg = config.features.notify;
  # Shared, derived value (modules/core/platform.nix) - same convention
  # as features.clipboard/features.opener.
  backend = config.core.platformBackend;

in
{
  options.features.notify = {
    enable = coreLib.mkDefaultDisabledOption "Cross-platform desktop/toast notification feature (notify-send on Linux, Windows toast on WSL, osascript on macOS)";
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = backend != null;
        message = ''
          features.notify.enable requires a non-null
          config.core.platformBackend (no compositor and not WSL - see
          modules/core/platform.nix). Set dotsLocal.compositor/isWsl
          appropriately, or leave features.notify disabled on a CLI-only
          host.
        '';
      }
    ];

    home.packages = [
      # The bulk of this logic lives in a real, static, shellcheck-able
      # file (mirrors features.clipboard's clipboard.sh) - this small
      # preamble resolves the Nix-level package paths / backend into
      # plain shell variables the static script references. Unlike
      # clipboard's functions (only sourced into interactive bash), this
      # is a real installed binary - notifications are just as useful
      # from scripts/cron/other shells as from an interactive prompt.
      (pkgs.writeShellScriptBin "notify" (''
        set -euo pipefail
        NOTIFY_BACKEND="${backend}"
        NOTIFY_SEND_BIN="${pkgs.libnotify}/bin/notify-send"
        NOTIFY_TOAST_PS1="${./notify/toast.ps1}"
      '' + builtins.readFile ./notify/notify.sh))
    ] ++ lib.optionals (backend == "wayland" || backend == "x11") [ pkgs.libnotify ];
  };
}
