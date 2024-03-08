{super, ...}: {modulesPath, ...}: {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    super.disko
  ];

  boot.initrd.availableKernelModules = [
    "ahci"
    "xhci_pci"
    "virtio_pci"
    "virtio_scsi"
    "sd_mod"
    "sr_mod"
  ];
  boot.initrd.kernelModules = [];
  boot.kernelModules = [];
  boot.extraModulePackages = [];
}
