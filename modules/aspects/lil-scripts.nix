# lil-scripts — small personal CLI helpers. Converted from
# nix/modules/home/lil-scripts.nix; the repo's own packages
# (Blueprint `flake.packages.<sys>`) are reached as `perSystem.self`.
_: {
  den.aspects.lil-scripts.homeManager = {perSystem, ...}: {
    home.packages = [
      # Find executables in PATH and follow symlink chains
      perSystem.self.whichbin

      # Show Nix derivation tree for an executable
      perSystem.self.treebinderivation

      # List processes listening on ports
      perSystem.self.open-ports

      # Print git repository root directory
      perSystem.self.git-root

      # Print $PATH with newlines for easier reading
      perSystem.self.prettypath

      # View journalctl logs for systemd units
      perSystem.self.jview
    ];
  };
}
