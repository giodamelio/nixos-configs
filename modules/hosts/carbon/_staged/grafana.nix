# grafana — metrics/logs UI (grafana.gio.ninja). secret_key moves from
# gio.credentials to a fleet.secrets credential on grafana.service ($__file points
# at the credential path). Datasources stay pointed at the prometheus/loki vhosts.
# Converted from nix/hosts/carbon/grafana.nix.
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
        security.secret_key = "$__file{/run/credentials/grafana.service/grafana-secret-key}";
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
  };

  den.hosts.x86_64-linux.carbon.services.grafana = {
    endpoint = {
      domain = "grafana";
      backend.host = "localhost";
      backend.port = 3000;
    };
    healthcheck.target = "https://grafana.gio.ninja/api/health";
  };

  fleet.secrets.grafana-secret-key = {
    origin = "carbon";
    use.carbon.services.grafana.type = "credential";
  };
}
