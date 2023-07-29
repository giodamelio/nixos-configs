{
  root,
  inputs,
  homelab,
  ...
}: {
  deployment = homelab.machines.beryllium.deployment;

  imports = [
    inputs.nixos-generators.nixosModules.do
    root.nixosModules.systems-beryllium
  ];
}
