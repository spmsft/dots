{ config, lib, pkgs, inputs, alien, dotsLocal, ... }:

let
  cfg = config.suites.tui-apps;
  coreLib = import ../core/lib.nix { inherit lib; };

  # Root cause of the "byobu launches into a stale/wrongly-themed
  # session, and exiting cycles through several more before it finally
  # quits" symptom (confirmed by reading byobu's own launcher source,
  # `$BYOBU_PREFIX/bin/.byobu`): byobu's plain `byobu` (no args) first
  # runs `tmux list-sessions`, and if ANY session already exists on the
  # (plain, default-socket) tmux server, it execs `byobu-select-session`
  # to attach one of them INSTEAD OF creating a new session - it never
  # creates fresh once at least one session is already running. Because
  # tmux only *applies* `set -g <style>` options (like this file's
  # `.tmux.conf` theme) at the moment a session is created/sources its
  # config - never retroactively to sessions already running on a still-
  # alive server - every session created by an earlier `byobu` launch
  # (e.g. from before this theme existed, or from a mid-iteration
  # version of it) keeps rendering with whatever config was live AT THE
  # TIME it was first created, forever, until that specific session is
  # killed. Repeated manual `byobu` launches across iterating on this
  # theme silently accumulate exactly these stale sessions on the
  # server, and `byobu-select-session` cycles through them one-by-one on
  # exit - which looks like "nested"/inconsistently-themed byobu
  # instances, but is really just several old, never-cleaned-up sessions
  # with different vintages of this same config baked in.
  #
  # Fix: a small opt-in helper (never run automatically/silently - that
  # would risk killing unrelated real work in other byobu sessions) that
  # kills the whole backing tmux server, so the next plain `byobu`
  # launch is guaranteed to create one fresh session using whatever the
  # CURRENT `.tmux.conf`/backend look like. Registered in the `dots-tools`
  # registry (see modules/core/tools-registry.nix) so it's discoverable.
  byobuReset = pkgs.writeShellScriptBin "byobu-reset" ''
    set -euo pipefail
    echo "This will terminate ALL byobu/tmux sessions (backing tmux server) so the next 'byobu' launch starts fresh with the current theme/config." >&2
    read -r -p "Continue? [y/N] " reply
    case "$reply" in
      y|Y|yes|YES) ;;
      *) echo "Aborted." >&2; exit 1 ;;
    esac
    ${pkgs.tmux}/bin/tmux kill-server 2>/dev/null || true
    echo "Done - all byobu sessions cleared." >&2
  '';

  appSet = coreLib.mkAppSet {
    inherit alien;
    apps = {
      # Core TUI apps
      btop = { enable = cfg.btop; pkg = pkgs.btop; };
      byobu = { enable = cfg.byobu; pkg = pkgs.byobu; };
      # nixpkgs's `byobu` derivation deliberately does NOT bundle/depend on
      # `tmux` (it just execs whatever `tmux` it finds on $PATH at
      # runtime, confirmed via `nix-store -q --requisites` on the built
      # byobu closure - empty) - so without this, byobu silently falls
      # back to using the system/paru-installed `tmux` binary if one
      # happens to be on $PATH, defeating the earlier "no AUR/native
      # build needed for a plain CLI tool" decision. Same toggle
      # (`cfg.byobu`) since tmux is only ever used here as byobu's
      # backend.
      tmux = { enable = cfg.byobu; pkg = pkgs.tmux; };
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
    home.packages = appSet.packages ++ lib.optional cfg.byobu byobuReset;

    dots.tools = lib.optional cfg.byobu {
      name = "byobu-reset";
      synopsis = "Kill the byobu-backed tmux server (prompts first) so the next 'byobu' launch starts one fresh session with the current theme/config, instead of attaching to an old stale one.";
      feature = "suites.tui-apps.byobu";
    };

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
      #
      # MUST be `BYOBU_BACKEND=tmux`, NOT a bare `tmux` - this file is
      # `.`-sourced as a shell script by byobu's own
      # lib/byobu/include/dirs (and elsewhere). A bare `tmux` line is
      # therefore *executed as a command*, launching a nested tmux/byobu
      # session from deep inside byobu's own startup script every single
      # time this file is sourced - this was the actual root cause of the
      # long-standing "byobu re-launches itself 2-3 times with a
      # different theme each time on exit" bug (see memory-bank/
      # decisions.md's dated entry - confirmed via a `set -x`-instrumented
      # pty trace of byobu-janitor showing `+++ tmux` firing mid-script).
      # Same class of bug as the removed `statusrc` file mentioned below.
      text = "BYOBU_BACKEND=tmux\n";
    };

    # NOTE: deliberately no `~/.byobu/statusrc` here (there was one, briefly
    # - removed after it broke shell startup, see memory-bank/decisions.md's
    # dated entry). `statusrc` is a bash-*sourced* file for overriding
    # variables like `MONITORED_DISK`/`NETWORK_UNITS` (see byobu's own
    # /usr/share/byobu/status/statusrc template) - it is NOT a plain list of
    # segment names to enable, which is what the removed file wrongly
    # contained (bare words like `disk_io` got executed as commands: "line
    # 3: disk_io: command not found"). Segment enable/disable is actually
    # `~/.byobu/status`'s `tmux_left`/`tmux_right` variables (`#`-prefix to
    # disable a segment) - but that mechanism is moot here anyway, since
    # the `status-left`/`status-right` set below in `.tmux.conf` already
    # fully replace byobu's dynamic segment-driven status line with a
    # minimal static one (session/clock/date only), which was the original
    # "trim the noisy default segments" goal.

    # Tokyo Night x solarpunk-neon crossover theme: Tokyo Night's dark
    # base palette (#1a1b26 bg / #c0caf5 fg) with neon-green/cyan
    # "growing circuitry" accents standing in for solarpunk's
    # nature-meets-tech vibe, instead of Tokyo Night's usual
    # blue/purple-only accenting. Sourced by byobu's generated tmux
    # config as the very last include, so it can freely override any
    # style set upstream (byobu's own `~/.byobu/.tmux.conf` hook point).
    # The ░▒▓ gradient blocks are plain Unicode (Block Elements, U+2591-
    # 2593) - no patched/Nerd Font glyphs required - used as a fading
    # "dissolve" transition between segment colors; 🌿/🌱/⚡/🕐 emoji lean
    # into the solarpunk (nature) x neon (energy) crossover.
    #
    # Keybindings are deliberately untouched: every directive below is a
    # cosmetic `set -g <style/format-option>` (status/window-status/pane-
    # border/message/mode/clock-mode styles+formats) - none of them are
    # `bind-key`/`unbind-key`/`set -g prefix`/`set -g mode-keys`/
    # `set -g status-keys`, so byobu's own F2-F12 shortcuts and prefix
    # key (set via bind-key in byobu's packaged config, sourced before
    # this file) are unaffected. Keep any future additions to this file
    # style-only for the same reason.
    home.file.".byobu/.tmux.conf" = lib.mkIf cfg.byobu {
      force = true;
      text = ''
        # Tokyo Night x solarpunk-neon crossover
        set -g status-style "bg=#1a1b26,fg=#c0caf5"

        set -g status-left-length 40
        set -g status-left "#[fg=#1a1b26,bg=#9ece6a,bold] 🌿⚡ #S #[fg=#9ece6a,bg=#1a1b26,nobold]░▒▓#[default]"

        set -g status-right-length 60
        set -g status-right "#[fg=#1a1b26,bg=#1a1b26]░▒▓#[fg=#c0caf5,bg=#414868] 🕐 %H:%M #[fg=#414868,bg=#7dcfff]▓▒░#[fg=#1a1b26,bg=#7dcfff,bold] 🌱 %d-%b-%y "

        set -g window-status-format "#[fg=#7aa2f7,bg=#1a1b26] ○ #I:#W "
        set -g window-status-current-format "#[fg=#1a1b26,bg=#9ece6a,bold] ➤ #I:#W "
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

    programs.bash.initExtra = lib.mkIf cfg.byobu (''
      if [ -n "''${BYOBU_BACKEND:-}$TMUX" ] && [ -z "$BYOBU_HELP_SHOWN" ]; then
        export BYOBU_HELP_SHOWN=1
        echo -e '\033[1m\033[35m F2 new / F3-F4 switch / F6 detach\033[0m'
      fi
    '' + lib.optionalString dotsLocal.isWsl ''

      # WSL's DrvFs (Windows-mounted /mnt/c/... paths) can intermittently
      # make getcwd() fail (bash's "shell-init: error retrieving current
      # directory" warning - seen when launching byobu/tmux from such a
      # directory, requiring several Ctrl-D's to unwind the resulting
      # broken nested shells). Guard the `byobu` invocation itself: if the
      # shell's own cwd is currently unreadable, fall back to $HOME (the
      # native WSL Linux filesystem, not /mnt/c) before entering byobu.
      byobu() {
        if ! builtin pwd >/dev/null 2>&1; then
          cd "$HOME" 2>/dev/null || cd /
        fi
        command byobu "$@"
      }
    '');

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
