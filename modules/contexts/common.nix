{ ... }:

{
  imports = [
    ../features/viewer.nix
    ../features/network.nix
    ../features/appimages.nix
    ../features/vk.nix
    ../features/task-sync.nix

    ../suites/network-tools.nix
    ../suites/git-tools.nix
    ../suites/dev-tools.nix
    ../suites/dtp-tools.nix
    ../suites/tui-apps.nix
    ../suites/gui-apps.nix
    ../suites/sixel-tools.nix
    ../suites/pim-apps.nix
  ];

  # pim-apps was previously priv-only (personal calendar/contacts); the
  # Taskwarrior-companion subset (tasksh/timewarrior/lazytask) is useful
  # in any context, so the suite itself is now enabled universally here,
  # with only those three tools defaulted on (khal/todoman/pimsync/khard/
  # superproductivity stay opt-in, still context-specific).
  suites.pim-apps = {
    enable = true;
    tasksh = true;
    timewarrior = true;
    lazytask = true;
    taskwarrior-tui = true;
  };
}
