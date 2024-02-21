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
    root.nixosModules.basic-packages-desktop
    root.nixosModules.basic-settings

    root.nixosModules.services-greetd # Minimal Login Manager
    root.nixosModules.services-firefox # Setup Firefox
    root.nixosModules.services-keyd # Easy key rebinding

    # Autosnapshot with Sanoid
    root.nixosModules.services-sanoid
    (_: {
      gio.services.zfs_backup = {
        enable = true;
        datasets = [
          "tank/home"
          "tank/nix"
          "tank/root"
        ];
      };
    })

    # Add giodamelio user with Home Manager config
    root.nixosModules.users-giodamelio
    inputs.home-manager.nixosModules.home-manager
    (_: {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.giodamelio = root.homeModules.user-giodamelio;
    })

    # Add Hyprland WM
    root.nixosModules.services-hyprland

    # Experimental COSMIC DE
    root.nixosModules.services-cosmic

    # Start some services
    root.nixosModules.services-tailscale

    (_: {
      networking.hostId = "3c510ad9";

      # Load the deployment config from our homelab.toml
      deployment = homelab.machines.cadmium.deployment;
    })
  ];
}
