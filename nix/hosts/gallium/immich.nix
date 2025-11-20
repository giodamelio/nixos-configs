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

  # Expose some custom metrics via directly reading the database
  services.prometheus.exporters.sql = {
    enable = true;
    openFirewall = true;

    configuration = {
      jobs.immich = {
        interval = "5m";
        connections = [
          "postgres:///immich?host=/run/postgresql"
        ];
        queries = {
          photos_total = {
            help = "Total number of photos";
            query = "SELECT COUNT(*) as count FROM asset WHERE type = 'IMAGE';";
            values = ["count"];
          };
          videos_total = {
            help = "Total number of videos";
            query = "SELECT COUNT(*) as count FROM asset WHERE type = 'VIDEO';";
            values = ["count"];
          };
          assets_total = {
            help = "Total number of assets";
            query = "SELECT COUNT(*) as count FROM asset;";
            values = ["count"];
          };
          assets_total_per_user = {
            help = "Total number of assets by user";
            query = ''
              SELECT u.email as email, COUNT(a.id) as count
              FROM "user" u
              LEFT JOIN asset a ON a."ownerId" = u.id
              GROUP BY u.email;
            '';
            values = ["count"];
            labels = ["email"];
          };
          disk_usage_per_user_bytes = {
            help = "Totaly number of bytes each user has used";
            query = ''
              SELECT email, "quotaUsageInBytes" count FROM "user";
            '';
            values = ["count"];
            labels = ["email"];
          };
          albums_total = {
            help = "Total number of albums";
            query = "SELECT COUNT(*) as count FROM album;";
            values = ["count"];
          };
          faces_total = {
            help = "Total number of recogonized people";
            query = "SELECT COUNT(*) as count FROM person;";
            values = ["count"];
          };
        };
      };
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
          handle_path /metrics/stats {
            reverse_proxy localhost:9237 {
              rewrite /metrics
            }
          }
        '';
      };
    };
  };

  gio.services.immich.consul = {
    name = "immich";
    address = "immich.gio.ninja";
    port = 443;
    checks = [
      {
        http = "https://immich.gio.ninja/";
        interval = "60s";
      }
    ];
  };
}
