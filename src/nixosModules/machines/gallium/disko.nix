{inputs, ...}: {
  imports = [
    inputs.disko.nixosModules.disko
  ];

  config = {
    disko.devices = {
      disk = {
        a = {
          type = "disk";
          device = "/dev/disk/by-id/nvme-WD_BLACK_SN770_1TB_23192N800112";
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
                  pool = "boot";
                };
              };
            };
          };
        };
      };
      zpool = {
        boot = {
          type = "zpool";
          postCreateHook = "zfs snapshot boot@blank";
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
              postCreateHook = "zfs snapshot boot/root@blank";
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
