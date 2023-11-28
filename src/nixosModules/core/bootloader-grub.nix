_: _: {
  boot.loader = {
    grub = {
      enable = true;
      efiSupport = true;
    };

    efi.canTouchEfiVariables = true;
  };
}
