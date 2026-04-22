{inputs, ...}: {
  imports = [
    inputs.disko.nixosModules.disko
  ];

  config = {
    disko.devices = {
      disk = {
        sd = {
          type = "disk";
          device = "/dev/disk/by-id/mmc-GD4QT_0x527a53fc";
          content = {
            type = "gpt";
            partitions = {
              firmware = {
                size = "512M";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot/firmware";
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
