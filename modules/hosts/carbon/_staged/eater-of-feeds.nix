# eater-of-feeds — Google Reader API backend, a gradient-deployed app slot. The
# vhost + DNS + consul come from the fleet endpoint (reverseProxy facet disabled);
# the password moves to a fleet.secrets credential on the unit. Converted from
# nix/hosts/carbon/eater-of-feeds.nix.
_: {
  den.aspects.carbon.nixos = {
    gio.deployedApps.eater-of-feeds = {
      description = "Feed reader backend implementing Google Reader API";
      listener = {
        type = "port";
        port = 38291;
      };
      reverseProxy.enable = false; # vhost via fleet.services below
      gradient.project = "default/eater-of-feeds";
    };

    systemd.services.eater-of-feeds.environment = {
      DATABASE_URL = "sqlite:///var/lib/eater-of-feeds/eater-of-feeds.db?mode=rwc";
      USERNAME = "giodamelio";
      PASSWORD_FILE = "/run/credentials/eater-of-feeds.service/eater-of-feeds-password";
      BASE_URL = "https://eater-of-feeds.gio.ninja";
      RUST_LOG = "info,eater_of_feeds=trace,tower_http=trace";
    };
  };

  den.hosts.x86_64-linux.carbon.services.eater-of-feeds = {
    endpoint = {
      domain = "eater-of-feeds";
      backend.host = "localhost";
      backend.port = 38291;
    };
    healthcheck.target = "https://eater-of-feeds.gio.ninja/";
  };

  fleet.secrets.eater-of-feeds-password = {
    origin = "carbon";
    use.carbon.services.eater-of-feeds.type = "credential";
  };
}
