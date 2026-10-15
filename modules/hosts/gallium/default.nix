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

    # ed25519 host key (ssh-keyscan gallium.gio.ninja); enrolls gallium as a cert
    # sign target so peers verify it via the host CA instead of failing on TOFU.
    ssh.hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPdhRUNcKpvd949OChBtkPTytHF6gxGgPuKhyDaAQgEg";

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

    # Fleet NFS over TLS: exports /tank/forgejo + /tank/paperless to carbon (the
    # mounts are declared in carbon's nfs.nix).
    nfs.enable = true;

    # The `server` user with its Home-Manager environment (the old
    # homeModules.users-server: git/neovim/zsh/atuin/lil-scripts + nix-activate;
    # shpool/zmx/modern-coreutils arrive via den.default for HM users). wheel
    # gives passwordless sudo (basic-settings); docker + sound as on the old host.
    users.server.aspect.includes = [
      den.batteries.define-user
      (den.batteries.user-shell "zsh")

      den.aspects.lil-scripts
      den.aspects.git
      den.aspects.neovim
      den.aspects.zsh
      den.aspects.atuin
      den.aspects.claude-code
      {
        user = {
          extraGroups = ["wheel" "docker" "sound"];
          openssh.authorizedKeys.keys = homelab.ssh_keys;
        };
        homeManager = {
          home.stateVersion = "25.05";
          programs.git.enable = true;
          gio.nix-activate-config.activation = {system = "nixos";};

          programs.gio-claude-code = {
            enable = true;
            installPackage = true;
          };
        };
      }
    ];
  };

  # Host NixOS feature aspects (the old Blueprint imports that den.default does
  # not already provide). The netdata child rides in its own file (netdata.nix),
  # like the per-service files.
  den.aspects.gallium.includes = [
    den.aspects.lil-scripts
    den.aspects.onepassword
    den.aspects.comin
    den.aspects.zfs-backup
    den.aspects.postgresql
    den.aspects.nats
    den.aspects.send-metrics
    den.aspects.server-heartbeat
    den.aspects.rayfish
    den.aspects.niks3-client
  ];

  # Host-specific config (merges with hardware.nix + filesystems.nix).
  den.aspects.gallium.nixos = {pkgs, ...}: {
    gio.rayfish.enable = true;

    environment.systemPackages = with pkgs; [
      dua
      dust
      parted
    ];

    gio.zfs_backup = {
      enable = true;
      makeRecvUser = true;
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
