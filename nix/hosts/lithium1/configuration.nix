{flake, ...}: let
  homelab = builtins.fromTOML (builtins.readFile ../../../homelab.toml);
in {
  imports = [
    # Setup hardware
    ./disko.nix
    ./hardware.nix

    flake.nixosModules.basic-packages
    flake.nixosModules.basic-settings
    flake.nixosModules.monitoring
    flake.nixosModules.onepassword

    # Create server user
    (
      {pkgs, ...}: {
        users.users.server = {
          extraGroups = [
            "wheel"
            "docker"
            "sound"
          ];
          isNormalUser = true;
          shell = pkgs.zsh;
          openssh.authorizedKeys.keys = homelab.ssh_keys;
        };
        security.sudo.wheelNeedsPassword = false;
        programs.zsh.enable = true;
      }
    )

    # Setup Pocket ID
    (
      {pkgs, ...}: {
        services.pocket-id = {
          enable = true;

          settings = {
            APP_URL = "https://login.gio.ninja";
            TRUST_PROXY = true;
            # TODO: hardcoding this is probably a bad idea
            # See: https://github.com/pocket-id/pocket-id/pull/799#issuecomment-3134806588
            # Maybe I can use mount path or something to make it work
            # ENCRYPTION_KEY_FILE = "\${CREDENTIALS_DIRECTORY}/pocket-id-encryption-key";
            ENCRYPTION_KEY_FILE = "/run/credentials/pocket-id.service/pocket-id-encryption-key";
            ANALYTICS_DISABLED = true;
          };
        };

        # Load the encrypted encryption key
        systemd.services.pocket-id.serviceConfig = {
          LoadCredentialEncrypted = "pocket-id-encryption-key:/var/lib/credstore/pocket-id-encryption-key";
        };

        # Setup Caddy as a reverse proxy
        systemd.services.caddy.serviceConfig = {
          LoadCredentialEncrypted = [
            "caddy-tailscale-preauth-key:/var/lib/credstore/caddy-tailscale-preauth-key"
            "caddy-cloudflare-api-token:/var/lib/credstore/caddy-cloudflare-api-token"
          ];
          Environment = [
            "TAILSCALE_PREAUTH_KEY_FILE=%d/caddy-tailscale-preauth-key"
            "CLOUDFLARE_API_TOKEN_FILE=%d/caddy-cloudflare-api-token"
          ];
        };
        networking.firewall.allowedTCPPorts = [
          80
          443
        ];
        services.caddy = {
          enable = true;

          package = pkgs.caddy.withPlugins {
            plugins = [
              "github.com/caddy-dns/cloudflare@v0.2.1"
              "github.com/tailscale/caddy-tailscale@v0.0.0-20250508175905-642f61fea3cc"
            ];
            # hash = "sha256-3nhBsVLFrGqG7JQpVDHtjyfphw2mTcpS3o0gGjydyHc=";
            hash = "sha256-eOEzNLk17TZZh0H/DRgxLM2nnEZWmtod9tfmlTU/Gls=";
          };

          globalConfig = ''
            email admin@gio.ninja

            tailscale {
              auth_key {file.{$TAILSCALE_PREAUTH_KEY_FILE}}
              control_url http://localhost:8080
              ephemral false
            }
          '';

          virtualHosts."https://login.gio.ninja" = {
            extraConfig = ''
              reverse_proxy localhost:1411
            '';
          };

          virtualHosts."https://headscale.gio.ninja" = {
            extraConfig = ''
              reverse_proxy localhost:8080
            '';
          };

          virtualHosts."https://testing123.h.gio.ninja" = {
            extraConfig = ''
              bind tailscale/testing123
              tls {
                dns cloudflare {file.{$CLOUDFLARE_API_TOKEN_FILE}}
                resolvers 1.1.1.1
              }
              respond OK
            '';
          };

          virtualHosts."https://gatus.h.gio.ninja" = {
            extraConfig = ''
              bind tailscale/gatus
              tls {
                dns cloudflare {file.{$CLOUDFLARE_API_TOKEN_FILE}}
                resolvers 1.1.1.1
              }
              reverse_proxy localhost:4444
            '';
          };
        };
      }
    )

    # Run Garage as a S3 file server
    (
      {pkgs, ...}: {
        services.garage = {
          enable = true;
          package = pkgs.garage_2;
          settings = {
            db_engine = "sqlite";
            replication_factor = 1;

            rpc_bind_addr = "[::]:3901";
            rpc_public_addr = "127.0.0.1:3901";
            rpc_secret_file = "/run/credentials/garage.service/garage_rpc_secret";

            # Secret files are loaded via SystemD Creds so it is secure
            allow_world_readable_secrets = true;

            s3_api = {
              s3_region = "garage";
              api_bind_addr = "[::]:3900";
              root_domain = ".s3.garage.h.gio.ninja";
            };

            s3_web = {
              bind_addr = "[::]:3902";
              root_domain = ".web.garage.h.gio.ninja";
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
          };
        };

        systemd.services.garage.serviceConfig = {
          LoadCredentialEncrypted = [
            "garage_rpc_secret:/var/lib/credstore/garage_rpc_secret"
            "garage_admin_token:/var/lib/credstore/garage_admin_token"
            "garage_metrics_token:/var/lib/credstore/garage_metrics_token"
          ];
        };

        services.caddy = {
          virtualHosts."https://s3.garage.h.gio.ninja" = {
            serverAliases = [
              "s3.garage.h.gio.ninja"
              "*.s3.garage.h.gio.ninja"
            ];
            extraConfig = ''
              bind tailscale/garage
              tls {
                dns cloudflare {file.{$CLOUDFLARE_API_TOKEN_FILE}}
                resolvers 1.1.1.1
              }
              reverse_proxy localhost:3900 {
                health_uri /health
                health_port 3903
              }
            '';
          };
        };
      }
    )

    # Run Headscale for easy networking
    {
      networking.firewall.allowedTCPPorts = [
        80
        443
      ];

      services.headscale = {
        enable = true;
        port = 8080;

        settings = {
          server_url = "https://headscale.gio.ninja";

          tls_cert_path = null;
          tls_key_paht = null;

          dns = {
            magic_dns = true;
            base_domain = "h.gio.ninja";
            nameservers.global = [
              "8.8.8.8"
              "8.8.4.4"
            ];
          };

          oidc = {
            only_start_if_oidc_is_available = false;
            issuer = "https://login.gio.ninja";
            client_id = "251934f5-6b41-4665-9a7f-c475ca534c92";
            client_secret_path = "\${CREDENTIALS_DIRECTORY}/headscale-oidc-client-secret";
            scope = [
              "openid"
              "profile"
              "email"
              "groups"
            ];
            allowed_groups = ["headscale"];
            pkce = {
              enabled = true;
              method = "S256";
            };
          };
        };
      };

      # Load the encrypted encryption key
      systemd.services.headscale.serviceConfig = {
        LoadCredentialEncrypted = "headscale-oidc-client-secret:/var/lib/credstore/headscale-oidc-client-secret";
      };
    }

    # Enable Tailscale
    {
      services.tailscale = {
        enable = true;
      };
    }

    # Setup PostgreSQL with TimescaleDB for metrics collection
    (
      {pkgs, ...}: {
        environment.systemPackages = [
          pkgs.pgcli
        ];

        services.postgresql = {
          enable = true;
          extensions = with pkgs.postgresql16Packages; [
            timescaledb
            timescaledb_toolkit
          ];
          settings.shared_preload_libraries = ["timescaledb"];
          ensureDatabases = [
            "telegraf"
            "cloudprober"
          ];
          ensureUsers = [
            {
              name = "server";
              ensureClauses = {
                login = true;
                superuser = true;
              };
            }
            {
              name = "telegraf";
              ensureDBOwnership = true;
              ensureClauses = {
                login = true;
                createdb = true;
              };
            }
            {
              name = "cloudprober";
              ensureDBOwnership = true;
              ensureClauses = {
                login = true;
                createdb = true;
              };
            }
          ];
        };
      }
    )

    # Collect some metrics with Telegraf
    (
      {pkgs, ...}: {
        services.telegraf = {
          enable = true;
          extraConfig = {
            inputs = {
              # System Stats
              cpu = {
                percpu = true;
                totalcpu = true;
              };
              disk = {};
              diskio = {};
              internet_speed = {
                interval = "60m";
              };
              kernel = {};
              linux_sysctl_fs = {};
              mem = {};
              net = {
                # Setting this to false is deprecated
                # See: https://github.com/influxdata/telegraf/blob/master/plugins/inputs/net/README.md
                ignore_protocol_stats = true;
              };
              netstat = {};
              nstat = {};
              processes = {};
              smart = {
                path_smartctl = "${pkgs.smartmontools}/bin/smartctl";
                path_nvme = "${pkgs.nvme-cli}/bin/nvme";
              };
              swap = {};
              system = {};
              systemd_units = [
                {unittype = "service";}
                {unittype = "timer";}
              ];

              # Monitor PostgreSQL
              postgresql = {
                address = "host=/run/postgresql dbname=telegraf";
              };

              # Monitor Wireguard
              wireguard = {};
            };

            outputs = {
              postgresql = {
                connection = "host=/run/postgresql dbname=telegraf";

                # Templated statements to execute when creating a new table.
                # Setup this way for TimescaleDB
                tags_as_foreign_keys = true;
                create_templates = [
                  "CREATE TABLE {{ .table }} ({{ .columns }})"
                  "SELECT create_hypertable({{ .table|quoteLiteral }}, 'time', chunk_time_interval => INTERVAL '7d')"
                  "ALTER TABLE {{ .table }} SET (timescaledb.compress, timescaledb.compress_segmentby = 'tag_id')"
                ];
              };
            };
          };
        };
      }
    )

    # Active probe based monitoring
    (
      {pkgs, ...}: let
        config = let
          dns_servers_endpoints = [
            {
              name = "cloudflare_primary";
              ip = "1.1.1.1";
            }
            {
              name = "cloudflare_secondary";
              ip = "1.0.0.1";
            }
            {
              name = "google_primary";
              ip = "8.8.8.8";
            }
            {
              name = "google_secondary";
              ip = "8.8.4.4";
            }
          ];
          validators = {
            status_200 = {
              name = "status_200";
              http_validator = {
                success_status_codes = "200";
              };
            };
            status_204 = {
              name = "status_204";
              http_validator = {
                success_status_codes = "204";
              };
            };
            response_json_status = value: {
              name = "response_status_pass";
              json_validator = {
                jq_filter = ''.status == "${value}"'';
              };
            };
          };
        in {
          probe = [
            {
              name = "http_google_homepage";
              type = "HTTP";
              targets = {
                host_names = "www.google.com";
              };
              http_probe = {
                protocol = "HTTPS";
                port = 443;
              };
            }
            {
              name = "http_headscale_health";
              type = "HTTP";
              targets = {
                host_names = "headscale.gio.ninja";
              };
              http_probe = {
                protocol = "HTTPS";
                relative_url = "/health";
              };
              validator = with validators; [
                status_200
                (response_json_status "pass")
              ];
            }
            {
              name = "http_pocket_health";
              type = "HTTP";
              targets = {
                host_names = "login.gio.ninja";
              };
              http_probe = {
                protocol = "HTTPS";
                relative_url = "/healthz";
              };
              validator = with validators; [status_204];
            }
            {
              name = "ping_dns_servers";
              type = "PING";
              targets = {
                endpoint = dns_servers_endpoints;
              };
            }
            {
              name = "dns_basic_resolve";
              type = "DNS";
              targets = {
                endpoint = dns_servers_endpoints;
              };
              dns_probe = {
                query_type = "A";
                query_class = "IN";
              };
            }
          ];

          surfacer = [
            {
              type = "PROMETHEUS";
              prometheus_surfacer = {
                metrics_url = "/metrics";
              };
            }
            {
              type = "POSTGRES";
              postgres_surfacer = {
                connection_string = "host=/run/postgresql dbname=cloudprober";
                # Schema for table:
                # CREATE TABLE metrics (
                #   time timestamp, metric_name varchar(80), value float8, labels jsonb
                # )
                # ALTER TABLE metrics OWNER TO cloudprober;
                metrics_table_name = "metrics";
              };
            }
          ];
        };
        jsonFormat = pkgs.formats.json {};
        cloudproberConfigFile = jsonFormat.generate "cloudprober.json" config;
      in {
        systemd.services.cloudprober = {
          description = "Cloudprober monitoring service";
          wants = ["network-online.target"];
          after = ["network-online.target"];
          wantedBy = ["multi-user.target"];

          serviceConfig = {
            Type = "simple";
            DynamicUser = true;
            User = "cloudprober";
            Group = "cloudprober";

            ExecStart = "${pkgs.cloudprober}/bin/cloudprober -config_file=${cloudproberConfigFile}";

            # Increase capabilities so all the probes work
            CapabilityBoundingSet = [
              "CAP_NET_RAW"
              "CAP_NET_BIND_SERVICE"
            ];
            AmbientCapabilities = [
              "CAP_NET_RAW"
              "CAP_NET_BIND_SERVICE"
            ];
          };
        };
      }
    )

    # Gatus Service Status Page
    {
      services.gatus = {
        enable = true;
        settings = {
          metrics = true;
          web.port = 4444;
          storage = {
            type = "sqlite";
            path = "/var/lib/gatus/data.db";
          };
          endpoints = [
            {
              name = "Headscale";
              url = "https://headscale.gio.ninja/health";
              interval = "5m";
              conditions = [
                "[STATUS] == 200"
                "[BODY].status == pass"
                "[RESPONSE_TIME] < 300"
              ];
            }
            {
              name = "Pocket ID";
              url = "https://login.gio.ninja/healthz";
              interval = "5m";
              conditions = [
                "[STATUS] == 204"
              ];
            }
          ];
        };
      };

      # Allow Gatus to send ICMP traffic
      systemd.services.gatus = {
        serviceConfig = {
          CapabilityBoundingSet = "CAP_NET_RAW";
          AmbientCapabilities = "CAP_NET_RAW";
        };
      };
    }
  ];

  nixpkgs.config.allowUnfree = true;
  system.stateVersion = "25.05";
}
