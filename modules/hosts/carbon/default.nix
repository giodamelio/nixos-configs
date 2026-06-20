# carbon — HP EliteDesk Mini (NixOS). The "important services" host: OIDC
# (pocket-id), the monitoring stack (prometheus/loki/grafana/gatus), the CI/CD
# cluster (forgejo/gradient/restate/hooks), netdata parent, the LAN DHCP/router
# (hammond), and an authoritative DNS replica. Migrated from nix/hosts/carbon/.
# Hardware + disko live in sibling files (also carbon.nixos contributions);
# services arrive as their own files.
#
# No Home-Manager user — the `server` system account is defined inline below
# (define-user + user-shell batteries), matching the old inline users.users.server
# + homeModules.users-server.
{den, ...}: let
  homelab = builtins.fromTOML (builtins.readFile ../../../homelab.toml);
in {
  den.hosts.x86_64-linux.carbon = {
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

    # Authoritative DNS replica (gallium serves the same zone; see fleet.dns).
    dns.serve.enable = true;

    # Static networking (was gio.homelab.networking.carbon + homelab/static-network).
    network = {
      mode = "static";
      interfaces.eno1 = {
        address = "10.30.0.10";
        prefixLength = 24;
        gateway = "10.30.0.1";
        ula = "fd7f:148b:0a27:30::10/64";
      };
    };

    # NFS mesh client: mounts gallium's /tank/forgejo + /tank/paperless over
    # WireGuard (mounts declared in nfs.nix). WG keys are auto-generated.
    nfs = {
      enable = true;
      wgIp = "10.200.0.2";
    };

    # The `server` user with its Home-Manager environment (the old
    # homeModules.users-server). Matches gallium's server user; carbon's account
    # was wheel-only (no docker/sound).
    users.server.aspect.includes = [
      den.batteries.define-user
      (den.batteries.user-shell "zsh")

      den.aspects.lil-scripts
      den.aspects.git
      den.aspects.neovim
      den.aspects.zsh
      den.aspects.atuin
      {
        user = {
          extraGroups = ["wheel"];
          openssh.authorizedKeys.keys = homelab.ssh_keys;
        };
        homeManager = {
          home.stateVersion = "25.05";
          programs.git.enable = true;
          gio.nix-activate-config.activation = {system = "nixos";};
        };
      }
    ];
  };

  # Host NixOS feature aspects (the old Blueprint imports that den.default does
  # not already provide). Same infra set as gallium; per-service files arrive
  # alongside this one. mtls is intentionally NOT ported (removed fleet-wide).
  den.aspects.carbon.includes = [
    den.aspects.lil-scripts
    den.aspects.onepassword
    den.aspects.comin
    den.aspects.zfs-backup
    den.aspects.postgresql
    den.aspects.nats
    den.aspects.send-metrics
    den.aspects.deployed-apps # gio.deployedApps + gradient-deployer (eater/yesman)
    den.aspects.gatus # status page (gio.gatus)
  ];

  # Host-specific config (merges with hardware.nix + disko.nix + service files).
  den.aspects.carbon.nixos = {
    lib,
    pkgs,
    ...
  }: {
    environment.systemPackages = [pkgs.pgcli]; # was carbon's postgresql.nix

    networking = {
      hostId = "3a06cc0b";
      firewall = {
        enable = true;
        allowPing = true;
      };
      nftables.enable = true;
    };

    # Consul: serve the read-only web UI locally and bind the cluster to eno1.
    # The old external read-only consul vhost is dropped (mTLS removed; reach
    # the UI over the VPN).
    services.consul = {
      webUi = lib.mkForce true;
      interface.bind = "eno1";
    };

    gio.zfs_backup = {
      enable = true;
      datasets = [
        "tank"
        "tank/home"
        "tank/nix"
        "tank/reserve"
        "tank/root"
        "tank/microvms"
      ];
    };

    nixpkgs.config.allowUnfree = true;
    system.stateVersion = "25.11";
  };
}
