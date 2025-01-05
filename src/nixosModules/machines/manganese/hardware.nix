_: {
  config,
  lib,
  ...
}: {
  boot.initrd.availableKernelModules = ["ahci" "xhci_pci" "usb_storage" "usbhid" "sd_mod" "sdhci_pci"];
  boot.initrd.kernelModules = [];
  boot.kernelModules = ["kvm-intel"];
  boot.extraModulePackages = [];

  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  time.timeZone = "America/Los_Angeles";

  networking.hostName = "manganese";

  boot.loader = {
    systemd-boot = {
      enable = true;
      consoleMode = "auto";
      netbootxyz.enable = true;
    };

    efi.canTouchEfiVariables = true;
  };
  boot.zfs.forceImportRoot = false;
  boot.supportedFilesystems = ["zfs"];
  boot.initrd.supportedFilesystems = ["zfs"];
}
