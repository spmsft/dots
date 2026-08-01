{ pkgs, lib, inputs, config, ... }: {
options.core.nixonPreserveVars = lib.mkOption {
  type = lib.types.listOf lib.types.str;
  default = [ ];
  description = ''
    Extra environment variable names `nixon`/`nixoff` should preserve
    across their default (`-`) mode re-exec, on top of
    `dotsLocal.nixonEnvAllowlist`. Intended for *modules* that need a
    specific var to survive the environment wipe (e.g. because some
    tool they configure relies on it being set in every shell) - end
    users should prefer `dotsLocal.nixonEnvAllowlist` instead. Values
    set here are merged (module-system list concatenation) with every
    other module's contributions and with `dotsLocal.nixonEnvAllowlist`
    at the point `nixon`/`nixoff` builds their preserve list.

    Declared here (rather than in `modules/core/nixon.nix`, which is
    the module that actually consumes it) because this file, unlike
    `nixon.nix`, is part of `flake.nix`'s `baseModules` - shared with
    the separate "gutter eval" sub-evaluation used to capture a clean
    `.bashrc`/`.profile`. Any `baseModules` member (e.g. `modules/
    suites/tui-apps.nix`) can set this option; declaring it only in
    `nixon.nix` would make that gutter eval fail with "option does not
    exist" the moment such a module set a value.
  '';
};

options.core.alwaysOnPathDirs = lib.mkOption {
  type = lib.types.listOf lib.types.str;
  default = [ ];
  description = ''
    Extra absolute directories (typically a single nix-store package's
    own `bin` dir, e.g. `"''${pkgs.tmux}/bin"`) that should always be
    appended to `$PATH` in EVERY shell, regardless of `$NIXON` state -
    including a fully-stripped `nixoff` shell, which otherwise has
    nothing nix-related on `$PATH` at all (see `modules/core/
    nixon.nix`'s "THE NIXON GATEKEEPER" section).

    Unlike `~/.nix-profile/bin` (which exposes every `home.packages`
    entry at once), each entry here is a single, specific store path -
    intended for modules that want ONE particular nix-provided tool
    reachable everywhere (e.g. `byobu`/`tmux`, so they work even with
    Nix "off"), without dragging in the rest of the nix profile or
    nix tooling itself. This is safe/self-contained: a nix-store
    binary's runtime library dependencies (glibc, ncurses, etc.) are
    resolved via its own embedded RPATH, not via `$PATH` - so adding a
    directory here does not expose or require any other nix package.

    Modules should only add a path here when the corresponding nix
    package is actually in use (e.g. gated on `!alien.hasAlien` for
    that package name) - if an alien/native package provides the same
    tool instead, it's already on the host `$PATH` and needs no entry
    here.

    Declared here rather than in `modules/core/nixon.nix` for the same
    "gutter eval" reason as `core.nixonPreserveVars` above.
  '';
};

config = {
home.packages = with pkgs; [
    # --- 1. CORE UTILITIES (Pure CLI / Automation) ---
    # Fast, silent, and scriptable tools
    nh                    # Nix helper
    ripgrep               # Fast search (rg)
    fd                    # Fast find
    jq                    # JSON processor
    fx                    # JSON viewer
    tree                  # Directory hierarchy
    gnupg                 # Encryption/Signing
    rsync                 # File transfer
    nix-direnv            # Nix integration for direnv (direnv itself comes via programs.direnv.enable below)
    curl                  # HTTP client (classic)
    wget                  # File downloader
    time                  # time
    mmv                   # mmv
        
    # --- 2. ENHANCED WORKFLOW (Modern Unix Replacements) ---
    # Tools that upgrade the interactive Bash experience
    # NOTE: bash/lsd/zoxide/fzf/bat are NOT listed here even though
    # they're core tools - they come via programs.bash/lsd/zoxide/fzf/
    # bat.enable below, which already add the package; listing them
    # again here was a redundant duplicate (confirmed via `nix eval` -
    # each appeared twice in config.home.packages before this cleanup).
    bash-completion                   # Tab-completion logic
    bash-language-server              # Editing bash scripts from helix 
    simple-completion-language-server # snippets
    starship                          # Prompt engine
    less                              # Standard pager
    glow                              # Markdown renderer
    dust                              # 'du' replacement
    tokei                             # Code statistics
    fastfetch                         # System info fetch
    procs                             # 'ps' replacement
    tealdeer                          # Fast 'tldr'
    difftastic                        # Semantic diff tool (see programs.git's `difft` alias)
    vivid                             # LS_COLORS generator
    gum                               # Shell script TUI components
    dufs                              # Zero-config static file/dir HTTP server (used by features.vk)
     
    # --- 3. INTERACTIVE TUI (Full-Screen Interfaces) ---
    # Tools with persistent terminal UI/dashboards
    helix                             # Modern modal text editor
    btop                              # Resource monitor
    pinentry-tty                      # TTY-based pinentry for GPG
    # msgvault                        # Search old email
  ];
  
  home.stateVersion = "26.05"; 
  programs.home-manager.enable = true;

  # --- TOOL CONFIGURATIONS ---
  programs.lsd = { 
    enable = true; 
    colors = "unthemed"; 
  };
  
  programs.zoxide = { 
    enable = true; 
    enableBashIntegration = true; 
    options = [ "--cmd cd" ]; 
  };
  
  programs.fzf = {
    enable = true;
    enableBashIntegration = true;
    defaultCommand = "fd --type f";
    defaultOptions = [ "--height=40%" "--layout=reverse" "--border" ];
  };
  
  programs.bat = {
    enable = true;
    extraPackages = with pkgs.bat-extras; [
        batman
        batgrep
        batdiff
        batpipe
        batwatch
    ];
    config = { 
      theme = "TwoDark"; 
      italic-text = "always"; 
      style = "numbers,header,snip,changes"; 
    };
  };
  
  programs.direnv = { 
    enable = true; 
    nix-direnv.enable = true; 
  };

  # Silence direnv's default noisy multi-line ANSI status chatter
  # ("direnv: loading ~/.envrc", "direnv: using flake", per-line exports,
  # etc.) in favor of one compact colored line - purely cosmetic, but
  # applies to every machine since programs.direnv.enable is universal
  # here too (was previously a per-host xdg.configFile snippet; promoted
  # to core since there's nothing machine-specific about it).
  xdg.configFile."direnv/direnvrc".text = ''
    log_status() {
      printf "\033[32mdirenv: %s\033[0m\n" "$*" >&2
    }
  '';
  
  programs.btop.settings = { 
    vim_keys = true; 
    proc_sorting = "cpu lazy"; 
    proc_cmdline = true; 
  };

  # --- BASH SETTINGS ---
  # These are the settings that the Flake's "Gutter Eval" will capture
  # and redirect into your .bashrc-nix file.
  programs.bash = {
    enable = true;
    enableCompletion = true;
    historySize = 50000;
    historyFileSize = 100000;
    historyControl = [ "ignoredups" "ignorespace" ];

    initExtra = ''
      # Disable XON/XOFF software flow control (Ctrl-S/Ctrl-Q) on every
      # interactive terminal - Ctrl-S freezing the terminal until Ctrl-Q
      # is a near-universally unwanted legacy default, and freeing up
      # Ctrl-S is handy for e.g. incremental-search keybindings. Guarded
      # on an actual tty so this is a no-op if .bashrc ever gets sourced
      # non-interactively (e.g. from a script).
      [[ -t 0 ]] && stty -ixon

      # Home Manager sources ~/.nix-profile/etc/profile.d/{nix.sh,
      # hm-session-vars.sh} itself (confirmed live in the generated
      # .bashrc-nix), but only AFTER this initExtra block's own content -
      # so `starship` (installed via home.packages, living only in
      # ~/.nix-profile/bin) isn't guaranteed to be on $PATH yet here.
      # Prepend it ourselves first - idempotent, so .bashrc-nix's own
      # later sourcing just re-adds the same already-present entry
      # (matching the existing, documented double-nix.sh-sourcing quirk
      # elsewhere - see modules/core/nixon.nix).
      case ":$PATH:" in
        *":$HOME/.nix-profile/bin:"*) ;;
        *) export PATH="$HOME/.nix-profile/bin:$PATH" ;;
      esac

      if [[ "$TERM" == "linux" ]]; then
        export STARSHIP_CONFIG=~/.config/starship_minimal.toml
      else
        export STARSHIP_CONFIG=~/.config/starship.toml
      fi
      eval "$(starship init bash)"
    '';

    sessionVariables = {
      FZF_CTRL_T_OPTS = "--preview 'lsd -l --color=always {}'";
    };
    
    shellAliases = {
      "+" = "sudo -E env \"PATH=$PATH\" ";  
      apply = "apply-dots";
      ls = lib.mkForce "lsd --group-dirs first --git";
      ll = lib.mkForce "lsd --group-dirs first -l --git";
      la = lib.mkForce "lsd --group-dirs first -a --git";
      lt = lib.mkForce "lsd --tree --git";
    };
  };
};
}
