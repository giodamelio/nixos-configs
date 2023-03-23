{
  description = "Simple System Config";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, ... }@inputs: 
  let
    inherit (self) outputs;
  in
  {
    nixosConfigurations = {
      # Testing system
      "nixos-playground" = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs outputs; };
        modules = [ ./hosts/nixos-playground ];
      };
    };
  };
}
