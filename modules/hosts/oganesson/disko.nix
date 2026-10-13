# Disko layout for oganesson — the single OCI boot volume (paravirtualized,
# /dev/sda): an ESP for GRUB and a ZFS `root` pool, laid out like carbon's.
{inputs, ...}: {
  den.aspects.oganesson.nixos = {
    imports = [inputs.disko.nixosModules.disko];

    disko.devices = {
      disk.boot = {
        type = "disk";
        device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              priority = 1;
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = ["umask=0077"];
              };
            };
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "root";
              };
            };
          };
        };
      };

      zpool.root = {
        type = "zpool";
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
              reservation = "5G";
            };
          };
          root = {
            type = "zfs_fs";
            mountpoint = "/";
            options.mountpoint = "legacy";
          };
          nix = {
            type = "zfs_fs";
            mountpoint = "/nix";
            options = {
              mountpoint = "legacy";
              atime = "off";
            };
          };
          home = {
            type = "zfs_fs";
            mountpoint = "/home";
            options.mountpoint = "legacy";
          };
        };
      };
    };
  };
}
