{
  root,
  super,
  homelab,
  ...
}: _: {
  imports = [
    # Disk layout
    super.disko

    # Hardware
    super.hardware

    # Basic packages I want on every system
    root.nixosModules.basic-packages
    root.nixosModules.basic-settings

    # Autosnapshot ZFS and send to NAS
    root.nixosModules.core.zfs-backup
    (_: {
      gio.services.zfs_backup = {
        enable = true;
        makeRecvUser = true;
        datasets = [
          "boot/home"
          "boot/nix"
          "boot/root"
          "tank/garage"
          "tank/isos"
          "tank/photos-dump"
          "tank/syncthing"
        ];
      };
    })

    # Setup Caddy
    root.nixosModules.core.caddy

    # Wireguard Mesh
    super.wireguard-mesh

    # Expose Monitoring
    root.nixosModules.core.monitoring

    # Add server user
    root.nixosModules.users.server

    # Garage distributed block storage
    super.garage

    ({pkgs,...}: {
      networking.hostId = "8425e349";

      services.samba = {
        enable = true;
        package = pkgs.samba4Full;
        openFirewall = true;

        extraConfig = ''
          server smb encrypt = required
          server min protocol = SMB3_00
        '';

        shares = {
          hard-drive-dumping-zone = {
            path = "/mnt/hard-drive-dumping-zone";
            comment = "Dumping zone for data from old hard drives";
            browseable = "yes";
            writable = "yes";
            "force user" = "samba-guest";
          };
        };
      };

      services.samba-wsdd = {
        enable = true;
        openFirewall = true;
      };

      users = {
        groups.samba-guest = {};
        users.samba-guest = {
          isSystemUser = true;
          description = "Samba guest users";
          group = "samba-guest";
          home = "/var/empty";
          createHome = false;
          shell = pkgs.shadow;
        };
      };

      # Load the deployment config from our homelab.toml
      inherit (homelab.machines.gallium) deployment;
    })
  ];
}
