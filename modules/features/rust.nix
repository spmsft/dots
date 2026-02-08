{ pkgs, ... }: {
  home.packages = with pkgs; [
    mold
    clang
    sccache
  ];

  programs.cargo = {
    enable = true;
    settings = {
      target."x86_64-unknown-linux-gnu" = {
        linker = "${pkgs.clang}/bin/clang";
        rustflags = ["-C" "link-arg=-fuse-ld=${pkgs.mold}/bin/mold"];
      };
    };
  };

  home.sessionVariables = {
    RUSTC_WRAPPER = "${pkgs.sccache}/bin/sccache";
  };
}
