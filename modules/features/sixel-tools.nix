{ pkgs, ... }:

let

  # Your Sixel-enabled engine
  sixelMpvBinary = pkgs.mpv-unwrapped.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.pkg-config ];
    buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.libsixel ];
    # Use -Dlibmpv=true if you need the library, but for the binary:
    mesonFlags = (old.mesonFlags or [ ]) ++ [ "-Dsixel=enabled" ];
  });
      
in {
  home.packages = with pkgs; [
    chafa
    timg
    yt-dlp
    fontconfig
    lsix
    mpvScripts.mpris 
  ];

  programs.mpv = {
    enable = true;
    package = sixelMpvBinary;
    config = {
      vo = "sixel";
      osc = "no";
      osd-level = 0;
      osd-bar = "no";
      ytdl-format = "bestvideo[height<=720]+bestaudio/best";
      vf = "scale=-1:720";
      video-align-x = "-1";
      video-align-y = "-1";
      display-fps-override = 20;
      video-sync = "display-resample";
      framedrop = "vo";
      hwdec = "auto";
      term-status-msg = "";
    };
  };
  
  home.sessionVariables = {
    # Note: NixOS usually handles fontconfig, but for standalone Home Manager:
    FONTCONFIG_FILE = "${pkgs.fontconfig.out}/etc/fonts/fonts.conf";
    MPV_YTDL_EXE = "${pkgs.yt-dlp}/bin/yt-dlp";
  };

  home.shellAliases = {
    vimg = "chafa --format=sixel";
    vyt  = "mpv";
    vpdf = "timg -U";
  };
}