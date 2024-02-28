{lib, ...}: {
  pkgs,
  inputs',
  config,
  ...
}: {
  languages.nix.enable = true;
  languages.lua.enable = true;

  packages = [
    inputs'.colmena.packages.colmena
    inputs'.little_boxes.packages.default

    config.packages.deploy

    pkgs.nurl
    pkgs.nushell
    pkgs.rage
    pkgs.pwgen
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
    };

    settings = {
      statix.ignore = [".direnv/*"];
    };
  };

  # Stop errors since we are not using containers
  # See: https://github.com/cachix/devenv/issues/528
  containers = lib.mkForce {};
}
