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

    pkgs.lefthook
  ];

  shellHook = ''
    ${pkgs.lefthook}/bin/lefthook install
  '';
}
