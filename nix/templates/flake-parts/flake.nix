{
  description = "Simple flake.parts template";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    git-hooks.url = "github:cachix/git-hooks.nix";
    git-hooks.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        inputs.treefmt-nix.flakeModule
        inputs.git-hooks.flakeModule
      ];

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];

      perSystem = {
        config,
        pkgs,
        ...
      }: {
        devShells.default = pkgs.mkShell {
          inputsFrom = [
            config.pre-commit.devShell
            config.treefmt.build.devShell
          ];

          packages = with pkgs; [
            # Nix tooling
            nil # LSP
          ];
        };

        # Treefmt configuration
        treefmt = {
          projectRootFile = "flake.nix";
          programs = {
            alejandra.enable = true; # Nix formatter
          };
        };

        # Git hooks configuration
        pre-commit = {
          check.enable = true;
          settings = {
            enable = true;
            default_stages = [
              "pre-commit"
              "pre-push"
            ];
            hooks = {
              # Formatting
              treefmt = {
                enable = true;
                package = config.treefmt.build.wrapper;
              };

              # General checks
              end-of-file-fixer.enable = true;
              trim-trailing-whitespace.enable = true;
            };
          };
        };
      };

      flake = {};
    };
}
