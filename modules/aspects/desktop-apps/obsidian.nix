_: {
  den.aspects.obsidian.nixos = {pkgs, ...}: {
    environment.systemPackages = [
      pkgs.obsidian
      # obsidian-mcp 2.5.0 fails its upgrade_semantic_reconcile tests in the sandbox
      # (sentinel process ENOENT); re-add once giopkgs ships a build that passes.
    ];
  };
}
