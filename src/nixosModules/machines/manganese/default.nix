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
    (_: {
      # Automatically create ZFS snapshots
      services.sanoid = {
        enable = true;

        datasets = let
          defaultSnapshotSettings = {
            hourly = 48;
            daily = 32;
            monthly = 8;
            yearly = 8;

            autosnap = true;
            autoprune = true;
          };
        in {
          "tank/root" = defaultSnapshotSettings;
          "tank/nix" = defaultSnapshotSettings;
          "tank/home" = defaultSnapshotSettings;
        };
      };
    })

    ({pkgs, ...}: {
      networking.hostId = "cf399625";

      # ZFS snapshot browsing
      environment.systemPackages = [pkgs.httm];

      # Load the deployment config from our homelab.toml
      inherit (homelab.machines.manganese) deployment;
    })
  ];
}
