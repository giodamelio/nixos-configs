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
        syncToGallium = true;
        datasets = [
          "tank/home"
          "tank/nix"
          "tank/root"
        ];
      };
    })

    # Setup Caddy
    root.nixosModules.core.caddy

    # Wireguard Mesh
    super.wireguard-mesh

    # Expose Monitoring
    root.nixosModules.core.monitoring

    # Miniflux Feed Reader
    super.miniflux

    # Homelab Dashboard
    super.homer

    # Paperless Document Storage
    super.paperless

    # Add server user
    root.nixosModules.users.server

    ({pkgs, ...}: {
      networking.hostId = "3a06cc0b";

      # ZFS snapshot browsing
      environment.systemPackages = [pkgs.httm];

      # Load the deployment config from our homelab.toml
      inherit (homelab.machines.carbon) deployment;
    })
  ];
}
