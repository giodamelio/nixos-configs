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

    # Add server user
    root.nixosModules.users.server

    # Autosnapshot ZFS and send to NAS
    # root.nixosModules.core.zfs-backup
    # (_: {
    #   gio.services.zfs_backup = {
    #     enable = true;
    #     syncToGallium = true;
    #     datasets = [
    #       "tank/home"
    #       "tank/nix"
    #       "tank/root"
    #     ];
    #   };
    # })

    ({pkgs, ...}: {
      networking.hostId = "cf399625";

      # ZFS snapshot browsing
      environment.systemPackages = [pkgs.httm];

      # Load the deployment config from our homelab.toml
      inherit (homelab.machines.manganese) deployment;
    })
  ];
}
