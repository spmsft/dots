{
  khal = {
    option = "khal";
    packages = {
      pacman = [ "khal" ];
      paru = [ ];
    };
  };
  
  todoman = {
    option = "todoman";
    packages = {
      pacman = [ "todoman" ];
      paru = [ ];
    };
  };
  
  pimsync = {
    option = "pimsync";
    packages = {
      pacman = [ "pimsync" ];
      paru = [ ];
    };
  };
  
  khard = {
    option = "khard";
    packages = {
      pacman = [ "khard" ];
      paru = [ ];
    };
  };
  
  taskwarrior = {
    option = "taskwarrior";
    packages = {
      pacman = [ "task" ];
      paru = [ ];
    };
  };

  timewarrior = {
    option = "timewarrior";
    packages = {
      pacman = [ "timew" ];
      paru = [ ];
    };
  };

  # tasksh (taskshell) deliberately has NO entry here (not even an empty
  # one - collectAlienSpecs/mkEntry treat mere key-presence as "alien
  # takes precedence", so an empty-lists entry would still block the Nix
  # package with nothing to actually install). The AUR tasksh PKGBUILD
  # fails to build under this machine's Nix-provided clang/binutils
  # toolchain (linker error: "libtasksh.a: error adding symbols: archive
  # has no index; run ranlib to add one" - a toolchain mismatch, not a
  # real packaging problem) - suites.pim-apps.tasksh falls back to the
  # plain nixpkgs build (pkgs.tasksh) instead, which builds fine.

  superproductivity = {
    option = "superproductivity";
    packages = {
      pacman = [];
      paru = [ "superproductivity" ];
    };
  };
}
