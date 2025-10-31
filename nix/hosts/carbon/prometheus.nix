{config, ...}: {
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
              host = "lithium1";
            };
          }
        ];
      }
      {
        job_name = "zfs";
        static_configs = [
          {
            targets = [
              "localhost:${builtins.toString config.services.prometheus.exporters.zfs.port}"
            ];
            labels = {
              host = "lithium1";
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
    ];
  };

  # Get stats from our Unifi Controller
  services.unpoller = {
    enable = true;
    unifi.controllers = [
      {
        url = "https://unifi.gio.ninja:8443";
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
