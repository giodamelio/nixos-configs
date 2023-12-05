_: {
  disko.devices = {
    disk = {
      a = {
        type = "disk";
        device = "/dev/disk/by-id/scsi-SNVMe_INTEL_SSDPEKNW010000_0000_0100_0000_E4D2_5C33_2A5C_5101.";
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
}
