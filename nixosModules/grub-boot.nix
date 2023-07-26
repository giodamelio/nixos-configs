{ inputs, ... }@flakeContext:
{ config, lib, pkgs, modulesPath, ... }:
{
  boot.growPartition = true;
  boot.loader.grub = {
    device = "nodev";
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
}
