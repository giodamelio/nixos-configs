# Rough commands to create and mount filesystems
#
# Create zpool
# $ sudo zpool create -R /mnt tank /dev/sda2
#
# Create dataset for root
# $ sudo zfs create -o mountpoint=legacy tank/root
# $ sudo mount -t zfs tank/root /mnt/
#
# Create data for our home directory
# $ sudo zfs create -o mountpoint=legacy tank/home
# $ sudo mount -m -t zfs tank/home /mnt/home
#
# Create dataset to mount the Nix store in
# $ sudo zfs create -o mountpoint=legacy tank/nix
# $ sudo mount -m -t zfs tank/nix /mnt/nix
#
# Create FAT32 EFI/boot partition
# $ sudo mkfs.fat -F 32 /dev/sda1
# $ sudo mount -m /dev/sda1 /mnt/boot
#
# Generate hardware configuration
# $ nixos-generate-config --root /mnt --show-hardware-config
{_}: _: {
  fileSystems."/" = {
    device = "tank/root";
    fsType = "zfs";
  };

  fileSystems."/home" = {
    device = "tank/home";
    fsType = "zfs";
  };

  fileSystems."/nix" = {
    device = "tank/nix";
    fsType = "zfs";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/798E-5846";
    fsType = "vfat";
  };
}
