{
  pkgs,
  inputs,
  flake,
  ...
}: let
  homelab = builtins.fromTOML (builtins.readFile ../../../homelab.toml);
in {
  imports = [
    inputs.colmena.nixosModules.deploymentOptions
    inputs.home-manager.nixosModules.home-manager
    inputs.ragenix.nixosModules.default

    ./disko.nix
    ./hardware.nix
    ./prometheus.nix
    ./gatus.nix

    flake.nixosModules.basic-packages
    flake.nixosModules.basic-settings
    flake.nixosModules.monitoring

    # Create server user
    ({pkgs, ...}: {
      users.users.server = {
        extraGroups = ["wheel" "docker" "sound"];
        isNormalUser = true;
        shell = pkgs.zsh;
        openssh.authorizedKeys.keys = homelab.ssh_keys;
      };
      security.sudo.wheelNeedsPassword = false;
      programs.zsh.enable = true;
    })

    # Autosnapshot ZFS and send to NAS
    flake.nixosModules.zfs-backup
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

    # Connect to our self hosted Headscale instance
    {
      services.tailscale = {
        enable = true;
      };
    }
  ];

  # ZFS snapshot browsing
  environment.systemPackages = [pkgs.httm];

  system.stateVersion = "25.05";
}
