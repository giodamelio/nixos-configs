# garage S3 object storage on gallium. Three secrets (rpc/admin/metrics) move
# from gio.credentials to fleet.secrets credential use-sites on garage.service —
# the settings already read them from /run/credentials/garage.service/<name>, so
# the paths are unchanged. Four endpoints (s3 + wildcard bucket/web + admin) and
# the consul registration become fleet.services. Converted from
# nix/hosts/gallium/garage.nix.
_: {
  den.aspects.gallium.nixos = {pkgs, ...}: {
    environment.shellAliases = {
      garage = "garage -c /etc/garage.toml";
    };

    services.garage = {
      enable = true;
      package = pkgs.garage_2;
      settings = {
        db_engine = "sqlite";
        replication_factor = 1;

        rpc_bind_addr = "[::]:3901";
        rpc_public_addr = "127.0.0.1:3901";
        rpc_secret_file = "/run/credentials/garage.service/garage-rpc-secret";

        s3_api = {
          s3_region = "garage";
          api_bind_addr = "[::]:3900";
          root_domain = ".s3.garage.gio.ninja";
        };

        s3_web = {
          bind_addr = "[::]:3902";
          root_domain = ".web.garage.gio.ninja";
          index = "index.html";
        };

        k2v_api = {
          api_bind_addr = "[::]:3904";
        };

        admin = {
          api_bind_addr = "[::]:3903";
          admin_token_file = "/run/credentials/garage.service/garage-admin-token";
          metrics_token_file = "/run/credentials/garage.service/garage-metrics-token";
        };

        # Secrets are mounted by systemd creds.
        allow_world_readable_secrets = true;
      };
    };

    # Dedicated (non-dynamic) user so the ZFS dataset mounts work.
    users.users.garage = {
      isSystemUser = true;
      group = "garage";
    };
    users.groups.garage = {};
    systemd.services.garage.serviceConfig = {
      DynamicUser = false;
      User = "garage";
      Group = "garage";
    };
  };

  den.hosts.x86_64-linux.gallium.services.garage = {
    endpoints = {
      s3 = {
        domain = "s3.garage";
        backend.host = "localhost";
        backend.port = 3900;
      };
      s3-buckets = {
        domain = "*.s3.garage";
        backend.host = "localhost";
        backend.port = 3900;
      };
      web = {
        domain = "*.web.garage";
        backend.host = "localhost";
        backend.port = 3902;
      };
      admin = {
        domain = "admin.garage";
        backend.host = "localhost";
        backend.port = 3903;
      };
    };
    consul = {
      address = "s3.garage.gio.ninja";
      port = 443;
    };
    healthcheck.target = "https://admin.garage.gio.ninja/health";
    "prometheus-endpoint" = {
      target = "admin.garage.gio.ninja";
      scheme = "https";
      auth.credentialsFile = "/run/credentials/prometheus.service/garage_metrics_token";
    };
  };

  # Secret names are hyphenated (fleet.secrets requires [a-z0-9-]); the blobs are
  # re-created under these names on deploy. carbon's prometheus reads its own
  # copy (garage_metrics_token) from agevault, not a push from here.
  fleet.secrets = {
    garage-rpc-secret = {
      origin = "gallium";
      use.gallium.services.garage.type = "credential";
    };
    garage-admin-token = {
      origin = "gallium";
      use.gallium.services.garage.type = "credential";
    };
    garage-metrics-token = {
      origin = "gallium";
      use.gallium.services.garage.type = "credential";
    };
  };
}
