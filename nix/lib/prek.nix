{
  pkgs,
  treefmt,
  remind-me-to,
  check-drv-drift,
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
            entry = "${lib.getExe pkgs.statix} check --format errfmt";
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
          {
            id = "remind-me-to";
            name = "remind-me-to";
            entry = "${lib.getExe remind-me-to}";
            language = "system";
            pass_filenames = false;
          }
          {
            id = "check-drv-drift";
            name = "check-drv-drift";
            entry = "${lib.getExe check-drv-drift}";
            language = "system";
            stages = ["pre-push"]; # full-fleet eval x2 — too slow for pre-commit
            pass_filenames = false;
            files = "(\\.nix$|^flake\\.lock$|^homelab\\.toml$)"; # skip lua/docs-only pushes
          }
        ];
      }
    ];
  };

  packages = [
    pkgs.prek
    pkgs.deadnix
    pkgs.statix
    pkgs.flake-checker
    pkgs.shellcheck
    pkgs.stylua
    pkgs.selene
    pkgs.jq
    remind-me-to
    check-drv-drift
  ];
in {
  inherit configFile packages;
  shellHook = ''
    ln -sf ${configFile} prek.toml
    ${lib.getExe pkgs.prek} install -t pre-commit -t pre-push
  '';
}
