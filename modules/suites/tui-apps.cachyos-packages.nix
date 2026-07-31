{
  # TUI Apps - CachyOS native packages
  #
  # `byobu` is deliberately NOT listed here - it's AUR-only on Arch/CachyOS
  # (not in the official pacman repos), but nixpkgs packages it directly,
  # so there's no reason to pull in an AUR/paru build for a plain CLI tool
  # like this. Leaving it unlisted means `mkEntry` falls back to the nix
  # package (see memory-bank/decisions.md).
  btop = {
    packages = {
      pacman = [ "btop" ];
    };
  };

  lazygit = {
    packages = {
      pacman = [ "lazygit" ];
    };
  };

  yazi = {
    packages = {
      pacman = [ "yazi" ];
    };
  };

  pass = {
    packages = {
      pacman = [ "pass" ];
    };
  };
  
  vhs = {
    packages = {
      pacman = [ "vhs" ];
    };
  };
  
  # Email
  aerc = {
    packages = {
      pacman = [ "aerc" ];
    };
  };
  
  deltachat-desktop = {
    packages = {
      pacman = [ "deltachat-desktop" ];
    };
  };
  
  # Social/Utils
  posting = {
    packages = {
      paru = [ "posting-git" ];
    };
  };

  frogmouth = {
    packages = {
      paru = [ "frogmouth" ];
    };
  };
  
  hledger = {
    packages = {
      pacman = [ "hledger" ];
    };
  };
}
