{ inputs, ... }:
{ system }:
let
  pkgs = inputs.nixpkgs.legacyPackages."${system}";
in
pkgs.mkShell {
  packages = [
    inputs.colmena.packages.${system}.colmena
  ];
}
