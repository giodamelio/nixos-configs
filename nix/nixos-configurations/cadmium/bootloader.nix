{ lib, ... }: {
  boot.loader = {
    grub = {
      enable = lib.mkDefault true;
      efiSupport = true;
      device = "nodev";
      useOSProber = true;
    };

    efi.canTouchEfiVariables = true;
  };
}
