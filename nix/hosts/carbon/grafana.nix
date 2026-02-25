{config, ...}: {
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
      security.secret_key = "$__file{${config.gio.credentials.services.grafana.credentialPath.grafana-secret-key}}";
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

  gio.credentials.services.grafana.loadCredentialEncrypted = ["grafana-secret-key"];

  services.gio.reverse-proxy = {
    enable = true;
    virtualHosts = {
      "grafana" = {
        host = "localhost";
        port = 3000;
      };
    };
  };

  gio.services.grafana.consul = {
    name = "grafana";
    address = "grafana.gio.ninja";
    port = 443;
    checks = [
      {
        http = "https://grafana.gio.ninja/api/health";
        interval = "60s";
      }
    ];
  };
}
