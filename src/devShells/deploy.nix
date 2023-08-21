{
  root,
  debug,
  ...
}: {
  pkgs,
  inputs',
  config,
}:
pkgs.mkShell {
  nativeBuildInputs = [
    config.treefmt.build.wrapper
  ];

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

  shellHook = ''
    ${pkgs.lefthook}/bin/lefthook install

    just
  '';
}
