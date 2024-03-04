{inputs, ...}: {
  imports = [
    inputs.disko.nixosModules.disko
  ];

  config = {
    disko.devices = {
      disk = {
        a = {
          type = "disk";
          device = "/dev/disk/by-id/nvme-INTEL_SSDPEKNW010T8_BTNH93440UH21P0B";
          content = {
            type = "gpt";
            partitions = {
              ESP = {
                size = "1G";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                };
              };
              zfs = {
                size = "100%";
                content = {
                  type = "zfs";
                  pool = "tank";
                };
              };
            };
          };
        };
      };
      zpool = {
        tank = {
          type = "zpool";
          postCreateHook = "zfs snapshot tank@blank";
          rootFsOptions = {
            compression = "zstd";
            mountpoint = "none";
          };

          datasets = {
            reserve = {
              type = "zfs_fs";
              options = {
                mountpoint = "none";
                reservation = "5G";
              };
            };
            root = {
              type = "zfs_fs";
              mountpoint = "/";
              options = {
                mountpoint = "legacy";
              };
              postCreateHook = "zfs snapshot tank/root@blank";
            };
            nix = {
              type = "zfs_fs";
              mountpoint = "/nix";
              options = {
                mountpoint = "legacy";
              };
            };
            home = {
              type = "zfs_fs";
              mountpoint = "/home";
              options = {
                mountpoint = "legacy";
              };
            };
          };
        };
      };
    };
  };
}
