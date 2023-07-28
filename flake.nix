{
  description = "";
  inputs = {
    nixpkgs.url = "flake:nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    nixos-generators.url = "flake:nixos-generators";
    colmena.url = "github:zhaofengli/colmena";
    haumea = {
      url = "github:nix-community/haumea/v0.2.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = inputs @ {
    self,
    flake-parts,
    ...
  }: let
    homelab = builtins.fromTOML (builtins.readFile ./homelab.toml);
    debug = inputs.nixpkgs.lib.debug;
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
        ...
      }: let
        lib = inputs.haumea.lib.load {
          src = ./src;
          inputs = {inherit config pkgs inputs' inputs self' system homelab debug;};
          transformer = inputs.haumea.lib.transformers.liftDefault;
        };
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
        lib = inputs.haumea.lib.load {
          src = ./src;
          inputs = {inherit inputs homelab debug;};
          transformer = inputs.haumea.lib.transformers.liftDefault;
        };
      in {
        nixosModules = lib.nixosModules;
        colmena = lib.colmena;
      };
    };
}
