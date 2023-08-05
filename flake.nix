{
  description = "";
  inputs = {
    nixpkgs.url = "flake:nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    nixos-generators.url = "github:nix-community/nixos-generators";
    deploy-rs.url = "github:serokell/deploy-rs";
    nuenv = {
      url = "github:giodamelio/nuenv/mkCommand";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
    deploy-rs,
    ...
  }: let
    debug = inputs.nixpkgs.lib.debug;

    # Static data about our homelab
    homelab = builtins.fromTOML (builtins.readFile ./homelab.toml);

    # Some utility functions
    util = import ./util.nix {inherit (inputs) nixpkgs;};

    # Load all of our source file
    # Flatten the modules under ./src/nixosModules
    lib = inputs.haumea.lib.load {
      src = ./src;
      inputs = {inherit inputs homelab debug;};
      transformer = [
        (util.subtreeTransformer ["nixosModules"] util.flattenTransformer)
      ];
    };
  in
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        inputs.treefmt-nix.flakeModule
      ];

      systems = ["x86_64-linux" "aarch64-linux"];

      perSystem = {
        pkgs,
        inputs',
        config,
        self',
        system,
        ...
      }: {
        devShells = rec {
          deploy = lib.devShells.deploy {inherit pkgs inputs' config;};
          default = deploy;
        };
        packages = let
          scripts = lib.packages.scripts {inherit pkgs system;};
        in {
          neovim-config = lib.packages.neovim-config {inherit pkgs;};
          scripts-zz = scripts.zz;
        };
        treefmt = {
          projectRootFile = ".git/config";
          programs = {
            alejandra.enable = true;
          };
        };
      };

      flake = {
        # Export our modules and configurations
        nixosModules = lib.nixosModules;
        nixosConfigurations = lib.nixosConfigurations;

        # Deploy with deploy-rs
        deploy.nodes = lib.deploy-rs;
        checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
      };
    };
}
