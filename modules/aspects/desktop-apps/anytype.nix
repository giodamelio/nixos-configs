# anytype — local-first knowledge base desktop app.
_: {
  den.aspects.anytype.nixos = {
    pkgs,
    perSystem,
    ...
  }: {
    environment.systemPackages = [
      pkgs.anytype
      perSystem.giopkgs.anytype-mcp
    ];
  };
}
