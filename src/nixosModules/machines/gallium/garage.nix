_: {
  pkgs,
  config,
  ...
}: {
  age.secrets.garage-envfile.file = ../../../../secrets/garage-envfile.age;

  services.garage = {
    enable = true;
    package = pkgs.garage_0_9_3;
    environmentFile = config.age.secrets.garage-envfile.path;

    settings = {
      data_dir = "/tank/garage";
      replication_mode = 1;
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
