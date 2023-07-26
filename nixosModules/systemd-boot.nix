{ inputs, ... }@flakeContext:
{ config, lib, pkgs, modulesPath, ... }:
{
  imports = [ ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}
