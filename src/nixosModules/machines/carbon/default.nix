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

    # Autosnapshot with Sanoid
    root.nixosModules.services.sanoid
    (_: {
      gio.services.zfs_backup = {
        enable = true;
        datasets = [
          "tank/home"
          "tank/nix"
          "tank/root"
        ];
      };
    })

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
