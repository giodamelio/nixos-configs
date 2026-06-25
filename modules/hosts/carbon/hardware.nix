# carbon hardware — HP EliteDesk Mini: boot modules, systemd-boot + netbootxyz,
# Intel KVM + microcode, ZFS. Copied from nix/hosts/carbon/hardware.nix and
# wrapped as a contribution to the carbon host aspect.
_: {
  den.aspects.carbon.nixos = {lib, ...}: {
    boot.initrd.availableKernelModules = ["xhci_pci" "ahci" "usbhid" "sd_mod"];
    boot.initrd.kernelModules = ["dm-snapshot"];
    boot.kernelModules = ["kvm-intel"];
    boot.extraModulePackages = [];

    time.timeZone = "Etc/UTC";

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
    hardware.cpu.intel.updateMicrocode = true;
  };
}
