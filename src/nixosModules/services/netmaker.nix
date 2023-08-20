{
  root,
  debug,
  ...
}: {
  pkgs,
  config,
  ...
}: let
  lib = pkgs.lib;
  baseDomain = "nm.gio.ninja";
  n = root.packages.netmaker {inherit pkgs;};
in {
  # Load our secrets
  age.secrets.cert_netmaker_gio_ninja.file = ../../../secrets/cert_cloudflare_gio_ninja.age;
  age.secrets.service_netmaker_mosquitto_password_file.file = ../../../secrets/service_netmaker_mosquitto_password_file.age;
  age.secrets.service_netmaker_postgres_password.file = ../../../secrets/service_netmaker_postgres_password.age;
  age.secrets.service_netmaker_envfile.file = ../../../secrets/service_netmaker_envfile.age;

  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "netmaker"
    ];
  environment = {
    systemPackages = [
      pkgs.netmaker

      n.netmaker-ui
    ];
  };

  # Get HTTPS certificates from LetsEncrypt
  security.acme = {
    acceptTerms = true;
    defaults.email = "gio@damelio.net";

    certs."nm.gio.ninja" = {
      dnsProvider = "cloudflare";
      domain = "*.${baseDomain}";
      extraDomainNames = [baseDomain];
      credentialsFile = config.age.secrets.cert_netmaker_gio_ninja.path;
    };
  };

  # Use Caddy to reverse proxy
  services.caddy = {
    enable = true;
    group = "acme";

    virtualHosts."https://dashboard.nm.gio.ninja" = {
      useACMEHost = "nm.gio.ninja";
      extraConfig = ''
        header {
            Access-Control-Allow-Origin *.${baseDomain}
            Strict-Transport-Security "max-age=31536000;"
            X-XSS-Protection "1; mode=block"
            X-Frame-Options "SAMEORIGIN"
            X-Robots-Tag "none"
            -Server
        }
        root * ${n.netmaker-ui}
        file_server
      '';
    };

    virtualHosts."wss://broker.nm.gio.ninja" = {
      useACMEHost = "nm.gio.ninja";
      extraConfig = ''
        reverse_proxy ws://localhost:8883
      '';
    };
  };

  # Setup Mosquitto MQTT message broker
  services.mosquitto = {
    enable = true;
    listeners = [
      {
        port = 8883;
        users.netmaker.passwordFile = config.age.secrets.service_netmaker_mosquitto_password_file.path;
        settings = {
          protocol = "websockets";
          allow_anonymous = false;
        };
      }
      {
        port = 1883;
        users.netmaker.passwordFile = config.age.secrets.service_netmaker_mosquitto_password_file.path;
        settings = {
          protocol = "websockets";
          allow_anonymous = false;
        };
      }
    ];
  };

  # Ensure PostgreSQL is running and has a database and user for us
  services.my-postgres = {
    enable = true;
    databases = {
      netmaker = config.age.secrets.service_netmaker_postgres_password.path;
    };
  };

  # Open up firewall ports
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      # Caddy Proxy
      80
      443
      # TURN Server
      3479
      8089
    ];
    allowedUDPPorts = [
      51821 # Wireguard
    ];
  };

  # Setup the Netmaker SystemD service itself
  systemd.services.netmaker = let
    netmakerConfig = pkgs.writeTextFile {
      name = "netmaker_server_config.yaml";
      text = ''
        server: "${baseDomain}"
        broker: "wss://broker.${baseDomain}"

        mqusername: "netmaker"

        database: "postgres"
        sql_host: "localhost"
        sql_db: "netmaker"
        sql_user: "netmaker"

        use_turn: false
      '';
    };
  in {
    description = "Netmaker Wireguard Mesh Network";

    wantedBy = ["multi-user.target"];
    after = ["network.target"];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.netmaker}/bin/netmaker -c ${netmakerConfig}";
      EnvironmentFile = config.age.secrets.service_netmaker_envfile.path;
      DynamicUser = true;
      User = "netmaker";
      Group = "netmaker";
    };
  };
}
