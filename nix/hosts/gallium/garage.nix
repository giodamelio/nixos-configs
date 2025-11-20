{pkgs, ...}: {
  environment.shellAliases = {
    garage = "garage -c /etc/garage.toml";
  };

  services.garage = {
    enable = true;
    package = pkgs.garage_2;
    settings = {
      db_engine = "sqlite";
      replication_factor = 1;

      rpc_bind_addr = "[::]:3901";
      rpc_public_addr = "127.0.0.1:3901";
      rpc_secret_file = "/run/credentials/garage.service/garage_rpc_secret";

      s3_api = {
        s3_region = "garage";
        api_bind_addr = "[::]:3900";
        root_domain = ".s3.garage.gio.ninja";
      };

      s3_web = {
        bind_addr = "[::]:3902";
        root_domain = ".web.garage.gio.ninja";
        index = "index.html";
      };

      k2v_api = {
        api_bind_addr = "[::]:3904";
      };

      admin = {
        api_bind_addr = "[::]:3903";
        admin_token_file = "/run/credentials/garage.service/garage_admin_token";
        metrics_token_file = "/run/credentials/garage.service/garage_metrics_token";
      };

      # Secrets are mounted by SystemD creds
      allow_world_readable_secrets = true;
    };
  };

  # Run Garage with a dedicated user to make the ZFS dataset mounts work
  users.users.garage = {
    isSystemUser = true;
    group = "garage";
  };
  users.groups.garage = {};
  systemd.services.garage.serviceConfig = {
    DynamicUser = false;
    User = "garage";
    Group = "garage";
  };

  gio.credentials = {
    enable = true;
    services = {
      "garage" = {
        loadCredentialEncrypted = [
          "garage_rpc_secret"
          "garage_admin_token"
          "garage_metrics_token"
        ];
      };
    };
  };

  services.gio.reverse-proxy = {
    enable = true;
    virtualHosts = {
      "s3.garage" = {
        host = "localhost";
        port = 3900;
      };
      "*.s3.garage" = {
        host = "localhost";
        port = 3900;
      };
      "*.web.garage" = {
        host = "localhost";
        port = 3902;
      };
      "admin.garage" = {
        host = "localhost";
        port = 3903;
      };
    };
  };
}
