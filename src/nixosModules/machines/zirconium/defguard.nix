_: {pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    pgcli
  ];

  # Run PostgreSQL in a container
  virtualisation.oci-containers.containers.defguard-pg = {
    image = "docker.io/postgres:15-alpine";
    autoStart = true;
    volumes = [
      "pg-socket:/run/postgresql"
    ];
    environment = {
      POSTGRES_USER = "defguard";
      POSTGRES_DB = "defguard";
      # Trust connections without a password
      # We don't open any ports and just access via Unix socket,
      # so this should be secure
      POSTGRES_HOST_AUTH_METHOD = "trust";
    };
  };

  # Run Defguard Core
  virtualisation.oci-containers.containers.defguard-core = {
    image = "ghcr.io/defguard/defguard:0.9.1";
    autoStart = true;
    dependsOn = ["defguard-pg"];
    ports = [
      "8000:8000" # WebUI
    ];
    volumes = [
      "pg-socket:/run/postgresql"
    ];
    environment = {
      DEFGUARD_SECRET_KEY = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
      DEFGUARD_AUTH_SECRET = "defguard-auth-secret";
      DEFGUARD_GATEWAY_SECRET = "defguard-gateway-secret";
      DEFGUARD_YUBIBRIDGE_SECRET = "defguard-yubibridge-secret";
      DEFGUARD_DB_HOST = "/run/postgresql";
    };
  };
}
