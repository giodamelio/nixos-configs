{pkgs, ...}: {
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

  # Setup Caddy as a reverse proxy
  systemd.services.caddy.serviceConfig = {
    LoadCredentialEncrypted = [
      "caddy-cloudflare-api-token:/var/lib/credstore/caddy-cloudflare-api-token"
    ];
    Environment = [
      "CLOUDFLARE_API_TOKEN_FILE=%d/caddy-cloudflare-api-token"
    ];
  };
  services.caddy = {
    enable = true;

    package = pkgs.caddy.withPlugins {
      plugins = [
        "github.com/caddy-dns/cloudflare@v0.2.1"
      ];
      hash = "sha256-iRzpN9awuEFsc7hqKzOMNiCFFEv833xhd4LM+VFQedI=";
    };

    globalConfig = ''
      email admin@gio.ninja
    '';

    virtualHosts."https://gatus.gio.ninja" = {
      extraConfig = ''
        tls {
          dns cloudflare {file.{$CLOUDFLARE_API_TOKEN_FILE}}
          resolvers 1.1.1.1
        }
        reverse_proxy localhost:4444
      '';
    };
  };

  networking.firewall.allowedTCPPorts = [
    80
    443
    4444
  ];
}
