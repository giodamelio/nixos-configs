_: {
  pkgs,
  config,
  ...
}: let
  basePath = "/var/lib/x-acme";
  email = "gio@damelio.net";
  domain = "testing.gio.ninja";
in {
  systemd.services.obtain-certificate = {
    description = "Obtain a certificate";
    wantedBy = ["default.target"];
    serviceConfig = {
      Type = "oneshot";
      ImportCredential = "CLOUDFLARE_API_TOKEN";
    };
    unitConfig = {
      # Note negation of the path
      ConditionPathExists = "!${basePath}/certificates/${domain}.json";
      # TODO: why doesn't this work?
      # AssertCredential = "test-cred";
    };
    environment = {
      LEGO_PATH = basePath;
      CLOUDFLARE_DNS_API_TOKEN_FILE = "%d/CLOUDFLARE_API_TOKEN";
    };
    script = ''
      ${pkgs.lego}/bin/lego \
        --server=https://acme-staging-v02.api.letsencrypt.org/directory \
        --email ${email} \
        --accept-tos \
        --dns cloudflare \
        --domains ${domain} \
        run
    '';
  };

  systemd.services.renew-certificate = {
    description = "Renew a certificate";
    wantedBy = ["default.target"];
    after = ["obtain-certificate.service"];
    serviceConfig = {
      Type = "oneshot";
      ImportCredential = "CLOUDFLARE_API_TOKEN";
    };
    unitConfig = {
      ConditionPathExists = "${basePath}/certificates/${domain}.json";
      # TODO: why doesn't this work?
      # AssertCredential = "test-cred";
    };
    environment = {
      LEGO_PATH = basePath;
      CLOUDFLARE_DNS_API_TOKEN_FILE = "%d/CLOUDFLARE_API_TOKEN";
    };
    script = ''
      ${pkgs.lego}/bin/lego \
        --server=https://acme-staging-v02.api.letsencrypt.org/directory \
        --email ${email} \
        --accept-tos \
        --dns cloudflare \
        --domains ${domain} \
        renew \
        --days 30
    '';
  };

  systemd.timers.renew-certificate = {
    description = "Try to renew certificate every day";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = "true";
      RandomizedDelaySec = 3600; # 1 hour
    };
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
