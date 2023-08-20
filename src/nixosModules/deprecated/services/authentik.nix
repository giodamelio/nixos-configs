{...}: {
  pkgs,
  config,
  ...
}: let
  lib = pkgs.lib;
in {
  # Trust requests that coming from the podman0 interface
  networking.firewall.trustedInterfaces = ["podman0"];

  # Launch Authentik server and worker in containers
  virtualisation = {
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings = {
        dns_enabled = true;
      };
    };
    oci-containers = {
      backend = "podman";

      containers.authentik-redis = {
        image = "docker.io/redis";
        autoStart = true;
      };

      containers.authentik-server = {
        image = "ghcr.io/goauthentik/server:2023.6.1";
        autoStart = true;
        extraOptions = [
          "--secret=authentik_secret_key"
          "--secret=authentik_postgres_password"
        ];
        ports = ["9000:9000" "9443:9443"];
        cmd = ["server"];
        environment = {
          AUTHENTIK_SECRET_KEY = "file:///run/secrets/authentik_secret_key";

          AUTHENTIK_REDIS__HOST = "authentik-redis";

          AUTHENTIK_POSTGRESQL__HOST = "host.containers.internal";
          AUTHENTIK_POSTGRESQL__USER = "authentik";
          AUTHENTIK_POSTGRESQL__NAME = "authentik";
          AUTHENTIK_POSTGRESQL__PASSWORD = "file:///run/secrets/authentik_postgres_password";
        };
        dependsOn = ["authentik-redis"];
      };

      containers.authentik-worker = {
        image = "ghcr.io/goauthentik/server:2023.6.1";
        autoStart = true;
        extraOptions = [
          "--secret=authentik_secret_key"
          "--secret=authentik_postgres_password"
        ];
        cmd = ["worker"];
        environment = {
          AUTHENTIK_SECRET_KEY = "file:///run/secrets/authentik_secret_key";

          AUTHENTIK_REDIS__HOST = "authentik-redis";

          AUTHENTIK_POSTGRESQL__HOST = "host.containers.internal";
          AUTHENTIK_POSTGRESQL__USER = "authentik";
          AUTHENTIK_POSTGRESQL__NAME = "authentik";
          AUTHENTIK_POSTGRESQL__PASSWORD = "file:///run/secrets/authentik_postgres_password";
        };
        dependsOn = ["authentik-redis"];
      };
    };
  };

  # Load secrets
  age.secrets.service_authentik_secret_key.file = ../../../secrets/service_authentik_secret_key.age;
  age.secrets.service_authentik_postgres_password.file = ../../../secrets/service_authentik_postgres_password.age;

  # Load secrets into podman
  systemd.services.podman-authentik-server = {
    serviceConfig = {
      LoadCredential = [
        "secret_key:${config.age.secrets.service_authentik_secret_key.path}"
        "postgres_password:${config.age.secrets.service_authentik_postgres_password.path}"
      ];
    };

    preStart = ''
      # Remove old secrets. Ignore error thrown if any secret doesn't exist
      # TODO: Only necessary until the `--replace` flag is released. See https://github.com/containers/podman/pull/19004
      podman secret rm authentik_secret_key authentik_postgres_password || true

      # Create podman secrets
      podman secret create authentik_secret_key $CREDENTIALS_DIRECTORY/secret_key
      podman secret create authentik_postgres_password $CREDENTIALS_DIRECTORY/postgres_password
    '';

    postStop = ''
      # Remove old secrets. Ignore error thrown if any secret doesn't exist
      podman secret rm authentik_secret_key authentik_postgres_password || true
    '';
  };

  systemd.services.podman-authentik-worker = {
    serviceConfig = {
      LoadCredential = [
        "secret_key:${config.age.secrets.service_authentik_secret_key.path}"
        "postgres_password:${config.age.secrets.service_authentik_postgres_password.path}"
      ];
    };

    preStart = ''
      # Remove old secrets. Ignore error thrown if any secret doesn't exist
      # TODO: Only necessary until the `--replace` flag is released. See https://github.com/containers/podman/pull/19004
      podman secret rm authentik_secret_key authentik_postgres_password || true

      # Create podman secrets
      podman secret create authentik_secret_key $CREDENTIALS_DIRECTORY/secret_key
      podman secret create authentik_postgres_password $CREDENTIALS_DIRECTORY/postgres_password
    '';

    postStop = ''
      # Remove old secrets. Ignore error thrown if any secret doesn't exist
      podman secret rm authentik_secret_key authentik_postgres_password || true
    '';
  };

  environment = {
    systemPackages = with pkgs; [
      # Easily connect to PostgreSQL REPL
      (writeShellApplication {
        name = "connect-postgres-authentik";
        runtimeInputs = [pgcli];
        text = ''
          sudo -u postgres pgcli authentik
        '';
      })
    ];
  };

  # Ensure PostgreSQL is running and has a database and user for us
  services.postgresql = {
    enable = true;

    # Allow Postgres to recieve connections from inside Podman networks
    # TODO: stop this ip address being hardcoded
    settings = {
      listen_addresses = lib.mkForce "127.0.0.1,10.88.0.1";
    };
    authentication = "host all all 10.88.0.1/16 md5";

    ensureDatabases = ["authentik"];
    ensureUsers = [
      {
        name = "authentik";
        ensurePermissions = {
          "DATABASE authentik" = "ALL PRIVILEGES";
        };
      }
    ];
  };

  systemd.services.postgresql = {
    # Set the authentik postgresql password
    # Note the multiple ''' to escape '' inside of ''
    postStart = ''
      $PSQL -tAc "ALTER ROLE authentik WITH PASSWORD '$(cat $CREDENTIALS_DIRECTORY/postgres_password)'"
    '';

    # Load some credentials for the service
    serviceConfig = {
      LoadCredential = [
        "postgres_password:${config.age.secrets.service_authentik_postgres_password.path}"
      ];
    };
  };
}
