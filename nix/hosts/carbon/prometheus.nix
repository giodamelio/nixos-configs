{config, ...}: let
  exporter_ports.zfs = config.services.prometheus.exporters.zfs.port;
in {
  services.prometheus = {
    enable = true;

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

  gio.loadCredentialEncrypted.services = {
    "unifi-poller" = ["unifi-controller-unpoller-password"];
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
