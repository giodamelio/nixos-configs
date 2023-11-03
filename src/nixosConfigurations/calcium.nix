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
    # Setup for WSL
    inputs.nixos-wsl.nixosModules.default
    (_: {
      wsl.enable = true;
    })

    # Load some basic packages
    root.nixosModules.basic-packages

    # System Specific Confiuration
    root.nixosModules.systems-calcium
    root.nixosModules.home-manager-users-giodamelio

    # Enable some services
    root.nixosModules.services-tailscale

    # Load the deployment config from our homelab.toml
    (_: {
      config.deployment = homelab.machines.calcium.deployment;
    })
  ];
}
