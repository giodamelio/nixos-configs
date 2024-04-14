_: {
  pkgs,
  config,
  ...
}: let
  db_name = "tsdb";
  user_name = db_name;
in {
  # Setup Prometheus
  services.prometheus = {
    enable = true;
    listenAddress = "127.0.0.1";

    # Start some exporters
    exporters = {
      node = {
        enable = true;
        enabledCollectors = ["systemd"];
        listenAddress = "127.0.0.1";
      };
    };

    # Scrape those exporters
    scrapeConfigs = [
      {
        job_name = "node_exporter";
        static_configs = [
          {
            targets = [
              "127.0.0.1:${toString config.services.prometheus.exporters.node.port}"
            ];
            labels = {
              host = "zirconium";
            };
          }
        ];
      }
    ];
  };

  # Setup TimescaleDB database
  gio.services.postgres = {
    enable = true;
    timescaledb = true;
    databases = [db_name];
  };
  # Map telegraf system user to correct username
  services.postgresql = {
    authentication = ''
      # Allow unix socket connections with a username map for tsdb
      local ${db_name} ${user_name} peer map=tsdb

      # Allow local access to only tsdb without a password
      host ${db_name} grafana samehost trust
    '';
    identMap = ''
      tsdb telegraf ${user_name}
    '';
  };

  # Configure Telegraf to send stats to to TSDB
  services.telegraf = {
    enable = true;
    extraConfig = {
      inputs = {
        # System Stats
        cpu = {};
        disk = {};
        diskio = {};
        kernel = {};
        linux_sysctl_fs = {};
        mem = {};
        net = {
          # Setting this to false is deprecated
          # See: https://github.com/influxdata/telegraf/blob/master/plugins/inputs/net/README.md
          ignore_protocol_stats = true;
        };
        netstat = {};
        nstat = {};
        processes = {};
        smart = {
          path_smartctl = "${pkgs.smartmontools}/bin/smartctl";
          path_nvme = "${pkgs.nvme-cli}/bin/nvme";
        };
        swap = {};
        system = {};
        systemd_units = [
          {unittype = "service";}
          {unittype = "timer";}
        ];
        zfs = {};

        # Monitor PostgreSQL
        postgresql = {
          address = "host=/run/postgresql user=${db_name} sslmode=disable";
        };

        # Monitor Wireguard
        wireguard = {};
      };
      outputs.postgresql = {
        connection = "host=/run/postgresql dbname=${db_name} user=${db_name} sslmode=disable";

        # Make it work with TSDB
        tags_as_foreign_keys = true;
        create_templates = [
          "CREATE EXTENSION IF NOT EXISTS timescaledb"
          "CREATE TABLE {{ .table }} ({{ .columns }})"
          "SELECT create_hypertable({{ .table|quoteLiteral }}, by_range('time', INTERVAL '1 week'), if_not_exists := true)"
        ];
      };
    };
  };

  # Give Telegraf CAP_NET_ADMIN so it can talk to Wireguard via netlink
  systemd.services.telegraf.serviceConfig = {
    CapabilityBoundingSet = "CAP_NET_ADMIN";
    AmbientCapabilities = "CAP_NET_ADMIN";
  };

  # Load the OAuth id/secret for Grafana
  age.secrets.grafana-defguard-oauth-client-id = {
    file = ../../../../secrets/grafana-defguard-oauth-client-id.age;
    owner = "grafana";
    group = "grafana";
  };
  age.secrets.grafana-defguard-oauth-client-secret = {
    file = ../../../../secrets/grafana-defguard-oauth-client-secret.age;
    owner = "grafana";
    group = "grafana";
  };

  # Setup Grafana
  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "127.0.0.1";
        domain = "grafana.gio.ninja";
        root_url = "https://grafana.gio.ninja";
      };

      auth.disable_login_form = true;
      "auth.generic_oauth" = {
        enabled = true;
        name = "Defguard";
        icon = "signin";
        allow_sign_up = true;
        scopes = "openid profile email groups";
        auth_url = "https://defguard.gio.ninja/api/v1/oauth/authorize";
        token_url = "https://defguard.gio.ninja/api/v1/oauth/token";
        api_url = "https://defguard.gio.ninja/api/v1/oauth/userinfo";

        # Map rules from OAuth groups
        role_attribute_path = "contains(groups[*], 'grafana-admin') && 'Admin' || contains(groups[*], 'grafana-editor') && 'Editor' || 'Viewer'";

        client_id = "$__file{${config.age.secrets.grafana-defguard-oauth-client-id.path}}";
        client_secret = "$__file{${config.age.secrets.grafana-defguard-oauth-client-secret.path}}";
      };
    };
  };

  # Cloudflare Token Secret
  age.secrets.cloudflare-token.file = ../../../../secrets/cloudflare-token.age;

  # Get HTTPS Certificate from LetsEncrypt
  security.acme = {
    acceptTerms = true;

    certs."grafana.gio.ninja" = {
      email = "gio@damelio.net";
      dnsProvider = "cloudflare";
      credentialFiles = {
        CLOUDFLARE_DNS_API_TOKEN_FILE = config.age.secrets.cloudflare-token.path;
      };
    };
    certs."prometheus.gio.ninja" = {
      email = "gio@damelio.net";
      dnsProvider = "cloudflare";
      credentialFiles = {
        CLOUDFLARE_DNS_API_TOKEN_FILE = config.age.secrets.cloudflare-token.path;
      };
    };
  };

  # Use Caddy as a reverse proxy
  services.caddy = {
    enable = true;

    virtualHosts."https://grafana.gio.ninja" = {
      useACMEHost = "grafana.gio.ninja";
      extraConfig = ''
        reverse_proxy localhost:3000
      '';
    };
    virtualHosts."https://prometheus.gio.ninja" = {
      useACMEHost = "prometheus.gio.ninja";
      extraConfig = ''
        reverse_proxy localhost:9090
      '';
    };
  };

  networking.firewall.interfaces."wg0" = {
    allowedTCPPorts = [443 80];
  };
  networking.firewall.interfaces."wg9" = {
    allowedTCPPorts = [443 80];
  };
}
