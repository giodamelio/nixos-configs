{
  pkgs,
  inputs',
  config,
  ...
}:
pkgs.mkShell {
  nativeBuildInputs = [
    config.treefmt.build.wrapper
  ];

  packages = [
    inputs'.colmena.packages.colmena
  ];
}
