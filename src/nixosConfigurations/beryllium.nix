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
    inputs.nixos-generators.nixosModules.do
    inputs.ragenix.nixosModules.default
    root.nixosModules.basic-packages
    root.nixosModules.systems-beryllium
    root.nixosModules.home-manager-users-server
    root.nixosModules.core-postgres
    root.nixosModules.services-kanidm
    root.nixosModules.services-firezone

    # Load the deployment config from our homelab.toml
    ({...}: {
      config.deployment = homelab.machines.beryllium.deployment;
    })
  ];
}
