{ pkgs, ... }: {
  imports = [
    ../../modules/core 
    ../../modules/features/sd-switch.nix
    ../../modules/features/sixel-tools.nix
    ../../modules/features/rust.nix
  ];

  home.packages = with pkgs; [ 
      azure-cli
      xclip
      # git-credential-manager
      # python312Packages.markitdown
      # github-copilot-cli
  ];

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true;
      line-numbers = true;
      side-by-side = true;
    };
  };

  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "stepn";
        email = "splantikow@microsoft.com";
      };
      core = {
        autocrlf = "input";
      };
      # credential = {
      #   helper = "manager";
      # } ;
    };
  };

  services.ssh-agent.enable = true;
  services.gpg-agent = {
    enable = true;
    pinentry.package = pkgs.pinentry-tty;
    defaultCacheTtl = 86400;
    maxCacheTtl = 604800;
  };
  
  home.sessionVariables = {
    ORGANIZATION = "Microsoft";
    GDK_SCALE = "2";
    WLR_BACKEND = "wayland";
    SSH_AUTH_SOCK = "$XDG_RUNTIME_DIR/ssh-agent.socket";
  };


  programs.bash = {
      enable = true;
      shellAliases = {
        copy = "xclip -selection clipboard";
        paste = "xclip -selection clipboard -o"; 
      };
      initExtra = ''
        export GPG_TTY=$(tty)
        # Force WSL to look for the Wayland socket if it's missing
        if [ -z "$WAYLAND_DISPLAY" ]; then
          export WAYLAND_DISPLAY="wayland-0"
        fi
        
        # if command -v github-copilot-cli > /dev/null; then
        #   eval "$(github-copilot-cli alias -- bash)"
        # fi
      '';
  };
}
