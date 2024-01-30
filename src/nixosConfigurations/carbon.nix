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
    # Disk layout
    inputs.disko.nixosModules.disko
    root.disko.systems.carbon

    # Boot with systemd-boot
    root.nixosModules.core-bootloader-systemd-boot

    # Basic packages I want on every system
    root.nixosModules.basic-packages
    root.nixosModules.basic-settings

    # Add giodamelio user with Home Manager config
    root.nixosModules.users-server

    (_: {
      networking.hostId = "3a06cc0b";

      # Load the deployment config from our homelab.toml
      deployment = homelab.machines.carbon.deployment;
    })
  ];
}
