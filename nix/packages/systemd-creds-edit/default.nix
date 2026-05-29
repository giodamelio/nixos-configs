{
  flake,
  pkgs,
  ...
}: let
  inherit (pkgs) lib;
in
  flake.lib.writeNushellApplication pkgs {
    name = "systemd-creds-edit";
    runtimeInputs = [pkgs.systemd pkgs.coreutils];
    meta.description = "Edit a systemd-creds encrypted credential file in place";
    meta.platforms = lib.platforms.linux;
    meta.mainProgram = "systemd-creds-edit";
    source = builtins.readFile ./systemd-creds-edit.nu;
  }
