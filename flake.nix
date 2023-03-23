{
  description = "Simple System Config";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, ... }@inputs: {
    nixosConfigurations."nixos-playground" = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";

      modules = [
        ./hosts/nixos-playgtound/configuration.nix
        ./common/base-packages.nix
      ];

      # Pass nixpkgs down into the modules
      specialArgs = { inherit nixpkgs; };
    };
  };
}
