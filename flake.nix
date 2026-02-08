{
  description = "Modular Home Manager Config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, ... }: 
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
        };
      };
    in {
      homeConfigurations."work" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ ./profiles/work/home.nix ];
      };
    };
}