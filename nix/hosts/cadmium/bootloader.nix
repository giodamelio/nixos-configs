{
  inputs,
  perSystem,
  ...
}: {
  imports = [
    "${inputs.boot-selector-switch}/nixos-module"
  ];

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

    boot-selector-switch = {
      enable = true;
      package = perSystem.boot-selector-switch.efi-shim;
      installMode = "systemd-boot-entry";
      positionMap = {
        "1" = "nixos-latest.conf";
        "2" = "windows_11-Pro.conf";
        "3" = "netbootxyz.conf";
      };
    };
  };
}
