_: {
  pkgs,
  config,
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

    storage = {
      type = "postgres";
      # Connect over the Unix socket
      path = "host=/run/postgresql dbname=gatus user=gatus sslmode=disable";
    };

    endpoints = let
      http5m = group: name: url: {
        inherit group name url;
        interval = "5m";
        conditions = [
          "[STATUS] == 200"
        ];
      };
      ping1m = group: name: url: {
        inherit group name url;
        interval = "1m";
        conditions = [
          "[CONNECTED] == true"
        ];
      };
    in [
      # Our services
      (http5m "Services" "Home Dashboard" "https://home.gio.ninja")
      (http5m "Services" "Gatus" "https://status.gio.ninja")
      (http5m "Services" "Miniflux" "https://miniflux.gio.ninja")
      (http5m "Services" "Paperless" "https://paperless.gio.ninja")
      (http5m "Services" "Defguard" "https://defguard.gio.ninja")

      # Ping the hosts
      (ping1m "Hosts" "Ping Zirconium" "icmp://zirconium.gio.ninja")
      (ping1m "Hosts" "Ping Zirconium Public IP" "icmp://zirconium.pub.gio.ninja")
      (ping1m "Hosts" "Ping Carbon" "icmp://carbon.gio.ninja")

      # Check the external internet is working
      (http5m "External Internet" "HTTP Google" "https://google.com")
      (ping1m "External Internet" "Ping Google" "icmp://google.com")
    ];
  };

  # Gatus
  systemd.services.gatus = {
    description = "Gatus health dashboard/alerting";
    wantedBy = ["default.target"];
    requires = ["postgres-ready.service"];
    after = ["postgres-ready.service"];
    serviceConfig = {
      Type = "simple";
      DynamicUser = true;
      User = "gatus";
      StateDirectory = "gatus";
      ExecStart = "${pkgs.gatus}/bin/gatus";

      # Allow Gatus to do pings
      CapabilityBoundingSet = "CAP_NET_RAW";
      AmbientCapabilities = "CAP_NET_RAW";
    };
    environment = {
      GATUS_CONFIG_PATH = "/etc/gatus";
    };
  };

  # Cloudflare Token Secret
  age.secrets.cloudflare-token.file = ../../../../secrets/cloudflare-token.age;

  # Get HTTPS Certificate from LetsEncrypt
  security.acme = {
    acceptTerms = true;

    certs."status.gio.ninja" = {
      email = "gio@damelio.net";
      dnsProvider = "cloudflare";
      credentialFiles = {
        CLOUDFLARE_DNS_API_TOKEN_FILE = config.age.secrets.cloudflare-token.path;
      };
    };
  };

  # Use Caddy as a reverse proxy
  services.caddy = {
    enable = true;

    virtualHosts."https://status.gio.ninja" = {
      useACMEHost = "status.gio.ninja";
      extraConfig = ''
        reverse_proxy localhost:8080
      '';
    };
  };

  networking.firewall.interfaces."wg0" = {
    allowedTCPPorts = [443 80];
  };
  networking.firewall.interfaces."wg9" = {
    allowedTCPPorts = [443 80];
  };
}
