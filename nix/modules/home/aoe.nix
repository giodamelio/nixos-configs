{
  perSystem,
  pkgs,
  ...
}: {
  home.packages = with pkgs;
  with perSystem.llm-agents;
  with perSystem.giopkgs; [
    tmux
    claude-code
    agent-of-empires
  ];
}
