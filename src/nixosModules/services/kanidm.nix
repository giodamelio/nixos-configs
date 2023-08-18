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
    };
  };

  # Load the LetsEncrypt certs as SystemD credentials
  systemd.services.kanidm = {
    serviceConfig = let
      cert_dir = config.security.acme.certs."idm.gio.ninja".directory;
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

      origin = "https://idm.gio.ninja";
      domain = "idm.gio.ninja";

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
      uri = "https://idm.gio.ninja";
    };
  };

  # Use Caddy to reverse proxy
  services.caddy = {
    enable = true;
    group = "acme";

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
