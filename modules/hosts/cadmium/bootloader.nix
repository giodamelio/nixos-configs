# cadmium bootloader — systemd-boot with netboot.xyz and Windows entries, plus
# the (currently disabled) physical boot-selector-switch. Copied from
# nix/hosts/cadmium/bootloader.nix; the boot-selector-switch module path comes
# from the file-scope `inputs` closure, its package via perSystem.
{inputs, ...}: {
  den.aspects.cadmium.nixos = {perSystem, ...}: {
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
        enable = false;
        package = perSystem.boot-selector-switch.efi-shim;
        installMode = "systemd-boot-entry";
        positionMap = {
          "1" = "nixos-latest.conf";
          "2" = "windows_11-Pro.conf";
          "3" = "netbootxyz.conf";
        };
      };
    };
  };
}
