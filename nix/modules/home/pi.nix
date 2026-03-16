{
  flake,
  lib,
  perSystem,
  pkgs,
  ...
}: let
  inherit (perSystem.llm-agents) pi;
  inherit (perSystem.giopkgs) omp tk;
  dontFuckMySystemUp = flake.packages.${pkgs.stdenv.hostPlatform.system}.dont-fuck-my-system-up;
in {
  home.packages = [
    dontFuckMySystemUp
    tk
  ];

  home.shellAliases = {
    pi = "${lib.getExe dontFuckMySystemUp} -- ${lib.getExe pi}";
    omp = "${lib.getExe dontFuckMySystemUp} -- ${lib.getExe omp}";
    pi-dangerous = lib.getExe pi;
    omp-dangerous = lib.getExe omp;
  };
}
