{
  config,
  lib,
  ...
}: {
  boot = {
    kernelModules = ["kvm-intel"];
    extraModulePackages = [];

    initrd = {
      kernelModules = [];
      availableKernelModules = ["ahci" "xhci_pci" "usb_storage" "usbhid" "sd_mod" "sdhci_pci"];
      supportedFilesystems = ["zfs"];
    };

    loader = {
      systemd-boot = {
        enable = true;
        consoleMode = "auto";
        netbootxyz.enable = true;
      };

      efi.canTouchEfiVariables = true;
    };

    zfs.forceImportRoot = false;
    supportedFilesystems = ["zfs"];
  };

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  networking.useDHCP = lib.mkDefault true;
  networking.hostName = "manganese";
  networking.hostId = "cf399625";

  time.timeZone = "America/Los_Angeles";

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
