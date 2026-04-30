{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: let
  # Chromebook audio (sof-rt5682 / Lillipup-Lindar)
  # UCM profiles not yet upstreamed — build custom alsa-ucm-conf with cros configs
  # Uses let binding + replaceRuntimeDependencies instead of overlay to avoid 1000+ rebuilds
  alsa-ucm-conf-cros = pkgs.alsa-ucm-conf.overrideAttrs (_old: {
    wttsrc = pkgs.fetchFromGitHub {
      owner = "WeirdTreeThing";
      repo = "alsa-ucm-conf-cros";
      rev = "a4e92135fd49e669b5ce096439289e05e25ae90c";
      hash = "sha256:1pwhyffrjh2wviig1k619q0xwr4k20ax0qw7g0z7yfmfcn776fnx";
    };
    postInstall = ''
      cp -r $wttsrc/ucm2/* $out/share/alsa/ucm2/
    '';
  });
in {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = ["xhci_pci" "nvme" "usb_storage" "sd_mod" "sdhci_pci"];
  boot.initrd.kernelModules = [];
  boot.initrd.supportedFilesystems = ["zfs"];
  boot.kernelModules = ["kvm-intel"];
  boot.extraModulePackages = [];
  boot.supportedFilesystems = ["zfs"];
  boot.zfs.devNodes = "/dev/disk/by-id";

  fileSystems."/" = {
    device = "zroot/root";
    fsType = "zfs";
  };

  fileSystems."/nix" = {
    device = "zroot/nix";
    fsType = "zfs";
  };

  fileSystems."/home" = {
    device = "zroot/home";
    fsType = "zfs";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/551A-705A";
    fsType = "vfat";
    options = ["fmask=0022" "dmask=0022"];
  };

  swapDevices = [];

  networking.useDHCP = lib.mkDefault true;
  networking.networkmanager.enable = true;

  time.timeZone = "America/Los_Angeles";

  networking.hostName = "cesium";

  # Chromebook audio: point ALSA at cros UCM configs and swap runtime deps
  environment.sessionVariables.ALSA_CONFIG_UCM2 = "${alsa-ucm-conf-cros}/share/alsa/ucm2";
  system.replaceRuntimeDependencies = [
    {
      original = pkgs.alsa-ucm-conf;
      replacement = alsa-ucm-conf-cros;
    }
  ];
  boot.extraModprobeConfig = ''
    options snd-intel-dspcfg dsp_driver=3
  '';

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
