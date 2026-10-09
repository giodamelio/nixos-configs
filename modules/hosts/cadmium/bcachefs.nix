# Tiered build-cache filesystem: the MX500 SSD in front of the WD's second half.
_: {
  den.aspects.cadmium-bcachefs.nixos = {lib, ...}: let
    subvolumes = {
      misc = "/home/giodamelio/.cache/builds";
      cargo = "/home/giodamelio/.cache/builds/cargo";
      sccache = "/home/giodamelio/.cache/builds/sccache";
    };
  in {
    boot.bcache.enable = true;
    boot.supportedFilesystems = ["bcachefs"];

    disko.devices = {
      disk = {
        mx500 = {
          type = "disk";
          device = "/dev/disk/by-id/ata-CT500MX500SSD1_1818E1399FF5";
          content = {
            type = "gpt";
            partitions.bcachefs = {
              size = "100%";
              content = {
                type = "bcachefs";
                filesystem = "builds";
                label = "ssd.mx500";
                extraFormatArgs = ["--discard"];
              };
            };
          };
        };
        # Only the hand-made second partition; sdb1 is the Windows NTFS volume
        # and disko must never see or rewrite this disk's partition table.
        wd4t-part2 = {
          type = "disk";
          device = "/dev/disk/by-id/ata-WDC_WD40EZRZ-22GXCB0_WD-WCC7K6HAFE0H-part2";
          destroy = false;
          content = {
            type = "bcachefs";
            filesystem = "builds";
            label = "hdd.wd4t";
          };
        };
      };

      bcachefs_filesystems.builds = {
        type = "bcachefs_filesystem";
        extraFormatArgs = [
          "--compression=lz4"
          "--background_compression=zstd"
          "--foreground_target=ssd"
          "--promote_target=ssd"
          "--metadata_target=ssd"
          "--background_target=hdd"
        ];
        mountpoint = "/mnt/builds";
        mountOptions = ["nofail"];
        # No subvolume mountpoints: mount.bcachefs ignores X-mount.subdir, so
        # they are bind-mounted from the single /mnt/builds mount instead.
        subvolumes = lib.mapAttrs (_: _: {}) subvolumes;
      };
    };

    fileSystems =
      {
        # disko hardcodes neededForBoot for bcachefs; a dead cache disk must
        # not stop cadmium from booting.
        "/mnt/builds".neededForBoot = lib.mkForce false;
      }
      // lib.mapAttrs' (name: mountpoint:
        lib.nameValuePair mountpoint {
          device = "/mnt/builds/${name}";
          fsType = "none";
          options = ["bind" "nofail" "x-systemd.requires-mounts-for=/mnt/builds"];
        })
      subvolumes;
  };
}
