{lib, ...}: {
  nixpkgs.hostPlatform = "aarch64-linux";

  networking.hostName = "rhodium";

  sdImage.compressImage = false;

  # hardware.raspberry-pi."4".apply-overlays-dtmerge.enable = false;
  # hardware.deviceTree.enable = true;

  console.enable = true;
  # boot.kernelParams = [
  #   "console=ttyS1,115200n8"
  #   # "console=tty0"
  # ];
  boot.kernelParams = [
    # "console=ttyAMA0,115200n8"
    # "console=ttyS0,115200n8"
    "console=ttyAMA0,115200n8"
    # "console=tty0"
    "loglevel=7"
    "earlycon"
  ];

  # Disable wifi and bluetooth
  # boot.blacklistedKernelModules = [
  #   "brcmfmac"
  #   "brcmutil"
  #   "hci_uart"
  #   "btbcm"
  #   "bluetooth"
  # ];

  hardware.enableRedistributableFirmware = lib.mkDefault true;

  # No ZFS on this host
  boot.supportedFilesystems.zfs = lib.mkForce false;

  # Allow missing modules — the RPi kernel doesn't have dw-hdmi
  # which vc4 depends on, but it's not needed at boot
  boot.initrd.allowMissingModules = true;
}
