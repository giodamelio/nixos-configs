{
  root,
  inputs,
  homelab,
  ...
}:
inputs.nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";

  modules = [
    inputs.nixos-generators.nixosModules.hyperv
    root.nixosModules.systems-testing
    root.nixosModules.home-manager-loader
    root.nixosModules.home-manager-users-server
  ];
}
