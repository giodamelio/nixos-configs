{
  inputs,
  system,
  pkgs,
  flake,
  ...
}: let
  inherit (pkgs) lib;

  # Treefmt Setup
  treefmt = flake.lib.treefmt pkgs;

  # Precommit Hooks sub packages
  precommitTools = inputs.pre-commit-hooks.packages.${system};

  # Config for Selene
  luaStdlib = (pkgs.formats.yaml {}).generate "vim.yml" {
    base = "lua51";
    globals = {
      vim.property = "new-fields";
      "_G".property = "new-fields";
      "hs".property = "new-fields";
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

  # New version of Statix that supports |> operator
  statixPipeVersion = pkgs.rustPlatform.buildRustPackage {
    pname = "statix";
    # also update version of the vim plugin in
    # pkgs/applications/editors/vim/plugins/overrides.nix
    # the version can be found in flake.nix of the source code
    version = "0.5.8";

    src = pkgs.fetchFromGitHub {
      owner = "oppiliappan";
      repo = "statix";
      rev = "refs/pull/102/head"; # Git ref for the PR head
      sha256 = "sha256-tvBFAIQuF15M4BygvUJomwQdU+rejWw1Sg/+tTt6jFI=";
    };

    cargoHash = "sha256-Jkp5e0TOKTTpLEAvxPp/UNQATmxOfSJgaakdPM3IidA=";

    buildFeatures = "json";

    # tests are failing on darwin
    doCheck = !pkgs.stdenv.hostPlatform.isDarwin;
  };
in
  inputs.pre-commit-hooks.lib.${system}.run {
    src = ../../.;
    default_stages = ["commit" "pre-push"];
    hooks = {
      # Nix
      deadnix.enable = true;
      statix = {
        enable = true;
        entry = "${lib.getExe statixPipeVersion} check --format errfmt";
      };
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
