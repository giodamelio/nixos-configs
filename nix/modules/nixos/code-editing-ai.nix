{
  pkgs,
  perSystem,
  ...
}: {
  environment.systemPackages = [
    pkgs.aider-chat
    pkgs.code-cursor
    perSystem.giopkgs.codebase-memory-mcp
    perSystem.mob.default
  ];
}
