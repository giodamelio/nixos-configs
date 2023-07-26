{ root, inputs, homelab, ... }:
{
  deployment = homelab.machines.testing.deployment;

  imports = [
    inputs.nixos-generators.nixosModules.hyperv
    root.nixosModules.testing
  ];
}
