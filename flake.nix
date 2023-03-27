{
  description = "Simple System Config";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs: 
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

      "cadmium" = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs outputs; };
        modules = [ ./hosts/cadmium ];
      };
    };

    homeConfigurations = {
      "giodamelio@nixos-playground" = home-manager.lib.homeManagerConfiguration {
       extraSpecialArgs = { inherit inputs outputs; };
       modules = [ ./home/giodamelio/nixos-playground.nix ];
      };

      "giodamelio@cadmium" = home-manager.lib.homeManagerConfiguration {
       extraSpecialArgs = { inherit inputs outputs; };
       modules = [ ./home/giodamelio/cadmium.nix ];
      };
    };
  };
}
