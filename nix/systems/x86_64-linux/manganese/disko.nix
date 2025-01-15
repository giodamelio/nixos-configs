{inputs, ...}: {
  imports = [
    inputs.disko.nixosModules.disko
  ];

  config = {
    disko.devices = {
      disk = {
        main = {
          type = "disk";
          device = "/dev/disk/by-id/ata-SanDisk_SDSSDA120G_173948453212";
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
              postCreateHook = "zfs snapshot tank/root@blank";
            };
            nix = {
              type = "zfs_fs";
              mountpoint = "/nix";
            };
            home = {
              type = "zfs_fs";
              mountpoint = "/home";
            };
          };
        };
      };
    };
  };
}
