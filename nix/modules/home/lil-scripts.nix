{
  pkgs,
  flake,
  ...
}: {
  home.packages = [
    # List processes listening on ports
    flake.packages.${pkgs.stdenv.system}.open-ports

    # Print git repository root directory
    flake.packages.${pkgs.stdenv.system}.git-root
  ];
}
