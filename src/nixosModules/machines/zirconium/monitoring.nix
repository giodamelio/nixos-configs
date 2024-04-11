_: {
  config,
  pkgs,
  ...
}: {
  # Load the oauth credentials
  age.secrets.openobserve.file = ../../../../secrets/openobserve.age;

  # OpenObserve
  systemd.services.openobserve = {
    description = "OpenObserve Observability Platform";
    wantedBy = ["default.target" "syslog.target" "network-online.target"];
    serviceConfig = {
      Type = "simple";
      DynamicUser = true;
      User = "openobserve";
      StateDirectory = "openobserve";
      ExecStart = "${pkgs.openobserve}/bin/openobserve";
      EnvironmentFile = config.age.secrets.openobserve.path;
    };
    environment = {
      ZO_DATA_DIR = "/var/lib/openobserve";
    };
  };

  # Cloudflare Token Secret
  age.secrets.cloudflare-token.file = ../../../../secrets/cloudflare-token.age;

  # Get HTTPS Certificate from LetsEncrypt
  security.acme = {
    acceptTerms = true;

    certs."o2.gio.ninja" = {
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

    virtualHosts."https://o2.gio.ninja" = {
      useACMEHost = "o2.gio.ninja";
      extraConfig = ''
        reverse_proxy localhost:5080
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
