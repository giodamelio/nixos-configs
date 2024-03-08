{inputs, ...}: {
  imports = [
    inputs.disko.nixosModules.disko
  ];

  config = {
    disko.devices = {
      disk = {
        main = {
          type = "disk";
          device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_43554007";
          content = {
            type = "gpt";
            partitions = {
              boot = {
                size = "1M";
                type = "EF02"; # for grub MBR
              };
              ESP = {
                size = "512M";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                };
              };
              root = {
                size = "100%";
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/";
                };
              };
            };
          };
        };
      };
    };
  };
}
