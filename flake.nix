{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dots-local.url = "path:./placeholder"; 
  };

  outputs = { self, nixpkgs, home-manager, dots-local, ... }: 
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      
      # Pull logic out here
      targetProfile = dots-local.profile;
      
      # Define the common settings as a module variable
      shared-config = {
        home.username = dots-local.username;
        home.homeDirectory = dots-local.homeDirectory;
        
        home.shellAliases = {
          apply-dots = "cd ~/dots && git add . && nix run home-manager -- switch --flake $HOME/dots#${targetProfile} --override-input dots-local git+file://$HOME/dots-local && cd -";
          update-dots = "cd ~/dots && nix flake update && cd -";
        };
        
        targets.genericLinux.enable = true;
      };
    in {
      homeConfigurations."${targetProfile}" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ 
          ./profiles/work/home.nix 
          shared-config # Inject the variable here
        ];
      };
    };
}
