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

    # ed25519 host key (ssh-keyscan carbon.gio.ninja); enrolls carbon as a cert
    # sign target so peers verify it via the host CA instead of failing on TOFU.
    ssh.hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIX5P0ZXB1SUbiDrm42t19GEsz80dw+yI0GoO0tYlJsn";

    # Consul server (bind interface + retry_join derive from host.network).
    # TEMP(NIXOS-103): off for the minimal first boot; back on with wave 1.
    consul = {
      enable = false;
      server = true;
    };

    # Authoritative DNS replica (gallium serves the same zone; see fleet.dns).
    dns.serve = {
      enable = true;
      # TEMP(NIXOS-103): staged services are missing from carbon's zone; keep
      # clients from caching those gaps once each wave comes back.
      maxTtl = 10;
    };

    # Static networking (was gio.homelab.networking.carbon + homelab/static-network).
    network = {
      mode = "static";
      interfaces.eno1 = {
        address = "10.30.0.10";
        prefixLength = 24;
        gateway = "10.30.0.1";
        ula = "fd7f:148b:0a27:30::10/64";
        vlans = [
          {
            name = "iot0";
            id = 4;
            subnets = [
              "10.40.0.0/16"
              "2604:5500:70cf:fd00::/64"
            ];
          }
        ];
      };
    };

    # Fleet NFS over TLS client: mounts gallium's /tank/forgejo + /tank/paperless
    # (mounts declared in nfs.nix).
    nfs.enable = false; # TEMP(NIXOS-103)

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
  # TEMP(NIXOS-103): minimal first boot. Service files wait in ./_staged and
  # return wave by wave; comin stays out until origin/main matches carbon.
  den.aspects.carbon.includes = [
    den.aspects.lil-scripts
    # den.aspects.onepassword
    # den.aspects.comin
    # den.aspects.zfs-backup
    # den.aspects.postgresql
    # den.aspects.nats
    # den.aspects.send-metrics
    # den.aspects.deployed-apps # gio.deployedApps + gradient-deployer (eater/yesman)
    # den.aspects.gatus # status page (gio.gatus)
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

    nixpkgs.config.allowUnfree = true;
    system.stateVersion = "25.11";
  };
}
