programs.bash = {
  enable = true;
  bashrcExtra = ''
    # Fix legacy Debian completion scripts breaking on missing `have` / `_have`
    _have() {
      PATH=$PATH:/usr/sbin:/sbin:/usr/local/sbin type "$1" &>/dev/null
    }
    have() {
      unset -v have
      _have "$1" && have=yes
    }
  '';
};
