# "priv" context bundle - personal Linux environment.
#
{ pkgs, lib, config, dotsLocal, ... }:

let
  enableGuiDefaults = config.core.enableGuiDefaults;
in {

  imports = [
    ../../modules/features/bookokrat.nix
    ../../modules/features/quarkdown.nix
  ];

  features.opener.alias = lib.mkDefault "o";

  suites.ai-apps = {
    enable = true;
  };

  features.tune = {
      enable = true;
      packages = {
        ripgrep = { enable = true; mode = "fast"; lang = "rust"; scope = "global"; };
        fd = { enable = true; mode = "fast"; lang = "rust"; scope = "global"; };

        # tesseract = { enable = true; mode = "fast"; lang = "c"; scope = "global"; };
        # simple-scan = { enable = false; mode = "fast"; lang = "c"; scope = "global"; };
        # gscan2pdf = { enable = false; mode = "fast"; lang = "c"; scope = "global"; };

        # Example: Wrapped scope with custom suffix (both baseline and tuned available)
        # yazi baseline on PATH, yazi-tuned available for explicit calls
        # yazi = {
        #  enable = true;
        #  mode = "fast";
        #  lang = "rust";
        #  scope = "wrapped";
        #  suffix = "-tuned";  # Optional, defaults to "-tuned"
        # };
      };
  };

  features.viewer = {
      enable = true;
      alias = "v";  # Use 'v' to view files in terminal
      ripgrepAll = true;
      preferImageViewer = "chafa";  # "chafa" or "catimg"
      enableVideo = true;           # Use mpv for video files
      enableDirectoryTree = true;   # lsd --tree for directories
      enableArchives = true;        # List archive contents
      enableDataFormats = true;     # Pretty print JSON/CSV/YAML
      enableFzfPicker = true;       # Interactive picker when no args
  };
  
  suites.network-tools = {
      bandwhich = true;
      curlie = true;
  };

  suites.cloud-tools = {
      rclone = true;
  };

  suites.git-tools = {
      jj = true;
      gitCredentialManager = true;
  };

  suites.dev-tools = {
      rust = true;
      haskell = true;
      python = true;
      xml = true;
      egglog = true;
      steel = true;
      mkcert = true;
      prettier = true;
  };

  # suites.dtp-tools.mystmd now defaults true whenever the suite itself
  # is enabled (modules/suites/dtp-tools.nix) - no longer needs stating
  # here.

  suites.pim-apps = {
      enable = true;
      superproductivity = enableGuiDefaults;
  };

  features.bookokrat = {
      enable = true;
    };
}

