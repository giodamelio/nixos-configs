{
  services.gatus = {
    enable = true;
    openFirewall = true;
    settings = {
      metrics = true;
      storage = {
        type = "sqlite";
        path = "/var/lib/gatus/data.db";
      };
      endpoints = let
        mkPingEndpoint = name: host: {
          inherit name;
          group = "Hosts";
          url = "icmp://${host}";
          interval = "5m";
          conditions = [
            "[CONNECTED] == true"
          ];
        };
      in [
        {
          name = "Headscale";
          url = "https://headscale.gio.ninja/health";
          interval = "5m";
          conditions = [
            "[STATUS] == 200"
            "[BODY].status == pass"
            "[RESPONSE_TIME] < 300"
          ];
        }
        {
          name = "Prometheus";
          url = "http://manganese.h.gio.ninja:9090/-/healthy";
          interval = "5m";
          conditions = [
            "[STATUS] == 200"
            "[RESPONSE_TIME] < 300"
          ];
        }
        {
          name = "Google";
          url = "https://google.com";
          interval = "10m";
          conditions = [
            "[STATUS] == 200"
          ];
        }
        (mkPingEndpoint "lithium1" "lithium1.h.gio.ninja")
        (mkPingEndpoint "manganese" "manganese.h.gio.ninja")
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
}
