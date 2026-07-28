# Prometheus on rhodium, exposed at prometheus.<host>.gio.ninja rather than a
# bare `prometheus` label, so more than one instance can exist in the fleet
# (carbon already owns prometheus.gio.ninja).
#
# Deliberately empty: `host.prometheus.enable` is left false, so the fleet-wide
# services-prometheus bridge does NOT inject every declared prometheus-endpoint.
# Flip that host fact when this instance should scrape the fleet.
_: let
  port = 9090;
  domain = "prometheus.rhodium";
in {
  den.aspects.rhodium.nixos = {
    services.prometheus = {
      enable = true;
      inherit port;
      # Caddy is the only front end.
      listenAddress = "127.0.0.1";
      scrapeConfigs = [];
    };
  };

  # Caddy vhost + DNS record render from this.
  den.hosts.aarch64-linux.rhodium.services.prometheus = {
    endpoint = {
      inherit domain;
      backend.host = "localhost";
      backend.port = port;
    };
    healthcheck.target = "https://${domain}.gio.ninja/-/healthy";
  };
}
