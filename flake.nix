{
  description = "My Personal Nix Configs";

  outputs = inputs @ {self, flake-parts, ...}: let
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
        inputs.pkgs-by-name-for-flake-parts.flakeModule
        inputs.ez-configs.flakeModule
      ];

      systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin"];

      # Load configs from nix directory
      ezConfigs = {
        root = ./nix;
        globalArgs = {
          inherit inputs self homelab;
          myPkgs = self.packages;
        };

        nixos.hosts.test-vm.userHomeModules = ["server"];
        nixos.hosts.cadmium.userHomeModules = ["giodamelio"];
      };

      perSystem = {
        pkgs,
        inputs',
        config,
        system,
        ...
      }: let
        sys = {inherit pkgs inputs' config system;};
      in {
        # Allow unfree packages
        _module.args.pkgs = import inputs.nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        # Load packages from directories
        pkgsDirectory = ./src/pkgs-by-name;

        # Create basic devshell with some basic tools
        devShells.default = pkgs.mkShell {
          buildInputs =
            [
              inputs'.colmena.packages.colmena
              inputs'.ragenix.packages.default

              config.packages.deploy
              config.packages.neovim
              config.packages.agedit

              pkgs.git
              pkgs.nurl
              pkgs.nix-init
              pkgs.nushell
              pkgs.rage
              pkgs.pwgen
              pkgs.dogdns
              pkgs.opentofu
              pkgs.little_boxes
              pkgs.nil
              pkgs.nvd
              pkgs.nix-diff
            ]
            ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
              inputs'.morlana.packages.default
            ];
        };

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
        colmenaHive = inputs.colmena.lib.makeHive self.outputs.colmena;
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

    # Easy package definition
    pkgs-by-name-for-flake-parts.url = "github:drupol/pkgs-by-name-for-flake-parts";

    # Easy config organization
    ez-configs.url = "github:ehllie/ez-configs";
    ez-configs.inputs.nixpkgs.follows = "nixpkgs";
    ez-configs.inputs.flake-parts.follows = "flake-parts";

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

    # Encrypted Secrets
    ragenix.url = "github:yaxitech/ragenix";
    ragenix.inputs.nixpkgs.follows = "nixpkgs";

    # Pre built Nixpkgs index
    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";

    # Experimental DE from System76
    nixos-cosmic.url = "github:lilyinstarlight/nixos-cosmic";
    nixos-cosmic.inputs.nixpkgs.follows = "nixpkgs";

    # Nix on my phone
    nix-on-droid.url = "github:nix-community/nix-on-droid/master";
    nix-on-droid.inputs.nixpkgs.follows = "nixpkgs";

    # Nice CLI for deploying Nix on Darwin
    morlana.url = "github:ryanccn/morlana";
    morlana.inputs.nixpkgs.follows = "nixpkgs";
  };
}
