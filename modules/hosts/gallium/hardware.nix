# gallium hardware — boot modules, Intel GPU (jellyfin transcoding), systemd-boot
# + netbootxyz, ZFS boot/tank pools. Copied from nix/hosts/gallium/hardware.nix
# and wrapped as a contribution to the gallium host aspect.
_: {
  den.aspects.gallium.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: {
    boot.initrd.availableKernelModules = ["xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod" "sr_mod" "sdhci_pci"];
    boot.initrd.kernelModules = [];
    boot.kernelModules = ["kvm-intel"];
    boot.extraModulePackages = [];

    time.timeZone = "America/Los_Angeles";

    networking.hostName = "gallium";

    hardware.graphics = {
      enable = true;
      extraPackages = with pkgs; [
        intel-media-driver
        vpl-gpu-rt
      ];
    };

    boot.loader = {
      systemd-boot = {
        enable = true;
        consoleMode = "auto";
        netbootxyz.enable = true;
      };

      efi.canTouchEfiVariables = true;
    };
    boot.zfs.forceImportRoot = true;
    boot.zfs.extraPools = ["boot" "tank"];
    boot.supportedFilesystems = ["zfs"];
    boot.initrd.supportedFilesystems = ["zfs"];

    hardware.enableRedistributableFirmware = true;
    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
    hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  };
}
