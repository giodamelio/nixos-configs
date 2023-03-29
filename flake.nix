{
  description = "Simple System Config";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";

    deploy-rs.url = "github:serokell/deploy-rs";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Nixified software
    hyprland.url = "github:hyprwm/Hyprland";
    yofi = {
      url = "github:l4l/yofi";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, deploy-rs, ... }@inputs: 
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

    deploy = {
      nodes = {
        cadmium = {
          hostname = "localhost";
          sshUser = "root";
          profiles.system = {
            user = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations."cadmium";
          };
        };
      };
    };

    # Catch mistakes with automated checks
    checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
  };
}
