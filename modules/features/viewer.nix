{ config, lib, pkgs, ... }:

let
  coreLib = import ../core/lib.nix { inherit lib; };
  cfg = config.features.viewer;
  sixelCfg = config.suites.sixel-tools or { enable = false; };
  
  # Check feature availability
  hasChafa = sixelCfg.enable && (sixelCfg.chafa or false);
  hasCatimg = sixelCfg.enable && (sixelCfg.catimg or false);
  hasMpv = sixelCfg.enable && (sixelCfg.mpv or false);
  
  # Image viewer preference and fallback
  preferChafa = cfg.preferImageViewer == "chafa";
  
  # Available image viewers in priority order
  imageViewer = 
    if hasChafa && preferChafa then "${pkgs.chafa}/bin/chafa"
    else if hasCatimg then "${pkgs.catimg}/bin/catimg"
    else if hasChafa then "${pkgs.chafa}/bin/chafa"
    else "${pkgs.bat}/bin/bat";
  
  # PDF viewer
  pdfViewer = "${pkgs.bat}/bin/bat";
  
  # Video viewer
  videoViewer = 
    if hasMpv then "${pkgs.mpv}/bin/mpv"
    else "${pkgs.bat}/bin/bat";
  
  # Main viewer script - the bulk of the logic lives in a real, static,
  # shellcheck-able file. This small preamble resolves the Nix-level
  # package paths / computed viewer choices into plain shell variables
  # that the static script references - keeping the actual ~290 lines of
  # viewer logic free of any Nix syntax at all.
  viewerScript = pkgs.writeShellScriptBin "v" (''
    #!/usr/bin/env bash
    BAT_BIN="${pkgs.bat}/bin/bat"
    DELTA_BIN="${pkgs.delta}/bin/delta"
    FD_BIN="${pkgs.fd}/bin/fd"
    FZF_BIN="${pkgs.fzf}/bin/fzf"
    GLOW_BIN="${pkgs.glow}/bin/glow"
    JQ_BIN="${pkgs.jq}/bin/jq"
    LSD_BIN="${pkgs.lsd}/bin/lsd"
    IMAGE_VIEWER="${imageViewer}"
    PDF_VIEWER="${pdfViewer}"
    VIDEO_VIEWER="${videoViewer}"
    ENABLE_VIDEO="${lib.boolToString cfg.enableVideo}"
    ENABLE_DIRECTORY_TREE="${lib.boolToString cfg.enableDirectoryTree}"
    ENABLE_ARCHIVES="${lib.boolToString cfg.enableArchives}"
    ENABLE_DATA_FORMATS="${lib.boolToString cfg.enableDataFormats}"
    ENABLE_FZF_PICKER="${lib.boolToString cfg.enableFzfPicker}"
  '' + builtins.readFile ./viewer/v.sh);

in
{
  options.features.viewer = {
    enable = coreLib.mkDefaultEnabledOption "Terminal file viewer with smart type detection";
    
    alias = lib.mkOption {
      type = lib.types.str;
      default = "v";
      description = "Alias name for the viewer command (default: 'v').";
    };
    
    preferImageViewer = lib.mkOption {
      type = lib.types.enum [ "chafa" "catimg" ];
      default = "chafa";
      description = "Preferred image viewer (chafa or catimg). Falls back to alternative if not available.";
    };
    
    enableVideo = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable video viewing with mpv --vo=sixel (requires features.sixel.mpv).";
    };
    
    enableDirectoryTree = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Show directory tree when viewing directories.";
    };
    
    enableArchives = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "List archive contents (.zip, .tar.gz, etc.) instead of extracting.";
    };
    
    enableDataFormats = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Pretty print data formats (.csv, .json, .yaml).";
    };
    
    enableFzfPicker = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable interactive file picker when v is called without arguments.";
    };

    ripgrepAll = coreLib.mkDefaultDisabledOption "ripgrep-all (search including PDFs and binaries)";
  };

  config = lib.mkIf cfg.enable {
    home.packages = builtins.filter (p: p != null) [
      viewerScript
      (lib.mkIf cfg.ripgrepAll pkgs.ripgrep-all)
    ];

    dots.tools = [
      {
        name = cfg.alias;
        synopsis = "Smart file viewer - picks image/pdf/video/text rendering by file type.";
        feature = "features.viewer";
        dotsLocalSettings = [ ];
      }
    ];

    # Create the alias
    programs.bash.shellAliases = {
      ${cfg.alias} = "${viewerScript}/bin/v";
    };
  };
}
