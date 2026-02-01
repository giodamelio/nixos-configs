{
  pkgs,
  flake,
  ...
}: {
  home.packages = [
    flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.pi
  ];
}
