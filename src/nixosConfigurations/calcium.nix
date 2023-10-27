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

    root.nixosModules.basic-packages
    root.nixosModules.systems-calcium

    # Load the deployment config from our homelab.toml
    # (_: {
    #   config.deployment = homelab.machines.beryllium.deployment;
    # })
  ];
}
