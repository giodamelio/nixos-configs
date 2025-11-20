{config, ...}: let
  exporter_ports.zfs = config.services.prometheus.exporters.zfs.port;
in {
  services.prometheus = {
    enable = true;
    checkConfig = "syntax-only";

    scrapeConfigs = [
      {
        job_name = "gatus";
        static_configs = [
          {
            targets = [
              "gatus.gio.ninja"
            ];
          }
        ];
      }
      {
        job_name = "pocket-id";
        static_configs = [
          {
            targets = [
              "localhost:9464"
            ];
          }
        ];
      }
      {
        job_name = "loki";
        static_configs = [
          {
            targets = [
              "localhost:3100"
            ];
          }
        ];
      }
      {
        job_name = "node";
        static_configs = [
          {
            targets = [
              "localhost:9000"
            ];
            labels = {
              host = "carbon";
            };
          }
          {
            targets = [
              "gallium.gio.ninja:9000"
            ];
            labels = {
              host = "gallium";
            };
          }
        ];
      }
      {
        job_name = "zfs";
        static_configs = [
          {
            targets = [
              "localhost:${builtins.toString exporter_ports.zfs}"
            ];
            labels = {
              host = "carbon";
            };
          }
          {
            targets = [
              "gallium.gio.ninja:${builtins.toString exporter_ports.zfs}"
            ];
            labels = {
              host = "gallium";
            };
          }
        ];
      }
      {
        job_name = "unpoller";
        static_configs = [
          {
            targets = [
              "localhost:9130"
            ];
          }
        ];
      }
      {
        job_name = "postgres";
        static_configs = [
          {
            targets = [
              "localhost:9187"
            ];
            labels = {
              host = "carbon";
            };
          }
          {
            targets = [
              "gallium.gio.ninja:9187"
            ];
            labels = {
              host = "gallium";
            };
          }
        ];
      }
      {
        job_name = "restate";
        static_configs = [
          {
            targets = [
              "localhost:5122"
            ];
          }
        ];
      }
      {
        job_name = "immich_api";
        metrics_path = "/metrics/api";
        static_configs = [
          {
            targets = [
              "immich.gio.ninja"
            ];
          }
        ];
      }
      {
        job_name = "immich_microservices";
        metrics_path = "/metrics/microservices";
        static_configs = [
          {
            targets = [
              "immich.gio.ninja"
            ];
          }
        ];
      }
      {
        job_name = "immich_stats";
        metrics_path = "/metrics/stats";
        static_configs = [
          {
            targets = [
              "immich.gio.ninja"
            ];
          }
        ];
      }
      {
        job_name = "immich_jobs";
        scheme = "https";
        metrics_path = "/api/w/main/jobs/run_wait_result/p/u/gio/convert_immich_job_stats_to_prometheus";
        static_configs = [
          {
            targets = [
              "windmill.gio.ninja"
            ];
          }
        ];
        authorization = {
          type = "Bearer";
          credentials = "tmoxuQTiIE4WRICfHsSAJ9uO7niEBNsY";
        };
      }
      {
        job_name = "rustmailer";
        static_configs = [
          {
            targets = [
              "rustmailer.gio.ninja"
            ];
          }
        ];
        authorization = {
          type = "Bearer";
          credentials = "CbAZP7V9G7cRjfbsrgkFK8kE";
        };
      }
      {
        job_name = "garage";
        static_configs = [
          {
            targets = [
              "admin.garage.gio.ninja"
            ];
          }
        ];
        authorization = {
          type = "Bearer";
          credentials_file = "/run/credentials/prometheus.service/garage_metrics_token";
        };
      }
    ];
  };

  # Get stats from our Unifi Controller
  services.unpoller = {
    enable = true;
    unifi.controllers = [
      {
        url = "https://unifi.gio.ninja";
        verify_ssl = false;
        user = "unpoller";
        pass = "/run/credentials/unifi-poller.service/unifi-controller-unpoller-password";

        # Extra info to send to Loki
        save_ids = true;
        save_events = true;
        save_alarms = true;
        save_anomalies = true;
      }
    ];
    influxdb.disable = true;
    loki.url = "http://localhost:3100";
  };

  # Load some credentials into our systemd services
  gio.credentials = {
    enable = true;
    services = {
      "prometheus" = {
        loadCredentialEncrypted = ["garage_metrics_token"];
      };
      "unifi-poller" = {
        loadCredentialEncrypted = ["unifi-controller-unpoller-password"];
      };
    };
  };

  services.gio.reverse-proxy = {
    enable = true;
    virtualHosts = {
      "prometheus" = {
        host = "localhost";
        port = 9090;
      };
    };
  };
}
