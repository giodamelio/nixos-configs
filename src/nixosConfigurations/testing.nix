{
  root,
  inputs,
  homelab,
  ...
}:
inputs.nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";

  extraModules = [
    # Not sure why this has to be an extraModule instead of a regular module
    inputs.colmena.nixosModules.deploymentOptions
  ];

  modules = [
    inputs.nixos-generators.nixosModules.hyperv
    root.nixosModules.basic-packages
    root.nixosModules.systems-testing
    root.nixosModules.home-manager-users-server

    # Load the deployment config from our homelab.toml
    ({...}: {
      config.deployment = homelab.machines.testing.deployment;
    })
  ];
}
