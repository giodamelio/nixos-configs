_: {pkgs, ...}: {
  services.garage = {
    enable = true;
    package = pkgs.garage_0_9_4;
    extraEnvironment = {
      # Our secrets are bind mounted by SystemD so they are not exposed
      GARAGE_ALLOW_WORLD_READABLE_SECRETS = "true";
      GARAGE_RPC_SECRET_FILE = "%d/garage-rpc-secret";
      GARAGE_ADMIN_TOKEN_FILE = "%d/garage-admin-token";
    };

    settings = {
      db_engine = "sqlite";

      rpc_bind_addr = "127.0.0.1:3901";

      s3_api = {
        s3_region = "garage";
        api_bind_addr = "127.0.0.1:3900";
      };

      admin = {
        api_bind_addr = "127.0.0.1:3903";
      };
    };
  };

  # Load SystemD secrets
  systemd.services.garage.serviceConfig.LoadCredentialEncrypted = [
    "garage-rpc-secret"
    "garage-admin-token"
  ];

  # Use Caddy as a reverse proxy
  services.caddy = {
    virtualHosts."https://garage.gio.ninja" = {
      extraConfig = ''
        reverse_proxy localhost:3900
      '';
    };
    virtualHosts."https://garage-admin.gio.ninja" = {
      extraConfig = ''
        reverse_proxy localhost:3903
      '';
    };
  };
}
