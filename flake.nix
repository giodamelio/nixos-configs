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
    in
    {
      devShells = {
        x86_64-linux = {
          default = import ./devShells/default.nix flakeContext { system = "x86_64-linux"; };
	};
      };
      nixosConfigurations = {
        beryllium = import ./nixosConfigurations/beryllium.nix flakeContext;
      };
      nixosModules = {
        beryllium = import ./nixosModules/beryllium.nix flakeContext;
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
	  deployment = {
	    targetHost = "128.199.9.59";
	    targetUser = "server";
	  };

	  imports = [
	    inputs.nixos-generators.nixosModules.do
	    inputs.self.nixosModules.beryllium
	  ];
	};
      };
    };
}
