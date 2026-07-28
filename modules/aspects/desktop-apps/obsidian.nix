_: {
  den.aspects.obsidian.nixos = {
    pkgs,
    perSystem,
    ...
  }: {
    environment.systemPackages = [
      pkgs.obsidian
      perSystem.giopkgs.obsidian-mcp
    ];
  };
}
