{inputs, ...}: {
  imports = [
    inputs.disko.nixosModules.disko
  ];

  config = let
    mkZFSDisk = name: id: {
      "${name}" = {
        type = "disk";
        device = "/dev/disk/by-id/${id}";
        content = {
          type = "gpt";
          partitions = {
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
  in {
    disko.devices = {
      disk =
        {
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
        }
        // (mkZFSDisk "hda" "ata-ST6000VN001-2BB186_ZR13SCLC")
        // (mkZFSDisk "hdb" "ata-ST6000VN001-2BB186_ZR13V715")
        // (mkZFSDisk "hdc" "ata-ST6000VN001-2BB186_ZR13TANY")
        // (mkZFSDisk "hdd" "ata-ST6000VN001-2BB186_ZR13V6ZJ");
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
        tank = {
          type = "zpool";
          postCreateHook = "zfs snapshot tank@blank";
          rootFsOptions = {
            compression = "lz4";
            mountpoint = "none";
          };

          datasets = {
            isos = {
              type = "zfs_fs";
              mountpoint = "/tank/isos";
              options = {
                mountpoint = "legacy";
              };
            };
            photos-dump = {
              type = "zfs_fs";
              mountpoint = "/tank/photos-dump";
              options = {
                mountpoint = "legacy";
              };
            };
            syncthing = {
              type = "zfs_fs";
              mountpoint = "/tank/syncthing";
              options = {
                mountpoint = "legacy";
              };
            };
            garage = {
              type = "zfs_fs";
              # mountpoint = "/var/lib/garage/data";
            };
          };
        };
      };
    };
  };
}
