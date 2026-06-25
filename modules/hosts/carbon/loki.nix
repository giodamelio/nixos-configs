# loki — log aggregation (loki.gio.ninja), filesystem backend, single-node.
# Converted from nix/hosts/carbon/loki.nix.
_: {
  den.aspects.carbon.nixos = {
    services.loki = {
      enable = true;
      configuration = {
        auth_enabled = false;

        server = {
          http_listen_port = 3100;
          grpc_listen_port = 9096;
        };

        common = {
          path_prefix = "/var/lib/loki";
          instance_addr = "127.0.0.1";
          storage = {
            filesystem = {
              chunks_directory = "/var/lib/loki/chunks";
              rules_directory = "/var/lib/loki/rules";
            };
          };
          replication_factor = 1;
          ring = {
            kvstore = {
              store = "inmemory";
            };
          };
        };

        schema_config = {
          configs = [
            {
              from = "2025-10-27";
              store = "tsdb";
              object_store = "filesystem";
              schema = "v13";
              index = {
                prefix = "index_";
                period = "24h";
              };
            }
          ];
        };

        analytics = {
          reporting_enabled = false;
        };
      };
    };
  };

  den.hosts.x86_64-linux.carbon.services.loki = {
    endpoint = {
      domain = "loki";
      backend.host = "localhost";
      backend.port = 3100;
    };
    healthcheck.target = "https://loki.gio.ninja/ready";
    "prometheus-endpoint".target = "localhost:3100";
  };
}
