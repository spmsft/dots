# Moved from tui-apps.cachyos-packages.nix (DTP section) now that these
# packages live in suites.dtp-tools.
{
  imagemagick = {
    packages = {
      pacman = [ "imagemagick" ];
    };
  };

  graphviz = {
    packages = {
      pacman = [ "graphviz" ];
    };
  };

  pandoc = {
    packages = {
      # Arch renamed the pacman package to "pandoc-cli" (it Provides/
      # Replaces the old "pandoc" name) - `pacman -Qq` reports the
      # package as installed under its real name "pandoc-cli", so
      # update-alien-packages' installed-vs-required diff (which compares
      # literal package names, not `Provides`) would otherwise think
      # "pandoc" is perpetually missing even when it's fully installed,
      # and keep re-offering to install it every run.
      pacman = [ "pandoc-cli" ];
    };
  };

  typst = {
    packages = {
      pacman = [ "typst" ];
    };
  };
}
