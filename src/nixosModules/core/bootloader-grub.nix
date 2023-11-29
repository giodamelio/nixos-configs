_: _: {
  boot.loader = {
    grub = {
      enable = true;
      efiSupport = true;
      device = "nodev";
    };

    efi.canTouchEfiVariables = true;
  };
}
