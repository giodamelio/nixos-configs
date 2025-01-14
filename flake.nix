{
  description = "My personal Nix configs";

  outputs = inputs:
    inputs.snowfall-lib.mkFlake {
      inherit inputs;

      src = ./.; # Root of the flake

      snowfall = {
        root = ./nix;
        namespace = "giodamelio";
      };

      # Alias the default shell
      alias.shells.default = "development";

      # Setup Treefmt as the formatter
      outputs-builder = channels: let
        treefmtConfig = {pkgs, ...}: {
          projectRootFile = "flake.nix";

          # Exclude some files from formatting
          settings.excludes = [
            ".envrc"
            "flake.lock"
            ".gitignore"
            "homelab.toml"
          ];

          programs = {
            alejandra.enable = true;
            stylua.enable = true;
          };
        };
        treefmtEval = inputs.treefmt-nix.lib.evalModule (channels.nixpkgs) treefmtConfig;
      in {
        formatter = treefmtEval.config.build.wrapper;
      };
    };

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    # Unified config loader
    snowfall-lib.url = "github:snowfallorg/lib";
    snowfall-lib.inputs.nixpkgs.follows = "nixpkgs";

    # Manage user environments with Nix
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # Single command formatting for all languages
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };
}
