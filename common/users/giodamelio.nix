{ config, pkgs, ... }:

{
  # TODO: should probabaly enable this
  # users.mutableUsers = false;

  users.users.giodamelio = {
    isNormalUser = true;
    shell = pkgs.fish;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFbUQ/gUuzZbOtBPseVWL1GVrjP08JqdNwHdndQgH+Am giodamelio@penguin"
    ];
  };

  home-manager.users.giodamelio = import ../../home/giodamelio/${config.networking.hostName}.nix;
}
