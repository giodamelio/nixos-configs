{...}: {disk ? "/dev/sda"}: {
  disk.${disk} = {
    device = disk;
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          label = "EFI";
          type = "EF00";
          size = "100M";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
          };
        };
        root = {
          label = "root";
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
}
