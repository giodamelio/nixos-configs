{
  root,
  inputs,
  ...
}:
inputs.nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";

  modules = [
    inputs.nixos-generators.nixosModules.hyperv
    root.nixosModules.basic-packages
    root.nixosModules.systems-testing
    root.nixosModules.home-manager-users-server
  ];
}
