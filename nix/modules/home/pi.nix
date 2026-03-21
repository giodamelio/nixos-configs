{perSystem, ...}: let
  inherit (perSystem.llm-agents) pi;
  inherit (perSystem.giopkgs) omp tk;
in {
  home.packages = [
    tk
  ];

  gio.dont-fuck-my-system-up = {
    enable = true;
    wrappers = let
      defaultROBinds = [
        "/etc/nix"
        "/usr/bin/env"
        "$HOME/.gitconfig"
        "$HOME/.config/git"
        "$HOME/.config/jj"
        "$HOME/.config/nix"
        "$HOME/projects/giodamelio/pi-stuff"
        "$HOME/projects/giodamelio/agent-skills"
        "$HOME/projects/nixos-configs"
      ];
      defaultRWBinds = [
        "$HOME/Documents/life/Projects/"
      ];
    in {
      pi = {
        command = pi;
        roBinds = defaultROBinds;
        rwBinds =
          defaultRWBinds
          ++ [
            "$HOME/.omp"
            "$HOME/.config/omp"
          ];
      };
      omp = {
        command = omp;
        roBinds = defaultROBinds;
        rwBinds =
          defaultRWBinds
          ++ [
            "$HOME/.omp"
            "$HOME/.config/omp"
          ];
      };
    };
  };
}
