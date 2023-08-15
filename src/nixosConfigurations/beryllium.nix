{
  root,
  inputs,
  ...
}:
inputs.nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";

  modules = [
    inputs.nixos-generators.nixosModules.do
    inputs.ragenix.nixosModules.default
    root.nixosModules.basic-packages
    root.nixosModules.systems-beryllium
    root.nixosModules.home-manager-users-server
    root.nixosModules.services-lldap
  ];
}
