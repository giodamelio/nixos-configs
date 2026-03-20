{perSystem, ...}: let
  inherit (perSystem.llm-agents) pi;
  inherit (perSystem.giopkgs) omp tk;
in {
  home.packages = [
    tk
  ];

  gio.dont-fuck-my-system-up = {
    enable = true;
    wrappers = {
      pi = {
        command = pi;
        rwBinds = [
          "$HOME/.omp"
          "$HOME/.config/omp"
        ];
        roBinds = [
          "$HOME/.gitconfig"
          "$HOME/.config/git"
          "$HOME/.config/jj"
          "$HOME/.config/nix"
          "/etc/nix"
          "$HOME/projects/giodamelio/pi-stuff"
        ];
      };
      omp = {
        command = omp;
        rwBinds = [
          "$HOME/.omp"
          "$HOME/.config/omp"
        ];
        roBinds = [
          "$HOME/.gitconfig"
          "$HOME/.config/git"
          "$HOME/.config/jj"
          "$HOME/.config/nix"
          "/etc/nix"
        ];
      };
    };
  };
}
