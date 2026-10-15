# Disko layout for carbon — the internal SSD carries the OS (`root` pool) plus
# bowl's SLOG + L2ARC; the two USB WD drives form the `bowl` mirror for
# per-service datasets.
{inputs, ...}: let
  bowlDisk = device: {
    type = "disk";
    inherit device;
    content = {
      type = "gpt";
      partitions.zfs = {
        size = "100%";
        content = {
          type = "zfs";
          pool = "bowl";
        };
      };
    };
  };
  # Partition members must be full paths: disko only expands bare disk names
  # to a partition labelled `zfs`.
  ssdPart = name: "/dev/disk/by-partlabel/disk-ssd-${name}";
in {
  den.aspects.carbon.nixos = {
    imports = [
      inputs.disko.nixosModules.disko
    ];

    config = {
      # bowl holds no boot-critical mounts; import it after the root pool.
      boot.zfs.extraPools = ["bowl"];

      disko.devices = {
        disk = {
          ssd = {
            type = "disk";
            device = "/dev/disk/by-id/ata-SPCC_Solid_State_Disk_YTAK220406643";
            content = {
              type = "gpt";
              partitions = {
                ESP = {
                  priority = 1;
                  size = "4G";
                  type = "EF00";
                  content = {
                    type = "filesystem";
                    format = "vfat";
                    mountpoint = "/boot";
                  };
                };
                slog = {
                  priority = 2;
                  size = "16G";
                  content = {
                    type = "zfs";
                    pool = "bowl";
                  };
                };
                l2arc = {
                  priority = 3;
                  size = "96G";
                  content = {
                    type = "zfs";
                    pool = "bowl";
                  };
                };
                zfs = {
                  priority = 4;
                  size = "100%";
                  content = {
                    type = "zfs";
                    pool = "root";
                  };
                };
              };
            };
          };
          bowl-a = bowlDisk "/dev/disk/by-id/ata-WDC_WD10SDZW-11UMGS0_WD-WX21A683KL07";
          bowl-b = bowlDisk "/dev/disk/by-id/ata-WDC_WD10SDZW-11UMGS0_WD-WXS1A480XXKA";
        };
        zpool = {
          root = {
            type = "zpool";
            options.ashift = "12";
            postCreateHook = "zfs snapshot root@blank";
            rootFsOptions = {
              compression = "zstd";
              acltype = "posixacl";
              xattr = "sa";
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
                postCreateHook = "zfs snapshot root/root@blank";
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
          bowl = {
            type = "zpool";
            mode.topology = {
              type = "topology";
              vdev = [
                {
                  mode = "mirror";
                  members = ["bowl-a" "bowl-b"];
                }
              ];
              log = [{members = [(ssdPart "slog")];}];
              cache = [(ssdPart "l2arc")];
            };
            options.ashift = "12";
            rootFsOptions = {
              compression = "zstd";
              acltype = "posixacl";
              xattr = "sa";
              mountpoint = "none";
            };
            datasets = {
              reserve = {
                type = "zfs_fs";
                options = {
                  mountpoint = "none";
                  reservation = "10G";
                };
              };
              postgresql = {
                type = "zfs_fs";
                mountpoint = "/var/lib/postgresql";
                options = {
                  mountpoint = "legacy";
                  recordsize = "16k";
                  atime = "off";
                };
              };
              pocket-id = {
                type = "zfs_fs";
                mountpoint = "/var/lib/pocket-id";
                options = {
                  mountpoint = "legacy";
                  atime = "off";
                };
              };
              forgejo = {
                type = "zfs_fs";
                mountpoint = "/var/lib/forgejo";
                options = {
                  mountpoint = "legacy";
                  atime = "off";
                };
              };
              paperless = {
                type = "zfs_fs";
                mountpoint = "/var/lib/paperless";
                options = {
                  mountpoint = "legacy";
                  atime = "off";
                };
              };
              grafana = {
                type = "zfs_fs";
                mountpoint = "/var/lib/grafana";
                options = {
                  mountpoint = "legacy";
                  atime = "off";
                };
              };
              prometheus = {
                type = "zfs_fs";
                # services.prometheus.stateDir defaults to the 2.x-migration name.
                mountpoint = "/var/lib/prometheus2";
                options = {
                  mountpoint = "legacy";
                  atime = "off";
                };
              };
              loki = {
                type = "zfs_fs";
                mountpoint = "/var/lib/loki";
                options = {
                  mountpoint = "legacy";
                  atime = "off";
                };
              };
              netdata = {
                type = "zfs_fs";
                mountpoint = "/var/lib/netdata";
                options = {
                  mountpoint = "legacy";
                  atime = "off";
                };
              };
            };
          };
        };
      };
    };
  };
}
