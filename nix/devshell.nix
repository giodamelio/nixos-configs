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

  # Rebuilt from the checkout on every run: the real package bakes in the zones,
  # and the devshell isn't re-entered when a service's DNS name changes.
  fleet-dns = pkgs.writeShellApplication {
    name = "fleet-dns";
    runtimeInputs = [pkgs.git];
    text = ''exec nix run "$(git rev-parse --show-toplevel)#fleet-dns" -- "$@"'';
  };
in
  pkgs.mkShell {
    buildInputs =
      [
        pkgs.git
        pkgs.nurl
        pkgs.nix-init
        pkgs.nushell
        pkgs.rage
        # CA + age secrets tooling (strontium)
        pkgs.age
        pkgs.age-plugin-yubikey
        pkgs.step-cli
        pkgs.paper-age
        pkgs.qrencode
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
        fleet-dns

        pkgs.go
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
