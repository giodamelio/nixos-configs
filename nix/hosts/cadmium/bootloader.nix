_: {
  boot.loader = {
    systemd-boot = {
      enable = true;
      netbootxyz.enable = true;
      windows = {
        "11-Pro" = {
          efiDeviceHandle = "HD0b65535a2";
          title = "Windows 11 Pro";
        };
      };
    };

    efi.canTouchEfiVariables = true;
  };
}
