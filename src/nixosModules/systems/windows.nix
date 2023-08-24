{
  root,
  inputs,
  homelab,
  ...
}: {
  config,
  lib,
  pkgs,
  ...
}: let
  rootDisk = "/dev/sda";
in {
  imports = [
    inputs.disko.nixosModules.disko

    root.nixosModules.basic-packages
    root.nixosModules.basic-settings
    root.nixosModules.users-server
  ];

  config = {
    # Load the deployment settings from our homelab.toml
    deployment = homelab.machines.windows.deployment;

    # Set the hostname
    networking.hostName = "windows";

    # Setup the partitions/mounts
    disko.devices = root.disko.simple-efi {disk = rootDisk;};

    # Setup hyperv kernel modules etc
    virtualisation.hypervGuest.enable = true;

    # Setup Bootloader
    boot.loader.efi.canTouchEfiVariables = true;
    boot.loader.systemd-boot.enable = true;
    boot.loader.systemd-boot.netbootxyz.enable = true;
  };
}
