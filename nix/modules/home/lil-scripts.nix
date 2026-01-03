{
  pkgs,
  flake,
  ...
}: let
  inherit (pkgs.stdenv.hostPlatform) system;
in {
  home.packages = [
    # Find executables in PATH and follow symlink chains
    flake.packages.${system}.whichbin

    # Show Nix derivation tree for an executable
    flake.packages.${system}.treebinderivation

    # List processes listening on ports
    flake.packages.${system}.open-ports

    # Print git repository root directory
    flake.packages.${system}.git-root

    # Print $PATH with newlines for easier reading
    flake.packages.${system}.prettypath

    # View journalctl logs for systemd units
    flake.packages.${system}.jview
  ];
}
