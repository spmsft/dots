# Shared catalog of host-local (runtime, not Nix-store-imported) AppImage
# definitions for the "priv" context. Definitions live here (file
# pattern/command/desktopName/categories) so machines don't need to
# copy-paste the same app metadata into their own dots-local repos -
# dots-local should only need to *enable* an app (and, if a machine
# genuinely needs it, override a specific field - see
# modules/features/appimages.nix's `lib.recursiveUpdate` merge).
#
# Every entry here defaults `enable = false;` deliberately: cataloging an
# app here does NOT install it anywhere - a machine's dots-local must
# explicitly turn it on, e.g. in dots-local/appimages.nix:
#   { tuta.enable = true; }
{
  tuta = {
    file = "Tuta_Mail-*.AppImage";
    desktopName = "Tuta Mail";
    categories = [ "Network" "Email" ];
    command = "tuta";
    enable = false;
  };

  chatbox = {
    file = "Chatbox-*.AppImage";
    desktopName = "ChatBox";
    categories = [ "Network" "Chat" ];
    command = "chatbox";
    enable = false;
  };

  tolaria = {
    file = "Tolaria*.AppImage";
    desktopName = "Tolaria";
    command = "tolaria";
    # Enabled by default whenever this machine has a real GUI - see the
    # `features.appimages.apps.tolaria.enable` cross default in
    # modules/features/appimages.nix, which always wins over this
    # manifest-level value (mkDefault there is still overridable per
    # dots-local/host.nix).
  };

  steam = {
    file = "Steam-*.AppImage";
    desktopName = "Steam";
    categories = [ "Game" ];
    command = "steam";
    enable = false;
  };

  betterbird = {
    file = "Betterbird-*.AppImage";
    desktopName = "Betterbird";
    categories = [ "Network" "Email" ];
    command = "betterbird";
    enable = false;
  };

  buttercup = {
    file = "Buttercup-*.AppImage";
    desktopName = "Buttercup";
    categories = [ "Utility" "Security" ];
    command = "buttercup";
    enable = false;
  };

  discord = {
    file = "Discord-*.AppImage";
    desktopName = "Discord";
    categories = [ "Network" "Chat" ];
    command = "discord";
    enable = false;
  };
}
