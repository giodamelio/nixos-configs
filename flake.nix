{
  description = "";
  inputs = {
    nixpkgs.url = "flake:nixpkgs/nixpkgs-unstable";
    nixos-generators.url = "flake:nixos-generators";
    colmena.url = "github:zhaofengli/colmena";
  };
  outputs = inputs:
    let
      flakeContext = {
        inherit inputs;
      };
      homelab = (builtins.fromTOML (builtins.readFile ./homelab.toml));
    in
    {
      devShells = {
        x86_64-linux = {
          default = import ./devShells/default.nix flakeContext { system = "x86_64-linux"; };
	};
      };
      nixosConfigurations = {
        beryllium = import ./nixosConfigurations/beryllium.nix flakeContext;
        testing = import ./nixosConfigurations/testing.nix flakeContext;
      };
      nixosModules = {
        beryllium = import ./nixosModules/beryllium.nix flakeContext;
        testing = import ./nixosModules/testing.nix flakeContext;
      };
      packages = {
        x86_64-linux = {
          beryllium-do = import ./packages/beryllium-do.nix flakeContext;
          beryllium-hyperv = import ./packages/beryllium-hyperv.nix flakeContext;
        };
      };
      colmena = {
	meta = {
	  nixpkgs = import inputs.nixpkgs {
	    system = "x86_64-linux";
	    overlays = [];
	  };
	};

	beryllium = {
	  deployment = homelab.machines.beryllium.deployment;

	  imports = [
	    inputs.nixos-generators.nixosModules.do
	    inputs.self.nixosModules.beryllium
	  ];
	};

	testing = {
	  deployment = homelab.machines.testing.deployment;

	  imports = [
	    inputs.nixos-generators.nixosModules.hyperv
	    inputs.self.nixosModules.testing
	  ];
	};
      };
    };
}
