{
  lib,
  root,
  ...
}: {
  pkgs,
  inputs',
  config,
  ...
}: {
  # Temporary hack
  # See: https://github.com/cachix/devenv/pull/1018
  devenv.root = "/home/giodamelio/nixos-configs";

  languages.nix.enable = true;
  languages.lua.enable = true;
  # languages.terraform.enable = true;

  packages = [
    inputs'.colmena.packages.colmena
    inputs'.ragenix.packages.default
    inputs'.morlana.packages.default

    config.packages.deploy

    pkgs.git
    pkgs.nurl
    pkgs.nix-init
    pkgs.nushell
    pkgs.rage
    pkgs.pwgen
    pkgs.dogdns
    pkgs.opentofu
    pkgs.little_boxes

    (root.packages.agedit {inherit pkgs;})
    (root.packages.neovim {inherit pkgs;})
  ];

  pre-commit = {
    default_stages = ["commit" "push"];

    hooks = {
      # Nix
      alejandra.enable = true;
      deadnix.enable = true;
      statix.enable = true;

      # Lua
      stylua.enable = true;
      luacheck.enable = true;

      # Terraform
      terraform-format.enable = true;
      tflint.enable = true;
    };

    settings = {
      statix.ignore = [".direnv/*"];
    };
  };

  # Stop errors since we are not using containers
  # See: https://github.com/cachix/devenv/issues/528
  containers = lib.mkForce {};
}
