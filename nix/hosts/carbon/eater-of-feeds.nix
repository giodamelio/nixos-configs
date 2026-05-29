_: {
  gio.deployedApps.eater-of-feeds = {
    description = "Feed reader backend implementing Google Reader API";
    listener = {
      type = "port";
      port = 38291;
    };
    reverseProxy = {
      enable = true;
      subdomain = "eater-of-feeds";
    };
    credentials = ["eater-of-feeds-password"];
  };

  systemd.services.eater-of-feeds = {
    environment = {
      DATABASE_URL = "sqlite:///var/lib/eater-of-feeds/eater-of-feeds.db?mode=rwc";
      USERNAME = "giodamelio";
      PASSWORD_FILE = "/run/credentials/eater-of-feeds.service/eater-of-feeds-password";
      BASE_URL = "https://eater-of-feeds.gio.ninja";
      RUST_LOG = "info,eater_of_feeds=trace,tower_http=trace";
    };
  };

  gio.services.eater-of-feeds.consul = {
    name = "eater-of-feeds";
    address = "eater-of-feeds.gio.ninja";
    port = 443;
    checks = [
      {
        http = "https://eater-of-feeds.gio.ninja/";
        interval = "60s";
      }
    ];
  };
}
