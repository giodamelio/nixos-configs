{ pkgs, inputs', ... }:
pkgs.mkShell {
  packages = [
    inputs'.colmena.packages.colmena
  ];
}
