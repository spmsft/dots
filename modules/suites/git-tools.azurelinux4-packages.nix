# Azure Linux 4.0 alien-package spec.
#
# Mirrors git-tools.azurelinux3-packages.nix's exact package set. Uses the
# `dnf5` manager key (Azure Linux 4 replaced tdnf with dnf5 - see
# modules/core/alien-packages.nix). Structurally ready, runtime-unverified.
{
  git = {
    packages = {
      dnf5 = [ "git" ];
    };
  };
}
