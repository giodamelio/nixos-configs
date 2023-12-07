{
  root,
  inputs,
  ...
}:
inputs.nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";

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

    # Add giodamelio user with Home Manager config
    root.nixosModules.users-giodamelio
    root.nixosModules.home-manager-users-giodamelio

    # Add Hyprland WM
    root.nixosModules.services-hyprland

    # Start some services
    root.nixosModules.services-tailscale

    (_: {
      networking.hostId = "3c510ad9";
    })
  ];
}
