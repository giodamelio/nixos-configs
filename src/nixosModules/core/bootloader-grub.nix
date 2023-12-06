{ inputs, ... }: _: let
  lib = inputs.nixpkgs.lib;
in {
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
