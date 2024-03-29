_: {
  config,
  lib,
  ...
}: {
  boot.initrd.availableKernelModules = ["xhci_pci" "ahci" "usbhid" "sd_mod"];
  boot.initrd.kernelModules = ["dm-snapshot"];
  boot.kernelModules = ["kvm-intel"];
  boot.extraModulePackages = [];

  networking.useDHCP = lib.mkDefault true;

  time.timeZone = "America/Los_Angeles";

  networking.hostName = "carbon";

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

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
