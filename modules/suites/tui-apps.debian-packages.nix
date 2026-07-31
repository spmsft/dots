# See network-tools.debian-packages.nix for the conservative-scope rationale.
# `lazygit` confirmed present in Debian's official archive (trixie/stable,
# 2026) via packages.debian.org - unlike yazi, which is only reliably
# available through unofficial third-party repos (e.g. deb.griffo.io), not
# dots's official-repos-only convention. `byobu` is deliberately NOT alien-
# routed here (nor on cachyos) - nixpkgs packages it directly and there's
# no native-integration reason to prefer the distro package for a plain
# CLI tool like this (see memory-bank/decisions.md).
{
  btop = {
    packages = {
      apt = [ "btop" ];
    };
  };

  pass = {
    packages = {
      apt = [ "pass" ];
    };
  };

  hledger = {
    packages = {
      apt = [ "hledger" ];
    };
  };
}
