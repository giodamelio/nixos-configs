{lib, ...}: {
  boot.initrd.availableKernelModules = ["xhci_pci" "ahci" "usbhid" "sd_mod"];
  boot.initrd.kernelModules = ["dm-snapshot"];
  boot.kernelModules = ["kvm-intel"];
  boot.extraModulePackages = [];

  networking.useDHCP = lib.mkDefault true;

  time.timeZone = "Etc/UTC";

  networking = {
    hostName = "carbon";
    hostId = "3a06cc0b";
  };

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
  hardware.cpu.intel.updateMicrocode = true;
}
