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
    nixosConfigurations."nixos-playgtound" = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./machines/nixos-playgtound/configuration.nix
        ./common-packages.nix
      ];
    };
  };
}
