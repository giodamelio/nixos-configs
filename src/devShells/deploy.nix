{lib, ...}: {
  pkgs,
  inputs',
  config,
}: {
  languages.nix.enable = true;
  languages.lua.enable = true;

  packages = [
    inputs'.colmena.packages.colmena
    inputs'.little_boxes.packages.default
    inputs'.ragenix.packages.ragenix

    config.packages.scripts-deploy
    config.packages.scripts-zdeploy

    pkgs.lefthook
    pkgs.nurl
    pkgs.just
    pkgs.nushell
    pkgs.rage
    pkgs.pwgen
  ];

  enterShell = ''
    ${pkgs.lefthook}/bin/lefthook install

    just
  '';

  # Stop errors since we are not using containers
  # See: https://github.com/cachix/devenv/issues/528
  containers = lib.mkForce {};
}
