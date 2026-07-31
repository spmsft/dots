{ config, lib, pkgs, inputs, alien, ... }:

let
  cfg = config.suites.tui-apps;
  coreLib = import ../core/lib.nix { inherit lib; };
  appSet = coreLib.mkAppSet {
    inherit alien;
    apps = {
      # Core TUI apps
      btop = { enable = cfg.btop; pkg = pkgs.btop; };
      byobu = { enable = cfg.byobu; pkg = pkgs.byobu; };
      lazygit = { enable = cfg.lazygit; pkg = pkgs.lazygit; };
      yazi = { enable = cfg.yazi; pkg = pkgs.yazi; };
      pass = { enable = cfg.pass; pkg = pkgs.pass; };
      vhs = { enable = cfg.vhs; pkg = pkgs.vhs; };
      tailspin = { enable = cfg.tailspin; pkg = pkgs.tailspin; };

      # Email
      aerc = { enable = cfg.aerc; pkg = pkgs.aerc; };
      deltachat = { enable = cfg.deltachat; pkg = pkgs.deltachat-desktop; alienName = "deltachat-desktop"; };

      # Social/Utils
      posting = { enable = cfg.posting; pkg = pkgs.posting; };
      frogmouth = { enable = cfg.frogmouth; pkg = pkgs.frogmouth; };
      hledger = { enable = cfg.hledger; pkg = pkgs.hledger; };
    };
  };
in
{
  options.suites.tui-apps = {
    enable = coreLib.mkDefaultEnabledOption "Enable interactive TUI tools";

    btop = coreLib.mkDefaultEnabledOption "btop - system monitor";
    byobu = coreLib.mkDefaultEnabledOption "Byobu terminal multiplexer";
    lazygit = coreLib.mkDefaultEnabledOption "Lazygit";
    yazi = coreLib.mkDefaultEnabledOption "Yazi file manager";
    pass = coreLib.mkDefaultDisabledOption "pass (password manager)";
    vhs = coreLib.mkDefaultDisabledOption "vhs - terminal recorder";
    tailspin = coreLib.mkDefaultEnabledOption "tailspin (tspin) - log file highlighter";

    # Email
    aerc = coreLib.mkDefaultDisabledOption "aerc (terminal email client)";
    deltachat = coreLib.mkDefaultDisabledOption "DeltaChat (Delta Chat)";

    # bandwhich/gping (network-monitoring tools) moved to
    # suites.network-tools; imagemagick/graphviz/pandoc/typst (DTP tools)
    # moved to suites.dtp-tools - see those suites' own modules.

    # Social/Utils
    posting = coreLib.mkDefaultEnabledOption "posting (API client)";
    frogmouth = coreLib.mkDefaultEnabledOption "frogmouth (Markdown viewer)";
    hledger = coreLib.mkDefaultDisabledOption "hledger (accounting)";
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
    home.packages = appSet.packages;

    programs.btop = lib.mkIf cfg.btop {
      settings = {
        vim_keys = true;
        proc_sorting = "cpu lazy"; 
        proc_cmdline = true;
      };      
    };

    # NOTE: no home-manager `programs.byobu` module exists (unlike
    # zellij/tmux) - byobu config is plain files under ~/.byobu/, written
    # directly via `home.file` below, same rationale as the old zellij
    # setup (`pkgs.byobu` already provided above via `appSet`/
    # `alien.mkEntry`, alien-aware).
    home.file.".byobu/backend" = lib.mkIf cfg.byobu {
      force = true;
      # Pin the tmux backend explicitly (byobu can also drive GNU screen)
      # so behavior/keybindings are consistent across machines regardless
      # of which backend happens to be installed/first-found.
      text = "tmux\n";
    };

    home.file.".byobu/statusrc" = lib.mkIf cfg.byobu {
      force = true;
      text = ''
        # Minimal status bar - trim the noisier default segments.
        color
        disk_io
        entropy
        network
        raid
        rcs_cold_plug
        reboot_required
        release
        updates_available
        users
        wifi_quality
      '';
    };

    # Tokyo Night x solarpunk-neon crossover theme: Tokyo Night's dark
    # base palette (#1a1b26 bg / #c0caf5 fg) with neon-green/cyan
    # "growing circuitry" accents standing in for solarpunk's
    # nature-meets-tech vibe, instead of Tokyo Night's usual
    # blue/purple-only accenting. Sourced by byobu's generated tmux
    # config as the very last include, so it can freely override any
    # style set upstream (byobu's own `~/.byobu/.tmux.conf` hook point).
    home.file.".byobu/.tmux.conf" = lib.mkIf cfg.byobu {
      force = true;
      text = ''
        # Tokyo Night x solarpunk-neon crossover
        set -g status-style "bg=#1a1b26,fg=#c0caf5"

        set -g status-left-length 40
        set -g status-left "#[fg=#1a1b26,bg=#9ece6a,bold] 🌿 #S #[fg=#9ece6a,bg=#1a1b26,nobold]"

        set -g status-right-length 60
        set -g status-right "#[fg=#414868,bg=#1a1b26]#[fg=#c0caf5,bg=#414868] %H:%M #[fg=#7dcfff,bg=#414868]#[fg=#1a1b26,bg=#7dcfff,bold] %d-%b-%y "

        set -g window-status-format "#[fg=#7aa2f7,bg=#1a1b26] #I:#W "
        set -g window-status-current-format "#[fg=#1a1b26,bg=#9ece6a,bold] #I:#W "
        set -g window-status-activity-style "fg=#f7768e,bg=#1a1b26,bold"
        set -g window-status-bell-style "fg=#e0af68,bg=#1a1b26,bold"

        set -g pane-border-style "fg=#414868"
        set -g pane-active-border-style "fg=#7dcfff"

        set -g message-style "fg=#1a1b26,bg=#bb9af7,bold"
        set -g message-command-style "fg=#1a1b26,bg=#9ece6a,bold"
        set -g mode-style "fg=#1a1b26,bg=#bb9af7"

        set -g clock-mode-colour "#9ece6a"
        set -g clock-mode-style 24
      '';
    };

    programs.bash.initExtra = lib.mkIf cfg.byobu ''
      if [ -n "''${BYOBU_BACKEND:-}$TMUX" ] && [ -z "$BYOBU_HELP_SHOWN" ]; then
        export BYOBU_HELP_SHOWN=1
        echo -e '\033[1m\033[35m F2 new / F3-F4 switch / F6 detach\033[0m'
      fi
    '';

    # NOTE: no `programs.lazygit.enable = true;` here (deliberately) -
    # `lazygit` has no `settings`/shell-integration set anywhere in this
    # file, so the module would do nothing except re-add `pkgs.lazygit`
    # to home.packages a second time (already provided above via
    # `appSet`/`alien.mkEntry`, alien-aware). Confirmed via reading
    # home-manager's own lazygit.nix module source.

    # Declare alien packages for this suite
    alienPackages.enabledPackages = appSet.alienEnabled;
    })
  ];
}
