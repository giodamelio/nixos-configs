{
  inputs,
  lib,
  pkgs,
  perSystem,
  ...
}: let
  jail = import ../../lib/jail-combinators.nix {inherit pkgs inputs;};
  inherit (perSystem.llm-agents) pi;
  inherit (perSystem.giopkgs) omp tk;

  commonPermissions = c:
    with c; [
      # NixOS essentials
      network
      (readwrite "/nix")
      (try-readonly "/run")
      (try-readonly "/etc/static")
      (try-readonly "/etc/profiles")
      overlay-home
      work-in-cwd
      (rw-paths-from-file ".sandbox-paths")

      # Shared ro paths
      (try-readonly "/etc/nix")
      (try-readonly "/usr/bin/env")
      (try-readonly (noescape "~/.gitconfig"))
      (try-readonly (noescape "~/.config/git"))
      (try-readonly (noescape "~/.config/jj"))
      (try-readonly (noescape "~/.config/nix"))
      (try-readonly (noescape "~/projects/giodamelio/pi-stuff"))
      (try-readonly (noescape "~/projects/giodamelio/agent-skills"))
      (try-readonly (noescape "~/projects/nixos-configs"))

      # Shared rw paths
      (try-readwrite (noescape "~/Documents/life/Projects/"))
      (try-readwrite (noescape "~/.omp"))
      (try-readwrite (noescape "~/.config/omp"))

      # Environment
      (unset-env "ANTHROPIC_API_KEY")
    ];

  jailedPi = jail "jailed-pi" pi commonPermissions;
  jailedOmp = jail "jailed-omp" omp commonPermissions;
in {
  home.packages = [
    tk
    jailedPi
    jailedOmp
  ];

  home.shellAliases = {
    pi = lib.getExe jailedPi;
    pi-dangerous = lib.getExe pi;
    omp = lib.getExe jailedOmp;
    omp-dangerous = lib.getExe omp;
  };
}
