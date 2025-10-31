{
  services.prometheus = {
    enable = true;

    scrapeConfigs = [
      # {
      #   job_name = "telegraf";
      #   static_configs = [
      #     {
      #       targets = [
      #         "lithium1.h.gio.ninja:9273"
      #       ];
      #       labels = {
      #         host = "lithium1";
      #       };
      #     }
      #   ];
      # }
      # {
      #   job_name = "cloudprober";
      #   static_configs = [
      #     {
      #       targets = [
      #         "lithium1.h.gio.ninja:9313"
      #       ];
      #     }
      #   ];
      #   metric_relabel_configs = [
      #     {
      #       source_labels = ["__name__"];
      #       regex = "(.*)";
      #       target_label = "__name__";
      #       replacement = "cloudprober_$1";
      #       action = "replace";
      #     }
      #   ];
      # }
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
      # {
      #   job_name = "loki";
      #   static_configs = [
      #     {
      #       targets = [
      #         "lithium1.h.gio.ninja:3100"
      #       ];
      #     }
      #   ];
      # }
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
    ];

    # Get OS stats
    exporters.node = {
      enable = true;
      port = 9000;
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
