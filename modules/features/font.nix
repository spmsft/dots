{ pkgs, ... }: {
  fonts.fontconfig.enable = true;

  home.packages = with pkgs; [
    nerd-fonts.iosevka-term 
    nerd-fonts.iosevka
  ];
}