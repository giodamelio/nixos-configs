{
  pkgs,
  flake,
  ...
}: {
  home.packages = [
    # Find executables in PATH and follow symlink chains
    flake.packages.${pkgs.stdenv.system}.whichbin

    # Show Nix derivation tree for an executable
    flake.packages.${pkgs.stdenv.system}.treebinderivation

    # List processes listening on ports
    flake.packages.${pkgs.stdenv.system}.open-ports

    # Print git repository root directory
    flake.packages.${pkgs.stdenv.system}.git-root

    # Print $PATH with newlines for easier reading
    flake.packages.${pkgs.stdenv.system}.prettypath

    # View journalctl logs for systemd units
    flake.packages.${pkgs.stdenv.system}.jview
  ];
}
