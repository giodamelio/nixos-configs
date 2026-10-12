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
        # ~60 MB per distinct kernel+initrd; 20 fits the 4G ESP with room.
        configurationLimit = 20;
      };

      efi.canTouchEfiVariables = true;
    };

    # 8 GB of 32: leave the rest to postgres and the service fleet, so the
    # kernel isn't pushed into zram while ARC holds half of RAM.
    zramSwap.enable = true;
    boot.kernelParams = ["zfs.zfs_arc_max=${toString (8 * 1024 * 1024 * 1024)}"];

    boot.zfs.forceImportRoot = false;
    boot.supportedFilesystems = ["zfs"];
    boot.initrd.supportedFilesystems = ["zfs"];

    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
    hardware.cpu.intel.updateMicrocode = true;
  };
}
