{...}: {
  pkgs,
  config,
  ...
}: {
  age.secrets.cert_idm_gio_ninja.file = ../../../secrets/cert_cloudflare_gio_ninja.age;

  # Get HTTPS certificates from LetsEncrypt for Kanidm
  security.acme = {
    acceptTerms = true;
    defaults.email = "gio@damelio.net";

    certs."idm.gio.ninja" = {
      dnsProvider = "cloudflare";
      credentialsFile = config.age.secrets.cert_idm_gio_ninja.path;
      group = config.systemd.services.kanidm.serviceConfig.Group;
    };
  };

  # Start Kanidm
  services.kanidm = let
    cert_dir = config.security.acme.certs."idm.gio.ninja".directory;
  in {
    enableServer = true;
    serverSettings = {
      bindaddress = "0.0.0.0:8443";

      origin = "https://idm.gio.ninja";
      domain = "idm.gio.ninja";

      # Certificates from the security.acme module
      tls_key = "${cert_dir}/key.pem";
      tls_chain = "${cert_dir}/fullchain.pem";

      online_backup = {
        path = "/var/lib/kanidm/backups/";
        schedule = "@daily";
        versions = 50;
      };
    };

    enableClient = true;
    clientSettings = {
      uri = "https://idm.gio.ninja";
    };
  };

  # Use Caddy to reverse proxy
  services.caddy = {
    enable = true;
    group = "kanidm";

    virtualHosts."https://idm.gio.ninja" = {
      useACMEHost = "idm.gio.ninja";
      extraConfig = ''
        reverse_proxy https://localhost:8443 {
          transport http {
            tls_insecure_skip_verify
          }
        }
      '';
    };
  };

  # Open up firewall port
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [443];
  };
}
