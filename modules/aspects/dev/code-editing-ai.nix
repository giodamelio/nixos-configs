# code-editing-ai — system-wide AI coding tools. Converted from
# nix/modules/nixos/code-editing-ai.nix.
_: {
  den.aspects.code-editing-ai.nixos = {
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
  };
}
