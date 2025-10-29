{
  pkgs,
  flake,
  system,
  ...
}: let
  inherit (pkgs) lib;

  # Treefmt Setup
  treefmt = flake.lib.treefmt pkgs;

  # Git Hooks Setup
  inherit (flake.packages.${system}) git-hooks claude-code;
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
        pkgs.dogdns
        pkgs.opentofu
        pkgs.little_boxes
        pkgs.nil
        pkgs.nvd
        pkgs.nix-diff
        pkgs.nix-output-monitor
        pkgs.backblaze-b2
        claude-code
        pkgs.lua-language-server
        pkgs.nh
        pkgs.minio-client
        pkgs.jq
      ]
      ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin []
      # Treefmt
      ++ [treefmt.wrapper]
      ++ (lib.attrValues treefmt.programs)
      # Precommit Hooks tools
      ++ git-hooks.config.enabledPackages;

    shellHook = ''
      ${git-hooks.shellHook}

      alias b2=backblaze-b2
    '';
  }
