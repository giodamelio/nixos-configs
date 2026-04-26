{
  inputs,
  flake,
  ...
}: let
  homelab = builtins.fromTOML (builtins.readFile ../../../homelab.toml);
in {
  imports = [
    inputs.home-manager.nixosModules.home-manager

    # Hardware and boot
    ./hardware.nix

    # Core system modules
    flake.nixosModules.lix
    flake.nixosModules.wifi
    flake.nixosModules.nh
    flake.nixosModules.optnix
    flake.nixosModules.basic-packages
    flake.nixosModules.basic-settings
    flake.nixosModules.onepassword

    # Create giodamelio user
    (
      {pkgs, ...}: {
        users.users.giodamelio = {
          extraGroups = [
            "wheel"
            "networkmanager"
          ];
          isNormalUser = true;
          shell = pkgs.zsh;
          openssh.authorizedKeys.keys = homelab.ssh_keys;
        };
        programs.zsh.enable = true;
      }
    )

    (_: {
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      networking.hostId = "98a5ee60";

      nixpkgs.config.allowUnfree = true;

      system.stateVersion = "26.05";
    })
  ];
}
