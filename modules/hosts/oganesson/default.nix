# oganesson — Oracle Cloud Always Free Ampere A1 VM (aarch64): the fleet's
# native ARM builder, so Pi builds stop going through qemu on cadmium. Installed
# with nixos-anywhere building on the target itself (`--build-on remote`).
{den, ...}: {
  den.hosts.aarch64-linux.oganesson = {
    role = "server";
    ssh.hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG1z7NWZYwF1QeRncSpY0x6zgltrBiUhfMHk78n0p0QX";
    users.server.classes = [];
    # OCI hands out the VNIC's private address by DHCP; the public IP is NAT'd
    # in front of it and never appears on the interface.
    network.mode = "dhcp";
    remoteBuilder = {
      enable = true;
      systems = ["aarch64-linux"];
      maxJobs = 2;
      supportedFeatures = ["benchmark" "big-parallel"];
    };
  };

  den.aspects.oganesson.includes = [
    # SSH is closed at OCI, but break glass reopens it to the internet, and the
    # host has a tunnel into the LAN (lan-vpn.nix).
    den.aspects.ssh-internet-facing
    # Push what it builds to cache.gio.ninja, so Pis and cadmium pull aarch64
    # builds instead of compiling them under qemu.
    den.aspects.niks3-client
    # Run the heartbeat collector (pushes to its own Healthchecks check).
    den.aspects.server-heartbeat
    # Rebuilds itself from main; it builds aarch64 natively and holds no state.
    den.aspects.comin
  ];

  den.aspects.oganesson.nixos = {modulesPath, ...}: {
    imports = ["${modulesPath}/profiles/qemu-guest.nix"];

    networking.hostName = "oganesson";

    # From nixpkgs' virtualisation/oci-common.nix. Not imported: it declares
    # label-based filesystems that would fight disko.nix.
    boot = {
      kernelParams = [
        "nvme.shutdown_timeout=10"
        "nvme_core.shutdown_timeout=10"
        "console=tty1"
        "console=ttyAMA0,115200"
        # Leave the 12 GB for builds; ZFS would otherwise let ARC take nearly all.
        "zfs.zfs_arc_max=${toString (2 * 1024 * 1024 * 1024)}"
      ];
      initrd.availableKernelModules = ["virtio_pci" "virtio_scsi" "xhci_pci" "usbhid" "sd_mod"];
      # OCI firmware doesn't keep NVRAM boot entries reliably; install GRUB to
      # the removable-media path the firmware always tries.
      loader.efi.canTouchEfiVariables = false;
      loader.grub = {
        enable = true;
        device = "nodev";
        efiSupport = true;
        efiInstallAsRemovable = true;
        # ~60 MB per kernel+initrd on the 1G ESP.
        configurationLimit = 10;
      };
      supportedFilesystems = ["zfs"];
      zfs.forceImportRoot = false;
      # disko names the vdev by partition label; scanning there doesn't depend
      # on the paravirtualized disk exposing a stable by-id serial.
      zfs.devNodes = "/dev/disk/by-partlabel";
    };
    networking.hostId = "69b4167c";
    networking.timeServers = ["169.254.169.254"];

    networking = {
      firewall.enable = true;
      nftables.enable = true;
    };

    zramSwap.enable = true;

    # A build box on a fixed boot volume: keep it from filling up.
    nix.settings = {
      max-jobs = "auto";
      cores = 0;
      min-free = 10 * 1024 * 1024 * 1024;
      max-free = 30 * 1024 * 1024 * 1024;
    };
    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };

    system.stateVersion = "26.11";
  };
}
