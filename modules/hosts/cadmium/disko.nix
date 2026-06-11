# Disko layout for cadmium — single NVMe with ESP + a `tank` zpool (root, nix,
# home, and the snapshot-heavy giodamelio-tmp dataset). Copied from
# nix/hosts/cadmium/disko.nix and wrapped as a cadmium host aspect
# contribution; the disko input module comes in via the file-scope closure.
{inputs, ...}: {
  den.aspects.cadmium.nixos = {
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
                  acltype = "posixacl";
                  xattr = "sa";
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
              giodamelio-tmp = {
                type = "zfs_fs";
                mountpoint = "/home/giodamelio/tmp";
                options = {
                  mountpoint = "legacy";
                };
              };
            };
          };
        };
      };
    };
  };
}
