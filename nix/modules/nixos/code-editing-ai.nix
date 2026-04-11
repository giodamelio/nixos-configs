{
  pkgs,
  perSystem,
  ...
}: {
  environment.systemPackages = with pkgs;
  with perSystem.giopkgs; [
    aider-chat
    code-cursor
    codebase-memory-mcp
  ];
}
