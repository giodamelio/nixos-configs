# gatus — status page (gatus.gio.ninja). Not wired to the fleet.services registry
# (the den gatus aspect is standalone gio.gatus.checks); the curated check list is
# ported verbatim. ICMP checks need CAP_NET_RAW. Converted from
# nix/hosts/carbon/gatus.nix.
_: {
  den.aspects.carbon.nixos = {
    gio.gatus = {
      enable = true;
      checks = {
        google = {
          name = "Google";
          group = "External";
          url = "https://google.com";
          status = 200;
          maxResponseTime = "500ms";
          interval = "5m";
        };
        grafana = {
          name = "Grafana";
          url = "http://Grafana.gio.ninja/api/health";
          status = 200;
          maxResponseTime = "300ms";
          interval = "5m";
        };
        pocket-id = {
          name = "Pocket ID";
          url = "http://login.gio.ninja/healthz";
          status = 204;
          maxResponseTime = "300ms";
          interval = "5m";
        };
        mealie = {
          name = "Mealie";
          url = "http://mealie.gio.ninja/";
          status = 200;
          maxResponseTime = "300ms";
          interval = "5m";
        };
        gallium = {
          name = "Gallium";
          group = "Hosts";
          type = "icmp";
          host = "gallium.gio.ninja";
        };
        carbon = {
          name = "Carbon";
          group = "Hosts";
          type = "icmp";
          host = "carbon.gio.ninja";
        };
        immich = {
          name = "Immich";
          url = "http://immich.gio.ninja/";
          status = 200;
          maxResponseTime = "300ms";
          interval = "5m";
        };
      };
    };

    systemd.services.gatus.serviceConfig = {
      CapabilityBoundingSet = "CAP_NET_RAW";
      AmbientCapabilities = "CAP_NET_RAW";
    };
  };

  den.hosts.x86_64-linux.carbon.services.gatus = {
    endpoint = {
      domain = "gatus";
      backend.host = "localhost";
      backend.port = 4444;
    };
    healthcheck.target = "https://gatus.gio.ninja/health";
  };
}
