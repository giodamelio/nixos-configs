{
  description = "";
  inputs = {
    nixpkgs.url = "flake:nixpkgs/nixpkgs-unstable";
    nixos-generators.url = "flake:nixos-generators";
    colmena.url = "github:zhaofengli/colmena";
    haumea = {
      url = "github:nix-community/haumea/v0.2.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = inputs:
    let
      flakeContext = {
        inherit inputs;
      };
      homelab = (builtins.fromTOML (builtins.readFile ./homelab.toml));
      lib = inputs.haumea.lib.load {
	src = ./src;
	inputs = {
	  inherit inputs homelab;
	};
	transformer = inputs.haumea.lib.transformers.liftDefault;
      };
    in
    {
      devShells = {
        x86_64-linux = rec {
          deploy = lib.devShells.deploy {
	    system = "x86_64-linux";
	  };
	  default = deploy;
	};
      };
      nixosConfigurations = lib.nixosConfigurations;
      nixosModules = lib.nixosModules;
      packages = {
        x86_64-linux = {
	  beryllium-do = lib.packages.beryllium-do;
	  beryllium-hyperv = lib.packages.beryllium-hyperv;
        };
      };
      colmena = lib.colmena;
    };
}
