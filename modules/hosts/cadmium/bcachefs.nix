# Tiered build-cache filesystem: the MX500 SSD in front of the WD's second half.
_: {
  den.aspects.cadmium-bcachefs.nixos = {lib, ...}: {
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
        mountpoint = "/home/giodamelio/.cache/builds";
        mountOptions = ["nofail"];
        # Unmounted on purpose: mount.bcachefs ignores X-mount.subdir, and
        # subvolumes already appear as directories under the root mount.
        subvolumes = {
          cargo = {};
          sccache = {};
        };
      };
    };

    # disko hardcodes neededForBoot for bcachefs; a dead cache disk must not
    # stop cadmium from booting.
    fileSystems."/home/giodamelio/.cache/builds".neededForBoot = lib.mkForce false;
  };
}
