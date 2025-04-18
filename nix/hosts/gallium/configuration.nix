{ flake, ... }: let
  homelab = builtins.fromTOML (builtins.readFile ../../../homelab.toml);
in {
  imports = [
    # Setup hardware
    ./disko.nix
    ./hardware.nix

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

    # Connect to our self hosted Headscale instance
    {
      services.tailscale = {
        enable = true;
      };
    }

    # Autosnapshot ZFS and send to NAS
    flake.nixosModules.zfs-backup
    (_: {
      gio.services.zfs_backup = {
        enable = true;
        datasets = [
          "boot/root"
          "boot/nix"
          "boot/home"
          "tank/garage"
          "tank/hard-drive-dumping-zone"
          "tank/isos"
          "tank/photos-dump"
          "tank/syncthing"
        ];
      };
    })

    (_: {
      networking.hostId = "8425e349";

      nixpkgs.config.allowUnfree = true;

      system.stateVersion = "25.05";
    })
  ];
}
