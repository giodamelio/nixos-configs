{
  services.immich = {
    enable = true;
    mediaLocation = "/tank/immich";

    database = {
      enable = true;
      createDB = true;
    };

    environment = {
      IMMICH_TELEMETRY_INCLUDE = "all";
    };
  };

  services.gio.reverse-proxy = {
    enable = true;
    virtualHosts = {
      "immich" = {
        host = "localhost";
        port = 2283;

        # Forward some paths to the metrics endpoints
        extraConfig = ''
          handle_path /metrics/api {
            reverse_proxy localhost:8081 {
              rewrite /metrics
            }
          }
          handle_path /metrics/microservices {
            reverse_proxy localhost:8082 {
              rewrite /metrics
            }
          }
        '';
      };
    };
  };
}
