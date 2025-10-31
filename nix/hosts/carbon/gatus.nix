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
          url = "https://google.com";
          interval = "5m";
          conditions = [
            "[STATUS] == 200"
            "[RESPONSE_TIME] < 300"
          ];
        }
        {
          name = "JetKVM";
          url = "http://jetkvm.gio.ninja";
          interval = "5m";
          conditions = [
            "[STATUS] == 200"
            "[RESPONSE_TIME] < 300"
          ];
        }
        {
          name = "Grafana";
          url = "http://Grafana.gio.ninja/api/health";
          interval = "5m";
          conditions = [
            "[STATUS] == 200"
            "[RESPONSE_TIME] < 300"
          ];
        }
        {
          name = "Pocket ID";
          url = "http://login.gio.ninja/healthz";
          interval = "5m";
          conditions = [
            "[STATUS] == 204"
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
}
