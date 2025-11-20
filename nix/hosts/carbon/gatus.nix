_: {
  services.gatus = {
    enable = true;
    settings = {
      metrics = true;
      web.port = 4444;
      storage = {
        type = "sqlite";
        path = "/var/lib/gatus/data.db";
      };
      endpoints = [
        {
          name = "Google";
          group = "External";
          url = "https://google.com";
          interval = "5m";
          conditions = [
            "[STATUS] == 200"
            "[RESPONSE_TIME] < 500"
          ];
        }
        {
          name = "JetKVM";
          group = "Services";
          url = "http://jetkvm.gio.ninja";
          interval = "5m";
          conditions = [
            "[STATUS] == 200"
            "[RESPONSE_TIME] < 300"
          ];
        }
        {
          name = "Grafana";
          group = "Services";
          url = "http://Grafana.gio.ninja/api/health";
          interval = "5m";
          conditions = [
            "[STATUS] == 200"
            "[RESPONSE_TIME] < 300"
          ];
        }
        {
          name = "Pocket ID";
          group = "Services";
          url = "http://login.gio.ninja/healthz";
          interval = "5m";
          conditions = [
            "[STATUS] == 204"
            "[RESPONSE_TIME] < 300"
          ];
        }
        {
          name = "Mealie";
          group = "Services";
          url = "http://mealie.gio.ninja/";
          interval = "5m";
          conditions = [
            "[STATUS] == 200"
            "[RESPONSE_TIME] < 300"
          ];
        }
        {
          name = "Gallium";
          group = "Hosts";
          url = "icmp://gallium.gio.ninja";
          conditions = [
            "[CONNECTED] == true"
          ];
        }
        {
          name = "Immich";
          group = "Services";
          url = "http://immich.gio.ninja/";
          interval = "5m";
          conditions = [
            "[STATUS] == 200"
            "[RESPONSE_TIME] < 300"
          ];
        }
      ];
    };
  };

  # Allow Gatus to send ICMP traffic
  systemd.services.gatus = {
    serviceConfig = {
      CapabilityBoundingSet = "CAP_NET_RAW";
      AmbientCapabilities = "CAP_NET_RAW";
    };
  };

  services.gio.reverse-proxy = {
    enable = true;
    virtualHosts = {
      "gatus" = {
        host = "localhost";
        port = 4444;
      };
    };
  };

  gio.services.gatus.consul = {
    name = "gatus";
    address = "gatus.gio.ninja";
    port = 443;
    checks = [
      {
        http = "https://gatus.gio.ninja/health";
        interval = "60s";
      }
    ];
  };
}
