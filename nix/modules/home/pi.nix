{perSystem, ...}: {
  home.packages = [
    perSystem.llm-agents.pi
    perSystem.giopkgs.omp
  ];
}
