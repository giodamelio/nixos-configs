_: _: {
  # Pretty Metrics/Logs UI
  services.grafana = {
    enable = true;
    settings = {
      server.http_addr = "0.0.0.0";
      server.http_port = 3000;
    };
    provision.datasources.settings.datasources = [
      {
        name = "Prometheus";
        type = "prometheus";
        access = "proxy";
        url = "http://localhost:9090";
      }
      # {
      #   name = "Loki";
      #   type = "loki";
      #   access = "proxy";
      #   url = "http://localhost:3100";
      # }
    ];
  };

  # Collect and store metrics
  services.prometheus = {
    enable = true;

    exporters = {
      node = {
        enable = true;
        enabledCollectors = [
          "systemd"
        ];
      };
    };

    scrapeConfigs = [
      # Make Prometheus monitor itself
      {
        job_name = "prometheus";
        scrape_interval = "5s";
        static_configs = [
          {
            targets = [
              "localhost:9090"
            ];
          }
        ];
      }
      # Monitor data from node_exporter
      {
        job_name = "node";
        scrape_interval = "10s";
        static_configs = [
          {
            targets = [
              "localhost:9100"
            ];
            labels = {
              alias = "zirconium.gio.ninja";
            };
          }
        ];
      }
    ];
  };

  # Allow traffic from within the Netbird network
  networking.firewall.interfaces.wt0.allowedTCPPorts = [
    9090 # Prometheus
    3000 # Grafana
  ];
}
