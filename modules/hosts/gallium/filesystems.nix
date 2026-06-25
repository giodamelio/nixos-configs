# gallium filesystems — ZFS root pool (boot/*) + EFI. The tank/* datasets are
# auto-mounted by ZFS via boot.zfs.extraPools (see hardware.nix), not declared
# here. Copied from nix/hosts/gallium/filesystems.nix.
_: {
  den.aspects.gallium.nixos = {
    fileSystems."/" = {
      device = "boot/root";
      fsType = "zfs";
    };

    fileSystems."/nix" = {
      device = "boot/nix";
      fsType = "zfs";
    };

    fileSystems."/home" = {
      device = "boot/home";
      fsType = "zfs";
    };

    fileSystems."/boot" = {
      device = "/dev/disk/by-uuid/E22B-1CDA";
      fsType = "vfat";
      options = ["fmask=0022" "dmask=0022"];
    };
  };
}
