{
  pkgs,
  flake,
  system,
  ...
}: let
  inherit (pkgs) lib;

  # Treefmt Setup
  treefmt = flake.lib.treefmt pkgs;

  # Prek (git hooks) Setup
  prek = flake.lib.prek pkgs flake;

  inherit (flake.packages.${system}) deploy;
in
  pkgs.mkShell {
    buildInputs =
      [
        pkgs.git
        pkgs.nurl
        pkgs.nix-init
        pkgs.nushell
        pkgs.rage
        pkgs.pwgen
        pkgs.doggo
        pkgs.little_boxes
        pkgs.nil
        pkgs.nvd
        pkgs.nix-diff
        pkgs.nix-output-monitor
        pkgs.lua-language-server
        pkgs.nh
        pkgs.minio-client
        pkgs.jq

        pkgs.nixd
        pkgs.efibootmgr
        deploy
      ]
      ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin []
      # Treefmt
      ++ [treefmt.wrapper]
      ++ (lib.attrValues treefmt.programs)
      # Prek (git hooks) tools
      ++ prek.packages;

    shellHook = ''
      ${prek.shellHook}

      alias b2=backblaze-b2
    '';
  }
