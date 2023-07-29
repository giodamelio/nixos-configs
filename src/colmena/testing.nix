{
  root,
  inputs,
  homelab,
  ...
}: {
  deployment = homelab.machines.testing.deployment;

  imports = [
    inputs.nixos-generators.nixosModules.hyperv
    root.nixosModules.systems-testing
    root.nixosModules.home-manager-loader
    root.nixosModules.home-manager-users-server
  ];
}
