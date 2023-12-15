{
  description = "";
  inputs = {
    nixpkgs.url = "flake:nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    nixos-generators.url = "github:nix-community/nixos-generators";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
    ragenix = {
      url = "github:yaxitech/ragenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # Programs
  inputs = {
    little_boxes = {
      url = "github:giodamelio/little_boxes";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    self,
    flake-parts,
    ...
  }: let
    inherit (inputs.nixpkgs.lib) debug;

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
          scripts = lib.packages.scripts {inherit pkgs;};
          installers = lib.packages.installers {inherit system self;};
          system-info = lib.packages.system-info {inherit pkgs;};
        in
          {
            neovim = lib.packages.neovim {inherit pkgs;};
            scripts-zz = scripts.zz;
            scripts-deploy = scripts.deploy;
            scripts-zdeploy = scripts.zdeploy;
          }
          // installers
          // system-info;

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

        # Deploy with Colmena
        colmena =
          {
            meta = {
              description = "My personal boxes";

              # This can be overriden by node nixpkgs
              nixpkgs = import inputs.nixpkgs {system = "x86_64-linux";};
              nodeNixpkgs = builtins.mapAttrs (name: value: value.pkgs) lib.nixosConfigurations;
              nodeSpecialArgs = builtins.mapAttrs (name: value: value._module.specialArgs) lib.nixosConfigurations;
            };
          }
          // builtins.mapAttrs (name: value: {imports = value._module.args.modules;}) lib.nixosConfigurations;
      };
    };
}
