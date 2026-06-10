# Disko layout for rhodium, preserved in den aspect form. Inactive — it was
# commented out under Blueprint too. To enable: uncomment the block below and
# add `inputs` to this file's function arguments.
_: {
  # den.aspects.rhodium.nixos = {inputs, ...}: {
  #   imports = [inputs.disko.nixosModules.disko];
  #   disko.devices.disk.sd = {
  #     type = "disk";
  #     device = "/dev/disk/by-id/mmc-GD4QT_0x527a53fc";
  #     content = {
  #       type = "gpt";
  #       partitions = {
  #         firmware = {
  #           size = "512M";
  #           type = "EF00";
  #           content = {
  #             type = "filesystem";
  #             format = "vfat";
  #             mountpoint = "/boot/firmware";
  #           };
  #         };
  #         root = {
  #           size = "100%";
  #           content = {
  #             type = "filesystem";
  #             format = "ext4";
  #             mountpoint = "/";
  #           };
  #         };
  #       };
  #     };
  #   };
  # };
}
