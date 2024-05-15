{
  description = "My Personal Nix Configs";

  outputs = inputs @ {flake-parts, ...}: let
    inherit (inputs.nixpkgs.lib) debug;

    # Static data about our homelab
    homelab = builtins.fromTOML (builtins.readFile ./homelab.toml);

    # Load all of our source file
    lib = inputs.haumea.lib.load {
      src = ./src;
      inputs = {
        inherit inputs homelab debug;
        inherit (inputs.nixpkgs) lib;
      };
    };
  in
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        inputs.treefmt-nix.flakeModule
        inputs.devenv.flakeModule
      ];

      systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin"];

      perSystem = {
        pkgs,
        inputs',
        config,
        system,
        ...
      }: let
        sys = {inherit pkgs inputs' config;};
      in {
        # Allow unfree packages
        _module.args.pkgs = import inputs.nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        # Pass the per system attributes to each package
        # Allow either a packge or attrset of packages in each file
        # If it is an atterset, each package within has the filename prefixed
        packages =
          pkgs.lib.attrsets.concatMapAttrs
          (
            name: pkgFn: let
              inherit (pkgs.lib) attrsets;
              pkg = pkgFn sys;
            in
              if (attrsets.isDerivation pkg)
              then {"${name}" = pkg;}
              else
                attrsets.mapAttrs' (
                  subName: subPkg:
                    attrsets.nameValuePair "${name}-${subName}" subPkg
                )
                pkg
          )
          lib.packages;

        devenv.shells.default = lib.devShells.deploy sys;

        treefmt = {
          projectRootFile = ".git/config";
          programs = {
            alejandra.enable = true;
            stylua.enable = true;
          };
        };
      };

      flake = {
        # Export our modules and configurations
        inherit (lib) nixosModules;
        inherit (lib) nixosConfigurations;
        inherit (lib) darwinConfigurations;
        inherit (lib) homeModules;

        # Deploy with Colmena
        colmena =
          {
            meta = {
              description = "My personal boxes";

              # This can be overriden by node nixpkgs
              nixpkgs = import inputs.nixpkgs {system = "x86_64-linux";};
              nodeNixpkgs = builtins.mapAttrs (_: value: value.pkgs) lib.nixosConfigurations;
              nodeSpecialArgs = builtins.mapAttrs (_: value: value._module.specialArgs) lib.nixosConfigurations;
            };
          }
          // builtins.mapAttrs (_: value: {imports = value._module.args.modules;}) lib.nixosConfigurations;
      };
    };

  inputs = {
    # Nixpkgs
    nixpkgs.url = "flake:nixpkgs/nixpkgs-unstable";

    # Configure MacOS via Nix
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    # Flake authoring framework
    flake-parts.url = "github:hercules-ci/flake-parts";

    # Format all the things
    treefmt-nix.url = "github:numtide/treefmt-nix";

    # Build NixOS images
    nixos-generators.url = "github:nix-community/nixos-generators";

    # NixOS modules for specific hardware
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # Stateless NixOS deployment tool written in Rust
    colmena.url = "github:zhaofengli/colmena";
    colmena.inputs.nixpkgs.follows = "nixpkgs";

    # Declarative disk partitioning
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    # Use NixOS in WSL2
    nixos-wsl.url = "github:nix-community/NixOS-WSL";
    nixos-wsl.inputs.nixpkgs.follows = "nixpkgs";

    # Filesystem based importing for Nix
    haumea.url = "github:nix-community/haumea/v0.2.2";
    haumea.inputs.nixpkgs.follows = "nixpkgs";

    # Manage user environments with Nix
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # Print pretty boxes around things in your shell scripts
    little_boxes.url = "github:giodamelio/little_boxes";
    little_boxes.inputs.nixpkgs.follows = "nixpkgs";

    # Easy Dev Shells
    devenv.url = "github:cachix/devenv";

    # Encrypted Secrets
    ragenix.url = "github:yaxitech/ragenix";
    ragenix.inputs.nixpkgs.follows = "nixpkgs";

    # Simplified nix packaging for various programming language ecosystems
    dream2nix.url = "github:nix-community/dream2nix";
    dream2nix.inputs.nixpkgs.follows = "nixpkgs";
  };
}
