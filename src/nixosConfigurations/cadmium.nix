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
    root.disko.systems.cadmium

    # Hardware
    root.nixosModules.systems-hardware-cadmium

    # Boot with grub
    root.nixosModules.core-bootloader-grub

    # Basic packages I want on every system
    root.nixosModules.basic-packages
    root.nixosModules.basic-settings

    # Autosnapshot with Sanoid
    root.nixosModules.services-sanoid

    # Add giodamelio user with Home Manager config
    root.nixosModules.users-giodamelio
    (_: {
      environment.systemPackages = [
        root.homeConfigurations.giodamelio.activationPackage
      ];
    })

    # Add Hyprland WM
    root.nixosModules.services-hyprland

    # Start some services
    root.nixosModules.services-tailscale

    (_: {
      networking.hostId = "3c510ad9";

      # Load the deployment config from our homelab.toml
      deployment = homelab.machines.cadmium.deployment;
    })
  ];
}
