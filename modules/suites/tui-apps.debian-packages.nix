# See network-tools.debian-packages.nix for the conservative-scope rationale.
# `lazygit`/`byobu` confirmed present in Debian's official archive
# (trixie/stable, 2026) via packages.debian.org - unlike yazi, which is
# only reliably available through unofficial third-party repos
# (e.g. deb.griffo.io), not dots's official-repos-only convention.
{
  btop = {
    packages = {
      apt = [ "btop" ];
    };
  };

  byobu = {
    packages = {
      apt = [ "byobu" ];
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
