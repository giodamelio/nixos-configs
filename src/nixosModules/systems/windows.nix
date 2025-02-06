{
  root,
  homelab,
  ...
}: {config, ...}: {
  imports = [
    root.nixosModules.partitions-windows
    root.nixosModules.basic-packages
    root.nixosModules.basic-settings
    root.nixosModules.users-server
  ];

  config = {
    # Load the deployment settings from our homelab.toml
    inherit (homelab.machines.windows) deployment;

    # Set the hostname
    networking.hostName = "windows";
    networking.hostId = "f92eef93";

    # Setup hyperv kernel modules etc
    virtualisation.hypervGuest.enable = true;

    # Setup Bootloader
    boot.loader.efi.canTouchEfiVariables = true;
    boot.loader.systemd-boot.enable = true;
    boot.loader.systemd-boot.netbootxyz.enable = true;
  };
}
