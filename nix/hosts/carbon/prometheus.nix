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
    ];
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
