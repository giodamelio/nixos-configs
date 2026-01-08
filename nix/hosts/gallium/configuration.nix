{flake, ...}: let
  homelab = builtins.fromTOML (builtins.readFile ../../../homelab.toml);
in {
  imports = [
    # Setup hardware
    ./filesystems.nix
    ./hardware.nix

    flake.nixosModules.basic-packages
    flake.nixosModules.basic-settings
    flake.nixosModules.credential
    flake.nixosModules.onepassword
    flake.nixosModules.lil-scripts
    flake.nixosModules.send-metrics
    flake.nixosModules.reverse-proxy
    flake.nixosModules.zfs-backup
    flake.nixosModules.consul
    flake.nixosModules.nats

    ./postgresql.nix # Shared PostgreSQL database
    ./immich.nix # Photo/Video backup service
    ./garage.nix # Open Source distributed object storage (S3 compatable)
    ./attic.nix # Nix binary cache
    ./jellyfin.nix # Home media server

    # Add some helpful programs
    (
      {pkgs, ...}: {
        environment.systemPackages = with pkgs; [
          dua
          dust
          parted
        ];
      }
    )

    # Setup ZFS auto snapshots
    {
      gio.zfs_backup = {
        enable = true;
        datasets = [
          "boot"
          "boot/garage_metadata"
          "boot/home"
          "boot/nix"
          "boot/reserve"
          "boot/root"
          "tank"
          "tank/attic"
          "tank/attic_storage"
          "tank/garage"
          "tank/hard-drive-dumping-zone"
          "tank/immich"
          "tank/isos"
          "tank/photos-dump"
          "tank/syncthing"
        ];
      };
    }

    # Host specific Consul configs
    {
      services.consul = {
        interface.bind = "enp5s0";
      };
    }

    # Create server user
    (
      {pkgs, ...}: {
        users.users.server = {
          extraGroups = [
            "wheel"
            "docker"
            "sound"
          ];
          isNormalUser = true;
          shell = pkgs.zsh;
          openssh.authorizedKeys.keys = homelab.ssh_keys;
        };
        security.sudo.wheelNeedsPassword = false;
        programs.zsh.enable = true;
      }
    )

    (_: {
      networking.hostId = "8425e349";

      nixpkgs.config.allowUnfree = true;

      system.stateVersion = "25.11";
    })
  ];
}
