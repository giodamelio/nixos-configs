_: {pkgs, ...}: {
  # TLS Setup script
  # Generates key and encrypts with systemd-creds
  # See: https://systemd.io/CREDENTIALS/
  # To run: `sudo systemctl start kanidm-generate-tls-cert`
  systemd.services.kanidm-generate-tls-cert = {
    description = "Generate a TLS cert for Kanidm";
    wantedBy = ["default.target"];
    before = ["kanidm.service"];
    serviceConfig = {
      Type = "oneshot";
    };
    unitConfig = {
      # Only generate if an existing key doesn't exist
      # Note negation of the path
      ConditionPathExists = [
        "!/usr/lib/credstore.encrypted/kanidm.crt"
        "!/usr/lib/credstore.encrypted/kanidm.key"
      ];
    };
    script = ''
      # Ensure the location to store the cert exists
      mkdir -p /usr/lib/credstore.encrypted/

      # Move to a temporary directory
      newdir=$(mktemp -d)
      cd $newdir

      # Generate a TLS key that will last 10 years
      ${pkgs.openssl}/bin/openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 \
        -nodes -keyout kanidm.key -out kanidm.crt -subj "/CN=localhost" \
        -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"

      # Encrypt the keys as SystemD credentials
      systemd-creds encrypt kanidm.crt /usr/lib/credstore.encrypted/kanidm.crt
      systemd-creds encrypt kanidm.key /usr/lib/credstore.encrypted/kanidm.key

      rm -r "$newdir"
    '';
  };

  # Load the TLS cert from the SystemD credentials
  systemd.services.kanidm = {
    serviceConfig = {
      ImportCredential = [
        "kanidm.crt"
        "kanidm.key"
      ];
    };
    environment = {
      KANIDM_TLS_CHAIN = "%d/kanidm.crt";
      KANIDM_TLS_KEY = "%d/kanidm.key";
    };
  };

  # Start Kanidm
  services.kanidm = {
    enableServer = true;
    serverSettings = {
      bindaddress = "0.0.0.0:8443";

      origin = "https://login.gio.ninja";
      domain = "login.gio.ninja";

      # This are placeholders, since Kanidm will use the ENV vars before the config
      tls_key = "/dev/null";
      tls_chain = "/dev/null";

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

  # Load the TLS cert from the SystemD credentials
  systemd.services.caddy = {
    serviceConfig = {
      ImportCredential = [
        "kanidm.crt"
      ];
    };
    environment = {
      KANIDM_TLS_CHAIN = "%d/kanidm.crt";
    };
  };

  # Use Caddy to reverse proxy
  services.caddy = {
    enable = true;
    virtualHosts."https://login.gio.ninja" = {
      extraConfig = ''
        reverse_proxy https://localhost:8443 {
          transport http {
            # Not sure why this doesn't work...
            # Maybe related to how Go checks SANs?
            # See: https://github.com/docker/for-linux/issues/248
            # tls_trusted_ca_certs {$KANIDM_TLS_CHAIN}

            # I don't like this, see above
            tls_insecure_skip_verify
          }
        }
      '';
    };
  };

  # Open up firewall port
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [80 443];
  };
}
