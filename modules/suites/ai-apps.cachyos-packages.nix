{
  # AI Apps - CachyOS native packages
  grabcontext = {
    packages = {
    };
  };

  opencode = {
    packages = {
      pacman = [ "opencode" ];
    };
  };

graphify = {
    packages = {
      paru = [ "graphifyy" ];
    };
  };
  
  github-copilot-cli = {
    packages = {
      pacman = [ "github-copilot-cli" ];
    };
  };

  herdr-bin = {
    packages = {
      paru = [ "herdr-bin" ];
    };
  };

  # FUSE2 support for AppImages
  appimages-fuse = {
    packages = {
      pacman = [
        "fuse2"           # FUSE2 library required by AppImages
      ];
    };
  };

}
