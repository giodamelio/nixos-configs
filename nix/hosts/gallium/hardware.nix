{
  config,
  lib,
  ...
}: {
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod" "sr_mod" "sdhci_pci" ];
  boot.initrd.kernelModules = [];
  boot.kernelModules = ["kvm-intel"];
  boot.extraModulePackages = [];

  networking.useDHCP = lib.mkDefault true;

  time.timeZone = "America/Los_Angeles";

  networking.hostName = "gallium";

  boot.loader = {
    systemd-boot = {
      enable = true;
      consoleMode = "auto";
      netbootxyz.enable = true;
    };

    efi.canTouchEfiVariables = true;
  };
  boot.zfs.forceImportRoot = true;
  boot.zfs.extraPools = ["boot"];
  boot.supportedFilesystems = ["zfs"];
  boot.initrd.supportedFilesystems = ["zfs"];

  hardware.enableRedistributableFirmware = true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
