{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ../../common/global
      ../../common/base-packages.nix
      ../../common/users/giodamelio.nix
    ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "cadmium";
  networking.hostId = "0bfd1077";

  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  # Change the RTC so Windows will have the correrct time
  time.hardwareClockInLocalTime = true;

  # Enable the nix command and flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Enable SSH
  services.openssh = {
    enable = true;
    settings = {
      # PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  # Add an ssh key to the root user
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFbUQ/gUuzZbOtBPseVWL1GVrjP08JqdNwHdndQgH+Am giodamelio@penguin"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAZF+j6HGldFqQdp+CaPaYKGMsFpUsk49jqhb7VtdUvn giodamelio@cadmium"
  ];

  # Enable polkit
  security.polkit.enable = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "22.11"; # Did you read the comment?
}

