{ pkgs, ... }: {
  # This only applies to the user-level systemd
  systemd.user.enable = true;

  # This makes Home Manager more aggressive about 
  # starting services after a 'switch'
  systemd.user.startServices = "sd-switch"; 
}
