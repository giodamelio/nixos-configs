{
  description = "";
  inputs = {
    nixpkgs.url = "flake:nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    nixos-generators.url = "github:nix-community/nixos-generators";
    colmena.url = "github:zhaofengli/colmena";
    haumea = {
      url = "github:nix-community/haumea/v0.2.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = inputs @ {
    self,
    flake-parts,
    ...
  }: let
    debug = inputs.nixpkgs.lib.debug;

    # Static data about our homelab
    homelab = builtins.fromTOML (builtins.readFile ./homelab.toml);

    # Some utility functions
    util = import ./util.nix {inherit (inputs) nixpkgs;};

    # Load our source files with out transformers
    loadSrc = custom-inputs:
      inputs.haumea.lib.load {
        src = ./src;
        inputs = custom-inputs;
        transformer = [
          inputs.haumea.lib.transformers.liftDefault
          (util.subtreeTransformer
            ["nixosModules"]
            util.flattenTransformer)
        ];
      };
  in
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        inputs.treefmt-nix.flakeModule
      ];
      systems = ["x86_64-linux" "aarch64-linux"];
      perSystem = {
        config,
        pkgs,
        inputs',
        self',
        system,
        debug,
        ...
      }: let
        lib = loadSrc {inherit config pkgs inputs' inputs self' system homelab debug;};
      in {
        devShells = rec {
          deploy = lib.devShells.deploy;
          default = deploy;
        };
        packages = lib.packages;
        treefmt = {
          projectRootFile = ".git/config";
          programs = {
            alejandra.enable = true;
          };
        };
      };

      flake = let
        lib = loadSrc {inherit inputs homelab debug;};
      in {
        nixosModules = lib.nixosModules;
        colmena = lib.colmena;
      };
    };
}
