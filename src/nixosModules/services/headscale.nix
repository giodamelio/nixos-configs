{
  root,
  debug,
  ...
}: {
  pkgs,
  config,
  ...
}: let
  baseDomain = "headscale.gio.ninja";
  port = 8010;
in {
  # Load our secrets
  age.secrets.cert_headscale_gio_ninja.file = ../../../secrets/cert_cloudflare_gio_ninja.age;
  age.secrets.service_headscale_postgres_password.file = ../../../secrets/service_headscale_postgres_password.age;

  # Setup Headscale
  services.headscale = {
    enable = true;
    address = "127.0.0.1";
    port = port;

    settings = {
      server_url = "https://${baseDomain}";

      db_type = "postgres";
      db_host = "localhost";
      db_port = 5432;
      db_name = "headscale";
      db_user = "headscale";
      db_password = "\${CREDENTIALS_DIRECTORY}/headscale_postgres_password";

      ip_prefixes = [
        "fd7a:115c:a1e0::/48"
        "100.64.0.0/10"
      ];
    };
  };

  # Load our secrets into headscale
  systemd.services.headscale = {
    serviceConfig.LoadCredential = "headscale_postgres_password:${config.age.secrets.service_headscale_postgres_password.path}";
  };

  # Get HTTPS certificates from LetsEncrypt
  security.acme = {
    acceptTerms = true;
    defaults.email = "gio@damelio.net";

    certs.${baseDomain} = {
      dnsProvider = "cloudflare";
      domain = baseDomain;
      credentialsFile = config.age.secrets.cert_headscale_gio_ninja.path;
    };
  };

  # Use Caddy to reverse proxy
  services.caddy = {
    enable = true;
    group = "acme";

    virtualHosts."https://${baseDomain}" = {
      useACMEHost = baseDomain;
      extraConfig = ''
        reverse_proxy http://localhost:${builtins.toString port}
      '';
    };
  };

  # Ensure PostgreSQL is running and has a database and user for us
  services.my-postgres = {
    enable = true;
    databases = {
      headscale = config.age.secrets.service_headscale_postgres_password.path;
    };
  };

  # Open up firewall ports
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      # Caddy Proxy
      80
      443
    ];
    # allowedUDPPorts = [];
  };
}
