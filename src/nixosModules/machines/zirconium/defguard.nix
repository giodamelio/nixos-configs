_: {pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    pgcli
  ];

  # Create PostgreSQL DB
  services.postgresql = {
    enable = true;

    ensureDatabases = [
      "defguard"
    ];
    ensureUsers = [
      {
        name = "defguard";
        ensureDBOwnership = true;
      }
    ];
  };

  # Run Defguard Core
  virtualisation.oci-containers.containers.defguard-core = {
    image = "ghcr.io/defguard/defguard:0.9.1";
    autoStart = true;
    ports = [
      "8000:8000" # WebUI
    ];
    volumes = [
      "/run/postgresql:/run/postgresql"
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
