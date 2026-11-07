# grafana — metrics/logs UI (grafana.gio.ninja)
_: {
  den.aspects.carbon.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.gio.grafana;

    victoriaMetricsUid = "victoriametrics";

    upstreamDashboards = {
      node-exporter-full = pkgs.fetchurl {
        name = "grafana-1860-rev46.json";
        url = "https://grafana.com/api/dashboards/1860/revisions/46/download";
        hash = "sha256-5Y3cXcU11MkB+U2pZIvD49Wue2946Y4YW86LKJlhzqM=";
      };
      process-exporter = pkgs.fetchurl {
        name = "grafana-8378-rev1.json";
        url = "https://grafana.com/api/dashboards/8378/revisions/1/download";
        hash = "sha256-AQJYEaLf/RL1RAb2Nt4o6+PtZLQEL31UBA/IrHqdT/o=";
      };
      victoriametrics-cluster = pkgs.fetchurl {
        name = "grafana-11176-rev65.json";
        url = "https://grafana.com/api/dashboards/11176/revisions/65/download";
        hash = "sha256-QuicGFM4KtNipYTxwVesNtedJzK/F1BRd5iDeFZsjtk=";
      };
      victorialogs-single-node = pkgs.fetchurl {
        name = "grafana-22084-rev12.json";
        url = "https://grafana.com/api/dashboards/22084/revisions/12/download";
        hash = "sha256-7ZwB8CrnE8T5GXGY7rDlXFxkrJvxYclBBQbA2TwswUs=";
      };
    };

    # Two Prometheus-type datasources exist during the parallel run, so a
    # datasource variable would otherwise default to the old one. Pin both the
    # variables and the `${DS_PROMETHEUS}` import placeholders to VictoriaMetrics.
    dashboards =
      pkgs.runCommand "grafana-dashboards" {nativeBuildInputs = [pkgs.jq];}
      ''
        mkdir $out
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: src: ''
            jq --arg uid ${victoriaMetricsUid} '
              (.templating.list[]? | select(.type == "datasource") | .current)
                = {selected: true, text: "VictoriaMetrics", value: $uid}
              | .id = null
            ' ${src} | sed 's/''${DS_PROMETHEUS}/${victoriaMetricsUid}/g' > $out/${name}.json
          '')
          upstreamDashboards)}
      '';
  in {
    options.gio.grafana.oidc = {
      enable = lib.mkEnableOption "Pocket ID login for Grafana (needs the grafana_oidc_* credentials)";
      adminGroup = lib.mkOption {
        type = lib.types.str;
        # REMIND-ME-TO: Decide the Pocket ID admin group name (NIXOS-150) date_passed=2026-12-01
        default = "telemetry_admin";
        description = "Pocket ID group whose members become Grafana server admins; everyone else is denied at login.";
      };
    };

    config = lib.mkMerge [
      {
        services.grafana = {
          enable = true;
          declarativePlugins = [pkgs.grafanaPlugins.victoriametrics-logs-datasource];
          settings = {
            server = {
              http_addr = "127.0.0.1";
              http_port = 3000;
              domain = "grafana.gio.ninja";
              enforce_domain = true;
            };
            analytics.reporting_enabled = false;
            # Must keep its value: it encrypts secrets stored in grafana's DB.
            security.secret_key = "$__file{/run/credentials/grafana.service/grafana_secret_key}";
            # The nixpkgs plugin build is not signed by Grafana Labs.
            plugins.allow_loading_unsigned_plugins = "victoriametrics-logs-datasource";
          };

          provision = {
            enable = true;
            datasources.settings.datasources = [
              {
                name = "Prometheus";
                type = "prometheus";
                url = "https://prometheus.gio.ninja";
                isDefault = true;
                editable = false;
              }
              {
                name = "Loki";
                type = "loki";
                url = "https://loki.gio.ninja";
                editable = false;
              }
              {
                name = "VictoriaMetrics";
                uid = victoriaMetricsUid;
                type = "prometheus";
                url = "http://127.0.0.1:8481/select/0/prometheus";
                editable = false;
              }
              {
                name = "VictoriaLogs";
                uid = "victorialogs";
                type = "victoriametrics-logs-datasource";
                url = "http://127.0.0.1:9428";
                editable = false;
              }
              {
                name = "Alertmanager";
                uid = "alertmanager";
                type = "alertmanager";
                url = "http://127.0.0.1:9093";
                jsonData.implementation = "prometheus";
                editable = false;
              }
            ];
            dashboards.settings.providers = [
              {
                name = "upstream";
                options.path = dashboards;
                allowUiUpdates = false;
              }
            ];
          };
        };

        fleet.credentials.needs = ["grafana_secret_key"];
        systemd.services.grafana.serviceConfig.LoadCredentialEncrypted = ["grafana_secret_key"];
      }

      (lib.mkIf cfg.oidc.enable {
        services.grafana.settings = {
          server.root_url = "https://grafana.gio.ninja";
          "auth.generic_oauth" = {
            enabled = true;
            name = "Pocket ID";
            client_id = "$__file{/run/credentials/grafana.service/grafana_oidc_client_id}";
            client_secret = "$__file{/run/credentials/grafana.service/grafana_oidc_client_secret}";
            scopes = "openid email profile groups";
            auth_url = "https://login.gio.ninja/authorize";
            token_url = "https://login.gio.ninja/api/oidc/token";
            api_url = "https://login.gio.ninja/api/oidc/userinfo";
            use_pkce = true;
            email_attribute_path = "email";
            login_attribute_path = "preferred_username";
            name_attribute_path = "name";
            groups_attribute_path = "groups";
            allowed_groups = cfg.oidc.adminGroup;
            role_attribute_strict = true;
            role_attribute_path = "contains(groups[*], '${cfg.oidc.adminGroup}') && 'GrafanaAdmin'";
            allow_assign_grafana_admin = true;
            auto_login = false;
          };
        };

        fleet.credentials.needs = ["grafana_oidc_client_id" "grafana_oidc_client_secret"];
        systemd.services.grafana.serviceConfig.LoadCredentialEncrypted = [
          "grafana_oidc_client_id"
          "grafana_oidc_client_secret"
        ];
      })
    ];
  };

  den.hosts.x86_64-linux.carbon.services.grafana = {
    endpoint = {
      domain = "grafana";
      backend.host = "localhost";
      backend.port = 3000;
    };
    healthcheck.target = "https://grafana.gio.ninja/api/health";
  };
}
