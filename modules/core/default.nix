{ pkgs, lib, ... }: {
  home.packages = with pkgs; [
    fresh-editor
    marksman
    ripgrep
    fd
    fzf
    zoxide
    btop
    jq
    tree
    gnupg
    pass
    pinentry-tty
    lsd
    glow
    bat
    less
    dust
    procs
    tealdeer
    doggo
    direnv
    nix-direnv
    tokei
    zellij
    lazygit
    oh-my-posh
    zellij
    delta
    opencode
    fastfetch
    gh
    rbw
    pinentry-tty
    curl
    wget
    curlie
    xh
    trippy
    bandwhich
    gping
    difftastic
    vivid
    jjui
    jj
    yazi
    uv
    bash
    bash-completion
  ];

  programs.home-manager.enable = true;
  home.stateVersion = "23.11"; 
  
  programs.lsd = {
    enable = true;
    # Force lsd to use the colors defined by the system/vivid
    colors = "unthemed"; 
  };
    
  # zoxide integration
  programs.zoxide = {
      enable = true;
      enableBashIntegration = true;
      options = [ "--cmd cd" ];
  };
  
  # FZF integration
  programs.fzf = {
      enable = true;
      enableBashIntegration = true;
      defaultCommand = "fd --type f";
      defaultOptions = [ "--height=40%" "--layout=reverse" "--border" ];
  };
  
  # bat integration
  programs.bat = {
    enable = true;
    config = {
      theme = "TwoDark"; # High-visibility for Surface screens
      italic-text = "always";
      style = "numbers,changes,header";
    };
  };
    
  # direnv integration
  programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
  };
 
  programs.btop = {
    settings = {
      # color_theme = "tokyo-night"; # Optional: matches your Posh theme
      vim_keys = true;
      proc_sorting = "cpu lazy"; 
      proc_cmdline = true; # Ensures the full command line is visible
    };      
  };
    
  programs.bash = {
    enable = true;
    enableCompletion = true;
    
    historySize = 50000;
    historyFileSize = 100000;
    historyControl = [ "ignoredups" "ignorespace" ];
    
    # 1. Always load the fallback first
    bashrcExtra = ''
      if [ -f "$HOME/.bashrc_core" ]; then
        . "$HOME/.bashrc_core"
        return
      fi
    '';

    # 2. Modern Overrides: Nix settings win over manual ones
    sessionVariables = {
      EDITOR = "fresh";
      PAGER = "bat --paging=always";
      # MANPAGER = "sh -c 'col -bx | bat -l man -p'";
      MANPAGER = "bat -l man -p";
      BAT_PAGER = "less -R";
      GLOW_PAGER = "1";
      GLOW_STYLE = "dark";
      GLOW_WIDTH  = "auto";
      FZF_CTRL_T_OPTS = "--preview 'lsd -l --color=always {}'";
    };
    
    # 3. Centralized Aliases
    shellAliases = {
      "+" = "sudo -E env \"PATH=$PATH\" ";  
      ls = lib.mkForce "lsd --group-dirs first";
      ll = lib.mkForce "lsd -l --git";
      la = lib.mkForce "lsd -la --git";
      lt = lib.mkForce "lsd --tree";
      fr = "fresh";
      cat = "bat";
      top = "btop";
      fzf = "fzf --preview 'bat --style=numbers --color=always --wrap=character {}'";
    };
    
    # 4. Extra Shell Logic (Completions, Prompts, etc.)
    initExtra = ''
      shopt -s histappend

      export LS_COLORS="$(vivid generate tokyonight-moon)"
            
      zi() {
        local dir
        dir=$(zoxide query -l | fzf \
          --preview 'lsd --tree --depth 2 {}' \
          --height=40% --reverse) && cd "$dir"
      }
      
      if command -v oh-my-posh >/dev/null 2>&1; then
        eval "$(oh-my-posh init bash --config pure)"
      fi
      
      if command -v fastfetch > /dev/null; then
        fastfetch
      fi
    '';
  };
}
