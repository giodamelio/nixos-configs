{
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

  services.gio.reverse-proxy = {
    enable = true;
    virtualHosts = {
      "grafana" = {
        host = "localhost";
        port = 3000;
      };
    };
  };
}
