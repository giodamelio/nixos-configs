{root, ...}: {
  imports = [
    # Setup the bootloader to handle zfs
    root.nixosModules.core-bootloader-zfs
  ];

  config = {
    disko.devices = {
      disk = {
        a = {
          type = "disk";
          device = "/dev/vda";
          content = {
            type = "gpt";
            partitions = {
              ESP = {
                size = "64M";
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
            root = {
              type = "zfs_fs";
              mountpoint = "/";
              options = {
                mountpoint = "legacy";
              };
              postCreateHook = "zfs snapshot tank/root@blank";
            };
          };
        };
      };
    };
  };
}
