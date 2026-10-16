# carbon — HP EliteDesk Mini (NixOS). The "important services" host: OIDC
# (pocket-id), the monitoring stack (prometheus/loki/grafana), the CI/CD
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
    consul = {
      enable = true;
      server = true;
      # Loopback-only (consul's default client_addr); reach it via ssh -L 8500:127.0.0.1:8500.
      webUi = true;
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
    nfs.enable = true;

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

  fleet.backups.zfs.carbon = [
    "bowl/postgresql"
    "bowl/pocket-id"
    "bowl/forgejo"
    "bowl/paperless"
    "bowl/grafana"
    "bowl/prometheus"
    "bowl/loki"
    "bowl/netdata"
    "bowl/hass"
    "bowl/mealie"
    "bowl/matter-server"
  ];

  # Host NixOS feature aspects (the old Blueprint imports that den.default does
  # not already provide). Same infra set as gallium; per-service files arrive
  # alongside this one. mtls is intentionally NOT ported (removed fleet-wide).
  # TEMP(NIXOS-103): minimal first boot. Service files wait in ./_staged and
  # return wave by wave; comin stays out until origin/main matches carbon.
  den.aspects.carbon.includes = [
    den.aspects.lil-scripts
    den.aspects.server-heartbeat
    # den.aspects.onepassword
    # REMIND-ME-TO: Re-enable comin once origin/main matches what is deployed (NIXOS-119) date_passed=2026-10-22
    # den.aspects.comin
    den.aspects.zfs-backup
    den.aspects.postgresql
    den.aspects.nats
    den.aspects.send-metrics
    # den.aspects.deployed-apps # gio.deployedApps + gradient-deployer (eater/yesman)
  ];

  # Host-specific config (merges with hardware.nix + disko.nix + service files).
  den.aspects.carbon.nixos = {pkgs, ...}: {
    environment.systemPackages = [pkgs.pgcli]; # was carbon's postgresql.nix

    # The old carbon's 17 cluster in bowl/postgresql is pg_upgraded by hand (NIXOS-117).
    # REMIND-ME-TO: rm -rf /var/lib/postgresql/17 and destroy bowl/postgresql@pre-pg18 and @post-pg18 on carbon (NIXOS-118) date_passed=2026-10-22
    services.postgresql.package = pkgs.postgresql_18;

    networking = {
      hostId = "3a06cc0b";
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
