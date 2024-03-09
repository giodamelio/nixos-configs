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
              alias = "zirconium";
            };
          }
          {
            targets = [
              "cadmium.n.gio.ninja:9100"
            ];
            labels = {
              alias = "cadmium";
            };
          }
        ];
      }
    ];
  };

  # # Log indexing
  # services.loki = {
  #   enable = true;
  #
  #   configuration = {
  #     auth_enabled = false;
  #
  #     server = {
  #       http_listen_port = 3100;
  #       grpc_listen_port = 9096;
  #     };
  #
  #     common = {
  #       instance_addr = "127.0.0.1";
  #       path_prefix = "/tmp/loki";
  #       storage.filesystem = {
  #         chunks_directory = "/tmp/loki/chunks";
  #         rules_directory = "/tmp/loki/rules";
  #       };
  #       replication_factor = 1;
  #       ring.kvstore.store = "inmemory";
  #     };
  #
  #     frontend.max_outstanding_per_tenant = 4096;
  #
  #     query_range.results_cache.cache.embedded_cache = {
  #       enabled = true;
  #       max_size_mb = 100;
  #     };
  #
  #     schema_config.configs = [
  #       {
  #         from = "2020-01-01";
  #         store = "tsdb";
  #         object_store = "filesystem";
  #         schema = "v12";
  #         index = {
  #           prefix = "index_";
  #           period = "24h";
  #         };
  #       }
  #     ];
  #   };
  # };
  #
  # # Log ingestion
  # services.promtail = {
  #   enable = true;
  #   configuration = {
  #     server = {
  #       http_listen_port = 9080;
  #       grpc_listen_port = 0;
  #     };
  #
  #     positions.filename = "/tmp/positions.yaml";
  #
  #     clients = [
  #       {
  #         url = "http://localhost:3100/loki/api/v1/push";
  #       }
  #     ];
  #
  #     scrape_configs = [
  #       {
  #         job_name = "journal";
  #         journal = {
  #           json = false;
  #           max_age = "12h";
  #           path = "/var/log/journal";
  #           labels.job = "systemd-journal";
  #         };
  #         relabel_configs = [
  #           {
  #             source_labels = ["__journal__systemd_unit"];
  #             target_label = "unit";
  #           }
  #           {
  #             source_labels = ["__journal__hostname"];
  #             target_label = "host";
  #           }
  #           {
  #             source_labels = ["__journal_priority_keyword"];
  #             target_label = "level";
  #           }
  #           {
  #             source_labels = ["__journal_syslog_identifier"];
  #             target_label = "syslog_identifier";
  #           }
  #         ];
  #       }
  #     ];
  #   };
  # };
  #

  # Make Caddy export Prometheus metrics
  # services.caddy = {
  #   globalConfig = ''
  #     servers {
  #       metrics
  #     }
  #   '';
  # };

  # Allow traffic from within the Netbird network
  networking.firewall.interfaces.wt0.allowedTCPPorts = [
    9090 # Prometheus
    3000 # Grafana
  ];
}
