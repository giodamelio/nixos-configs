{
  root,
  super,
  homelab,
  inputs,
  ...
}: _: {
  imports = [
    # Encrypted Secrets
    inputs.ragenix.nixosModules.default

    # Disk layout
    super.disko

    # Hardware
    super.hardware

    # Boot with grub
    root.nixosModules.core.bootloader-grub

    # Add giodamelio user with Home Manager config
    super.user-giodamelio

    # Basic packages I want on every system
    root.nixosModules.basic-packages
    root.nixosModules.basic-packages-desktop
    root.nixosModules.basic-settings

    # Software Development tools
    super.development

    super.greetd # Minimal Login Manager
    super.firefox # Setup Firefox
    super.keyd # Easy key rebinding
    super.hyprland # Hyperland WM
    super.cosmic # Experimental COSMIC DE
    super.sanoid # Autosnapshot ZFS with sanoid
    super.monitoring # Export metrics
    super.streamdeck # StreamDeck stuff

    (_: {
      virtualisation.docker = {
        enable = true;
      };
      programs.ssh.startAgent = true;

      networking.hostId = "3c510ad9";

      nixpkgs.config.allowUnfree = true;

      # Load the deployment config from our homelab.toml
      inherit (homelab.machines.cadmium) deployment;
    })
  ];
}
