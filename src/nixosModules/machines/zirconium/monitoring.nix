_: {
  config,
  lib,
  ...
}: let
  makeNodeExporterConfig = host: address: {
    targets = [
      "${address}:${toString config.services.prometheus.exporters.node.port}"
    ];
    labels = {
      inherit host;
    };
  };
  makeZfsExporterConfig = host: address: {
    targets = [
      "${address}:${toString config.services.prometheus.exporters.zfs.port}"
    ];
    labels = {
      inherit host;
    };
  };
in {
  # Run TimescaleDB
  gio.services.postgres = {
    enable = true;
    timescaledb = true;
    databases = ["metrics"];
    impostare = {
      databases = [{name = "metrics";}];
      extensions = [
        {
          name = "timescaledb";
          database = "metrics";
        }
      ];
      users = [
        {
          name = "grafana";
          systemd_password_credential = "grafana_postgres_password";
        }
        {
          name = "telegraf";
          systemd_password_credential = "telegraf-postgres-password";
        }
      ];
      database_permissions = [
        {
          role = "telegraf";
          permissions = ["CONNECT"];
          databases = ["metrics"];
        }
      ];
      schema_permissions = [
        {
          role = "telegraf";
          permissions = ["CREATE"];
          database = "metrics";
          schemas = ["public"];
          make_default = true;
        }
      ];
      table_permissions = [
        {
          role = "telegraf";
          permissions = ["ALL"];
          database = "metrics";
          tables = "ALL";
          make_default = true;
        }
        {
          role = "grafana";
          permissions = ["SELECT"];
          database = "metrics";
          tables = "ALL";
          make_default = true;
        }
      ];
    };
  };

  # Allow PostgreSQL to be accessed from the Wireguard Mesh
  networking.firewall.interfaces.wg9.allowedTCPPorts = [5432];

  # Allow access to the metrics database from the local network
  services.postgresql.authentication = lib.mkAfter ''
    host metrics grafana samehost scram-sha-256
  '';
  # services.postgresql.authentication = lib.mkAfter ''
  #   host metrics grafana samehost scram-sha-256
  #   host metrics telegraf samenet scram-sha-256
  # '';

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
        # TODO: fix this
        # smart = {
        #   path_smartctl = "${pkgs.smartmontools}/bin/smartctl";
        #   path_nvme = "${pkgs.nvme-cli}/bin/nvme";
        # };
        swap = {};
        system = {};
        systemd_units = [
          {unittype = "service";}
          {unittype = "timer";}
        ];
        zfs = {
          poolMetrics = true;
          datasetMetrics = true;
        };

        # TODO: Fix this, what are the minimum permissions it needs to function
        # Monitor PostgreSQL
        # postgresql = {
        #   address = "host=/run/postgresql user=telegraf sslmode=disable";
        # };

        # Monitor Wireguard
        wireguard = {};
      };
      outputs.postgresql = {
        connection = "host=/run/postgresql dbname=metrics user=telegraf sslmode=disable";

        # Make it work with TSDB
        tags_as_foreign_keys = true;
        create_templates = [
          "CREATE TABLE {{ .table }} ({{ .columns }})"
          "SELECT create_hypertable({{ .table|quoteLiteral }}, by_range('time', INTERVAL '1 week'), if_not_exists := true)"
        ];
      };
    };
  };

  systemd.services.telegraf = {
    # Don't start Telegraf until PostgreSQL is ready for it
    requires = ["postgresql-ready.target"];
    after = ["postgresql-ready.target"];

    # Give Telegraf CAP_NET_ADMIN so it can talk to Wireguard via netlink
    serviceConfig = {
      CapabilityBoundingSet = "CAP_NET_ADMIN";
      AmbientCapabilities = "CAP_NET_ADMIN";
    };
  };

  # Setup Prometheus
  services.prometheus = {
    enable = true;
    listenAddress = "127.0.0.1";

    # Scrape those exporters
    scrapeConfigs = [
      {
        job_name = "node_exporter";
        static_configs = [
          (makeNodeExporterConfig "zirconium" "127.0.0.1")
          (makeNodeExporterConfig "carbon" "carbon.gio.ninja")
          (makeNodeExporterConfig "gallium" "gallium.gio.ninja")
        ];
      }
      {
        job_name = "zfs";
        static_configs = [
          (makeZfsExporterConfig "carbon" "carbon.gio.ninja")
          (makeZfsExporterConfig "gallium" "gallium.gio.ninja")
        ];
      }
      {
        job_name = "gatus";
        scheme = "https";
        static_configs = [
          {
            targets = [
              "status.gio.ninja"
            ];
            labels = {
              host = "zirconium";
            };
          }
        ];
      }
      {
        job_name = "garage";
        scheme = "https";
        static_configs = [
          {
            targets = [
              "garage-admin.gio.ninja"
            ];
            labels = {
              host = "gallium";
            };
          }
        ];
      }
    ];
  };

  # Load the OAuth id/secret for Grafana
  systemd.services.grafana.serviceConfig.LoadCredentialEncrypted = [
    "grafana-defguard-oauth-client-id"
    "grafana-defguard-oauth-client-secret"
  ];

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

        # FIXME: I know you are not supposed to hardcode these
        client_id = "$__file{/run/credentials/grafana.service/grafana-defguard-oauth-client-id}";
        client_secret = "$__file{/run/credentials/grafana.service/grafana-defguard-oauth-client-secret}";
      };
    };
  };

  # Use Caddy as a reverse proxy
  services.caddy = {
    virtualHosts."https://grafana.gio.ninja" = {
      extraConfig = ''
        reverse_proxy localhost:3000
      '';
    };
    virtualHosts."https://prometheus.gio.ninja" = {
      extraConfig = ''
        reverse_proxy localhost:9090
      '';
    };
  };
}
