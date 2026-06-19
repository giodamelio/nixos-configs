# gallium — QNAP TS-462 NAS (NixOS). Storage host: garage S3, attic cache,
# immich, jellyfin media stack, syncthing, samba, plus the fleet NFS exports.
# Migrated from nix/hosts/gallium/. Hardware + ZFS filesystems live in sibling
# files (also gallium.nixos contributions); services arrive as their own aspects.
#
# No Home-Manager user — the `server` system account is defined inline below
# (define-user + user-shell batteries), matching the old inline users.users.server.
{den, ...}: let
  homelab = builtins.fromTOML (builtins.readFile ../../../homelab.toml);
in {
  den.hosts.x86_64-linux.gallium = {
    role = "server";

    # Deployed host, but its ed25519 host key isn't recorded here yet, so it is
    # not a cert sign target. ssh stays enabled (access grants still apply); fill
    # in the real public key later to issue a host certificate.
    ssh.hostKey = null;

    # Consul server (bind interface + retry_join derive from host.network).
    consul = {
      enable = true;
      server = true;
    };

    # Authoritative DNS replica (carbon serves the same zone; see fleet.dns).
    dns.serve.enable = true;

    # Static networking (was gio.homelab.networking.gallium + homelab/static-network).
    network = {
      mode = "static";
      interfaces.enp5s0 = {
        address = "10.30.0.11";
        prefixLength = 24;
        gateway = "10.30.0.1";
        ula = "fd7f:148b:0a27:30::11/64";
      };
    };

    # The `server` system account (no Home-Manager): wheel for passwordless sudo
    # (from basic-settings), docker + sound as on the old host, fleet SSH keys.
    users.server = {
      classes = [];
      aspect.includes = [
        den.batteries.define-user
        (den.batteries.user-shell "zsh")
        {
          user = {
            extraGroups = ["wheel" "docker" "sound"];
            openssh.authorizedKeys.keys = homelab.ssh_keys;
          };
        }
      ];
    };
  };

  # Host NixOS feature aspects (the old Blueprint imports that den.default does
  # not already provide). send-metrics / netdata-child / nats arrive in the NFS
  # + infra task.
  den.aspects.gallium.includes = [
    den.aspects.lil-scripts
    den.aspects.onepassword
    den.aspects.comin
    den.aspects.zfs-backup
  ];

  # Host-specific config (merges with hardware.nix + filesystems.nix).
  den.aspects.gallium.nixos = {pkgs, ...}: {
    environment.systemPackages = with pkgs; [
      dua
      dust
      parted
    ];

    gio.zfs_backup = {
      enable = true;
      datasets = [
        "boot"
        "boot/garage_metadata"
        "boot/home"
        "boot/nix"
        "boot/reserve"
        "boot/root"
        "tank"
        "tank/attic"
        "tank/attic_storage"
        "tank/garage"
        "tank/hard-drive-dumping-zone"
        "tank/immich"
        "tank/isos"
        "tank/photos-dump"
        "tank/syncthing"
        "tank/paperless"
      ];
    };

    networking = {
      hostId = "8425e349";
      firewall = {
        enable = true;
        allowPing = true;
      };
      nftables.enable = true;
    };

    nixpkgs.config.allowUnfree = true;
    system.stateVersion = "25.11";
  };
}
