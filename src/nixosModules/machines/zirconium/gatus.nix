_: {
  pkgs,
  lib,
  ...
}: {
  # Setup database
  gio.services.postgres = {
    enable = true;
    databases = ["gatus"];
  };

  # Setup the config
  environment.etc."gatus/config.yml".text = builtins.toJSON {
    web.address = "127.0.0.1";

    metrics = true;

    storage = {
      type = "postgres";
      # Connect over the Unix socket
      path = "host=/run/postgresql dbname=gatus user=gatus sslmode=disable";
    };

    endpoints = let
      # Generate the Gatus key for an endpoint
      slugify = str: (
        builtins.replaceStrings
        [" " "/" "_" "," "."]
        ["-" "-" "-" "-" "-"]
        (lib.strings.toLower str)
      );
      makeKey = group: name: "${slugify group}_${slugify name}";

      # Make the alerts for an endpoint
      makeAlerts = group: name: url: [
        {
          type = "pushover";
          failure-threshold = 3;
          success-threshold = 5;
          send-on-resolved = true;
          description = ''
            Healthcheck Failed

            Status URL:
            https://status.gio.ninja/endpoints/${makeKey group name}

            Service URL:
            ${url}
          '';
        }
      ];

      # Helper to make HTTPS endpoints
      http5m = group: name: url: {
        inherit group name url;
        interval = "5m";
        conditions = [
          "[STATUS] == 200"
        ];
        alerts = makeAlerts group name url;
      };

      # Helper to make ping endpoints
      ping1m = group: name: url: {
        inherit group name url;
        interval = "1m";
        conditions = [
          "[CONNECTED] == true"
        ];
        alerts = makeAlerts group name url;
      };
    in [
      # Our services
      (http5m "Services" "Home Dashboard" "https://home.gio.ninja")
      (http5m "Services" "Gatus" "https://status.gio.ninja")
      (http5m "Services" "Miniflux" "https://miniflux.gio.ninja")
      (http5m "Services" "Paperless" "https://paperless.gio.ninja")
      (http5m "Services" "Defguard" "https://defguard.gio.ninja")
      (http5m "Services" "Grafana" "https://grafana.gio.ninja")
      (http5m "Services" "Prometheus" "https://prometheus.gio.ninja")
      (http5m "Services" "Garage" "https://garage-admin.gio.ninja/health")

      # Ping the hosts
      (ping1m "Hosts" "Ping Zirconium" "icmp://zirconium.gio.ninja")
      (ping1m "Hosts" "Ping Zirconium Public IP" "icmp://zirconium.pub.gio.ninja")
      (ping1m "Hosts" "Ping Carbon" "icmp://carbon.gio.ninja")
      (ping1m "Hosts" "Ping Gallium" "icmp://gallium.gio.ninja")

      # Check the external internet is working
      (http5m "External Internet" "HTTP Google" "https://google.com")
      (ping1m "External Internet" "Ping Google" "icmp://google.com")
    ];
  };

  # Gatus
  systemd.services.gatus = {
    description = "Gatus health dashboard/alerting";
    wantedBy = ["default.target"];
    requires = ["postgresql-ready.target"];
    after = ["postgresql-ready.target"];
    serviceConfig = {
      Type = "simple";
      DynamicUser = true;
      User = "gatus";
      StateDirectory = "gatus";
      ExecStart = "${pkgs.gatus}/bin/gatus";

      # Bind mount in our secrets
      LoadCredentialEncrypted = "gatus-config";
      BindReadOnlyPaths = "%d/gatus-config:/etc/gatus/secrets.yml";

      # Allow Gatus to do pings
      CapabilityBoundingSet = "CAP_NET_RAW";
      AmbientCapabilities = "CAP_NET_RAW";
    };
    environment = {
      GATUS_CONFIG_PATH = "/etc/gatus";
    };
  };

  # Use Caddy as a reverse proxy
  services.caddy = {
    virtualHosts."https://status.gio.ninja" = {
      extraConfig = ''
        reverse_proxy localhost:8080
      '';
    };
  };
}
