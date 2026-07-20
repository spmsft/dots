{ config, lib, pkgs, alien, ... }:

let
  cfg = config.suites.pim-apps;
  coreLib = import ../core/lib.nix { inherit lib; };
  appSet = coreLib.mkAppSet {
    inherit alien;
    apps = {
      khal = { enable = cfg.khal; pkg = pkgs.khal; };
      todoman = { enable = cfg.todoman; pkg = pkgs.todoman; };
      pimsync = { enable = cfg.pimsync; pkg = pkgs.pimsync; };
      khard = { enable = cfg.khard; pkg = pkgs.khard; };
      # nixpkgs renamed/replaced the old `taskwarrior` attribute with
      # `taskwarrior2` (still Taskwarrior 2.x, same `task` binary/pname -
      # `taskwarrior3` is the newer 3.x data-format rewrite, which tasksh
      # 1.2.0 isn't necessarily compatible with, so deliberately staying
      # on 2.x here).
      taskwarrior = { enable = cfg.taskwarrior; pkg = pkgs.taskwarrior2; };
      tasksh = { enable = cfg.tasksh; pkg = pkgs.tasksh; };
      timewarrior = { enable = cfg.timewarrior; pkg = pkgs.timewarrior; };
      superproductivity = { enable = cfg.superproductivity; pkg = pkgs.superproductivity; };
    };
  };
in {
  options.suites.pim-apps = {
    enable = coreLib.mkDefaultDisabledOption "Enable PIM (Personal Information Management) tools";
    
    khal = coreLib.mkDefaultDisabledOption "khal - calendar CLI";
    
    todoman = coreLib.mkDefaultDisabledOption "todoman - todo manager for CalDAV";
    
    pimsync = coreLib.mkDefaultDisabledOption "pimsync - sync CalDAV/CardDAV with vdirsyncer";
    
    khard = coreLib.mkDefaultDisabledOption "khard - console CardDAV client";
    
    taskwarrior = coreLib.mkDefaultEnabledOption "Taskwarrior - command line task manager";

    # taskshell (tasksh) - interactive Taskwarrior REPL/shell.
    tasksh = coreLib.mkDefaultDisabledOption "tasksh (taskshell) - interactive Taskwarrior REPL";

    timewarrior = coreLib.mkDefaultDisabledOption "Timewarrior - command line time tracker (Taskwarrior companion)";

    # lazytask (github.com/OsamaMahmood/lazytask) - a standalone lazygit-
    # style TUI for TaskChampion/Taskwarrior-compatible storage. Not in
    # nixpkgs and no AUR package exists either - built from source
    # (pkgs/lazytask.nix via rustPlatform.buildRustPackage, wired in via
    # flake.nix's externalOverlay as pkgs.external.lazytask), same
    # override mechanism as quarkdown/bookokrat/snippets-ls.
    lazytask = coreLib.mkDefaultDisabledOption "lazytask - lazygit-style TUI for TaskChampion/Taskwarrior";
    
    superproductivity = coreLib.mkDefaultDisabledOption "SuperProductivity - GUI todo app with timeboxing";
  };

  config = lib.mkIf cfg.enable {
    home.packages = appSet.packages
      ++ (with pkgs; builtins.filter (p: p != null) [
        (lib.mkIf cfg.lazytask external.lazytask)
      ]);

    # Declare alien packages as enabled
    alienPackages.enabledPackages = appSet.alienEnabled;
  };
}
