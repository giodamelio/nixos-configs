# grafana — metrics/logs UI (grafana.gio.ninja). Datasources point at the
# prometheus/loki vhosts; dashboards live in grafana's own DB.
_: {
  den.aspects.carbon.nixos = {
    services.grafana = {
      enable = true;
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
        ];
      };
    };

    fleet.credentials.needs = ["grafana_secret_key"];
    systemd.services.grafana.serviceConfig.LoadCredentialEncrypted = ["grafana_secret_key"];
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
