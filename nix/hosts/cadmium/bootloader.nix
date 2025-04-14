_: {
  boot.loader = {
    systemd-boot = {
      enable = true;
      netbootxyz = {
        enable = true;
        sortKey = "m_netbootxyz";
      };
      windows = {
        "11-Pro" = {
          efiDeviceHandle = "HD0b65535a2";
          title = "Windows 11 Pro";
          sortKey = "m_windows";
        };
      };
    };

    efi.canTouchEfiVariables = true;
  };
}
