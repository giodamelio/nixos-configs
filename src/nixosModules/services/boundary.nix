_: {
  pkgs,
  config,
  ...
}: let
  baseDomain = "boundary.gio.ninja";
  boundaryConfig = pkgs.writeTextFile {
    name = "boundary-config";
    text = ''
      controller {
        name = "beryllium"
        description = "Main controller"

        database {
          # Connect over Unix socket with peer auth
          url = "postgresql:///boundary?user=boundary"
        }
      }

      listener "unix" {
        purpose = "api"
        address = "/run/boundary/api.sock"
        tls_disable = true
      }

      listener "tcp" {
        purpose = "api"
        address = "127.0.0.1:9200"
        tls_disable = true
      }

      listener "unix" {
        purpose = "cluster"
        address = "/run/boundary/cluster.sock"
      }
    '';
  };
in {
  # Load our secrets
  age.secrets.cert_boundary_gio_ninja.file = ../../../secrets/cert_cloudflare_gio_ninja.age;
  age.secrets.service_boundary_postgres_password.file = ../../../secrets/service_boundary_postgres_password.age;
  age.secrets.service_boundary_kms_config.file = ../../../secrets/service_boundary_kms_config.age;
  age.secrets.service_boundary_admin_password.file = ../../../secrets/service_boundary_postgres_password.age;

  environment.systemPackages = with pkgs; [
    boundary
  ];

  # Start Boundary
  systemd.services.boundary = {
    description = "Boundary";

    wantedBy = ["multi-user.target"];
    after = ["network.target" "postgresql.service" "boundary-init-database.service"];
    requires = ["postgresql.service" "boundary-init-database.service"];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.boundary}/bin/boundary server -config=${boundaryConfig} -config=%d/boundary_kms_config";
      DynamicUser = true;
      User = "boundary";
      Group = "boundary";
      RuntimeDirectory = "boundary";
      LoadCredential = [
        "boundary_kms_config:${config.age.secrets.service_boundary_kms_config.path}"
      ];

      # Allow Boundary to mlock memory
      LimitMEMLOCK = "infinity";
      AmbientCapabilities = "CAP_IPC_LOCK";
    };
  };

  # Oneshot service to init the boundary database
  # Command checks if the DB is already initilized, so it is safe to run before startup
  systemd.services.boundary-init-database = let
    boundaryInitDatabase = pkgs.writeShellApplication {
      name = "boundary_init_database";
      runtimeInputs = [pkgs.boundary];
      text = ''
        boundary database init \
          -config=${boundaryConfig} \
          -config="''${CREDENTIALS_DIRECTORY}/boundary_kms_config"
      '';
    };
  in {
    description = "Initilize Boundary Database";

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${boundaryInitDatabase}/bin/boundary_init_database";
      DynamicUser = true;
      User = "boundary";
      Group = "boundary";
      RuntimeDirectory = "boundary";
      LoadCredential = [
        "boundary_kms_config:${config.age.secrets.service_boundary_kms_config.path}"
      ];
    };
  };

  # Setup the initial data in Boundary
  systemd.services.boundary-initial-setup = let
    boundaryInitialSetup = pkgs.writeShellApplication {
      name = "boundary_initial_setup";
      runtimeInputs = with pkgs; [boundary jq];
      text = ''
        # Get the auth method id of the default auth method
        auth_method_id=$(boundary auth-methods list -format=json -filter='"/item/type"=="password"' | jq -r ".items[0].id")

        # Set the admin password
        boundary accounts create password \
          -recovery-config="''${CREDENTIALS_DIRECTORY}/boundary_kms_config" \
          -auth-method-id="$auth_method_id" \
          -login-name="admin" \
          -password="file:///''${CREDENTIALS_DIRECTORY}/boundary_admin_password"
      '';
    };
  in {
    description = "Create Initial Boundary Data";

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${boundaryInitialSetup}/bin/boundary_initial_setup";
      DynamicUser = true;
      User = "boundary";
      Group = "boundary";
      RuntimeDirectory = "boundary";
      LoadCredential = [
        "boundary_kms_config:${config.age.secrets.service_boundary_kms_config.path}"
        "boundary_admin_password:${config.age.secrets.service_boundary_admin_password.path}"
      ];
    };
  };
  # Get HTTPS certificates from LetsEncrypt
  security.acme = {
    acceptTerms = true;
    defaults.email = "gio@damelio.net";

    certs.${baseDomain} = {
      dnsProvider = "cloudflare";
      domain = baseDomain;
      credentialsFile = config.age.secrets.cert_boundary_gio_ninja.path;
    };
  };

  # Use Caddy to reverse proxy
  services.caddy = {
    enable = true;
    group = "acme";

    # virtualHosts."https://${baseDomain}" = {
    #   useACMEHost = baseDomain;
    #   extraConfig = ''
    #     reverse_proxy http://localhost:${builtins.toString port}
    #   '';
    # };
  };

  # Ensure PostgreSQL is running and has a database and user for us
  services.my-postgres = {
    enable = true;
    databases = {
      boundary = config.age.secrets.service_boundary_postgres_password.path;
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
  };
}
