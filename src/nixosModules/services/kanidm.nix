_: {config, ...}: {
  security.lego = {
    enable = true;
    acceptTerms = true;
    email = "gio@damelio.net";

    certs."testing2.gio.ninja" = {};
    certs."testing3.gio.ninja" = {};
    certs."testing4.gio.ninja" = {};
  };

  services.acme-redirect = {
    enable = true;
    acceptTerms = true;
    email = "gio@damelio.net";

    certs."testing21.gio.ninja" = {};
    certs."testing22.gio.ninja" = {};
    certs."testing23.gio.ninja" = {};
  };

  # Get HTTPS certificates from LetsEncrypt for Kanidm
  security.acme = {
    acceptTerms = true;
    defaults.email = "gio@damelio.net";

    certs."login.gio.ninja" = {
      listenHTTP = ":8080";
    };
  };

  # Load the LetsEncrypt certs as SystemD credentials
  systemd.services.kanidm = {
    serviceConfig = let
      cert_dir = config.security.acme.certs."login.gio.ninja".directory;
    in {
      LoadCredential = [
        "certs:${cert_dir}"
      ];
    };
  };

  # Start Kanidm
  services.kanidm = let
    credentials_directory = "/run/credentials/kanidm.service";
  in {
    enableServer = true;
    serverSettings = {
      bindaddress = "0.0.0.0:8443";

      origin = "https://login.gio.ninja";
      domain = "login.gio.ninja";

      # Certificates from the security.acme module
      # TODO: these should really be referencing the $CREDENTIALS_DIRECTORY not hardcoded
      # kanidm will need some way to load config from env vars or files first
      # See: https://github.com/kanidm/kanidm/issues/290
      tls_key = "${credentials_directory}/certs_key.pem";
      tls_chain = "${credentials_directory}/certs_fullchain.pem";

      online_backup = {
        path = "/var/lib/kanidm/backups/";
        schedule = "@daily";
        versions = 50;
      };
    };

    enableClient = true;
    clientSettings = {
      uri = "https://login.gio.ninja";
    };
  };

  # Use Caddy to reverse proxy
  services.caddy = {
    enable = true;
    group = "acme";

    virtualHosts."https://login.gio.ninja" = {
      useACMEHost = "login.gio.ninja";
      extraConfig = ''
        reverse_proxy https://localhost:8443 {
          transport http {
            tls_insecure_skip_verify
          }
        }
      '';
    };

    virtualHosts."http://login.gio.ninja" = {
      extraConfig = ''
        reverse_proxy http://localhost:8080
      '';
    };
  };

  # Open up firewall port
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [80 443];
  };
}
