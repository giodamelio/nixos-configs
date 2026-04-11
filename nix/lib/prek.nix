{
  pkgs,
  treefmt,
  statix-pipe,
}: let
  inherit (pkgs) lib;

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
    phases = ["installPhase"];
    installPhase = ''
      mkdir -p $out
      ln -s ${seleneConfig} $out/selene.toml
      ln -s ${luaStdlib} $out/vim.yml
    '';
  };

  # Generate prek.toml
  configFile = (pkgs.formats.toml {}).generate "prek.toml" {
    default_stages = ["pre-commit" "pre-push"];
    repos = [
      {
        repo = "builtin";
        hooks = [
          {id = "check-added-large-files";}
          {id = "check-case-conflict";}
          {id = "check-json";}
          {id = "check-merge-conflict";}
          {id = "check-toml";}
          {id = "check-yaml";}
          {id = "detect-private-key";}
          {id = "end-of-file-fixer";}
          {id = "trailing-whitespace";}
        ];
      }
      {
        repo = "local";
        hooks = [
          {
            id = "deadnix";
            name = "deadnix";
            entry = "${lib.getExe pkgs.deadnix} --fail";
            language = "system";
            files = "\\.nix$";
          }
          {
            id = "statix";
            name = "statix";
            entry = "${lib.getExe statix-pipe} check --format errfmt";
            language = "system";
            files = "\\.nix$";
            pass_filenames = false;
          }
          {
            id = "flake-checker";
            name = "flake-checker";
            entry = "${lib.getExe pkgs.flake-checker} -f";
            language = "system";
            files = "(^flake\\.nix$|^flake\\.lock$)";
            pass_filenames = false;
          }
          {
            id = "shellcheck";
            name = "shellcheck";
            entry = "${lib.getExe pkgs.shellcheck}";
            language = "system";
            types = ["shell"];
          }
          {
            id = "stylua";
            name = "stylua";
            entry = "${lib.getExe pkgs.stylua} --respect-ignores";
            language = "system";
            types = ["lua"];
          }
          {
            id = "selene";
            name = "selene";
            entry = "${lib.getExe pkgs.selene} --config ${combinedConfig}/selene.toml --no-summary";
            language = "system";
            types = ["lua"];
          }
          {
            id = "treefmt";
            name = "treefmt";
            entry = "${lib.getExe treefmt.wrapper} --fail-on-change --no-cache";
            language = "system";
            pass_filenames = false;
          }
        ];
      }
    ];
  };

  packages = [
    pkgs.prek
    pkgs.deadnix
    statix-pipe
    pkgs.flake-checker
    pkgs.shellcheck
    pkgs.stylua
    pkgs.selene
    pkgs.jq
  ];
in {
  inherit configFile packages;
  shellHook = ''
    ln -sf ${configFile} prek.toml
    ${lib.getExe pkgs.prek} install
  '';
}
