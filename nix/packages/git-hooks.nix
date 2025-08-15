{
  inputs,
  system,
  pkgs,
  ...
}: let
  inherit (pkgs) lib;

  # Treefmt Setup
  treefmtEvaledModule = inputs.treefmt-nix.lib.evalModule pkgs (import ../../treefmt.nix);
  treefmt = treefmtEvaledModule.config.build;

  # Precommit Hooks sub packages
  precommitTools = inputs.pre-commit-hooks.packages.${system};

  # Config for Selene
  luaStdlib = (pkgs.formats.yaml {}).generate "vim.yml" {
    base = "lua51";
    globals = {
      vim.property = "new-fields";
      "_G".property = "new-fields";
    };
  };
  seleneConfig = (pkgs.formats.toml {}).generate "selene.toml" {
    std = "vim";
    lints = {
      mixed_table = "allow";
      global_usage = "allow";
    };
  };
  combinedConfig = pkgs.stdenv.mkDerivation {
    name = "selene-config";
    phases = ["installPhase"]; # Only run the install phase
    installPhase = ''
      mkdir -p $out
      ln -s ${seleneConfig} $out/selene.toml
      ln -s ${luaStdlib} $out/vim.yml
    '';
  };
in
  inputs.pre-commit-hooks.lib.${system}.run {
    src = ../../.;
    hooks = {
      # Nix
      deadnix.enable = true;
      statix.enable = true;
      flake-checker.enable = true;

      # Shell
      shellcheck.enable = true;

      # Lua (for Neovim config)
      stylua.enable = true;
      selene = {
        enable = true;
        entry = "${lib.getExe precommitTools.selene} --config ${combinedConfig}/selene.toml";
      };
      lua-ls = {
        enable = true;
        settings = {
          configuration = {
            diagnostics.globals = ["vim"];
          };
        };
      };

      # Our whole formatting stack
      treefmt = {
        enable = true;
        packageOverrides.treefmt = treefmt.wrapper;
      };
    };
  }
