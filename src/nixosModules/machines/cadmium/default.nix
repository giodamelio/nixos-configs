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

    # Setup user programs/services
    super.home-manager
    root.nixosModules.core.modern-coreutils-replacements # Fancy versions of some coreutils
    root.nixosModules.services.atuin # Shell History Search

    # Basic packages I want on every system
    root.nixosModules.basic-packages
    root.nixosModules.basic-packages-desktop
    root.nixosModules.basic-settings

    # Thunar File Browser
    root.nixosModules.core.thunar

    # Autosnapshot ZFS and send to NAS
    root.nixosModules.core.zfs-backup
    (_: {
      gio.services.zfs_backup = {
        enable = true;
        syncToGallium = true;
        datasets = [
          "tank/home"
          "tank/nix"
          "tank/root"
        ];
      };
    })

    # Software Development tools
    super.development

    super.firefox # Setup Firefox
    super.keyd # Easy key rebinding
    super.hyprland # Hyperland WM
    super.cosmic # Experimental COSMIC DE
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
