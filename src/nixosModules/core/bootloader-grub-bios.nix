{inputs, ...}: _: {
  boot.loader.grub = {
    enable = true;
  };
}
