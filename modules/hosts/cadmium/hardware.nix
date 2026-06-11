# cadmium hardware — boot modules, NetworkManager, pipewire audio, bluetooth,
# game/Teensy udev rules, Windows-compatible hardware clock. Copied from
# nix/hosts/cadmium/hardware.nix and wrapped as a contribution to the cadmium
# host aspect (import-tree loads every modules/**.nix as a flake-parts module,
# so a raw NixOS module can't live here directly).
_: {
  den.aspects.cadmium.nixos = {
    pkgs,
    config,
    lib,
    modulesPath,
    ...
  }: {
    imports = [
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

    boot.initrd.availableKernelModules = ["xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod"];
    boot.initrd.kernelModules = ["amdgpu"];
    boot.kernelModules = ["kvm-intel" "amdgpu" "iwlwifi" "vhost_vsock"];
    boot.extraModulePackages = [];

    networking.useDHCP = lib.mkDefault true;
    networking.networkmanager.enable = true;

    # Make hardware clock compatable with Windows
    time.hardwareClockInLocalTime = true;

    time.timeZone = "America/Los_Angeles";

    networking.hostName = "cadmium";

    # Setup sound
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      audio.enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
    };

    services.udev.packages = [
      # Udev Rules for game controllers
      pkgs.game-devices-udev-rules

      # Udev rules for Teensy development
      pkgs.teensy-udev-rules
    ];

    # Enable Bluetooth
    hardware.bluetooth.enable = true;
    hardware.bluetooth.powerOnBoot = true;
    hardware.enableAllFirmware = true;
    services.blueman.enable = true;

    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
    hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  };
}
