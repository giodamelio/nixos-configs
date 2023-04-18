{
  inputs,
  cell,
}:
let
  inherit (inputs) nixpkgs std;
  lib = nixpkgs.lib // builtins;
in
lib.mapAttrs (_: std.lib.dev.mkShell) {
  default = { ... }: {
    # This devshell should contain everything I need to deploy NixOS configs
    name = "OS Config Shell";

    imports = [
      # Import TUI and other stuff from std
      std.std.devshellProfiles.default
    ];

    # Helpful packages to have on hand
    packages = with nixpkgs; [
      curl
      wget
      ripgrep
      fd
      vim

      # Colmena for deployment
      inputs.colmena.packages.colmena
    ];

    commands = [
      {
        category = "nix";
        name = "check";
        command = "nix flake check $PRJ_ROOT $@";
        help = "Check our flake";
      }
      {
        category = "nix";
        name = "update";
        command = "nix flake update $PRJ_ROOT $@";
        help = "Update our flakes inputs";
      }
      {
        category = "nixos";
        name = "test";
        command = "sudo nixos-rebuild test --flake $PRJ_ROOT $@";
        help = "Test a NixOS configuration";
      }
      {
        category = "nixos";
        name = "switch";
        command = "sudo nixos-rebuild test --flake $PRJ_ROOT $@";
        help = "Switch to a NixOS configuration";
      }
    ];
  };
}
