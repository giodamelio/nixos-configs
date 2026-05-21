{perSystem, ...}: {
  environment.systemPackages = [
    perSystem.affinity-nix.affinity-v3
  ];
}
