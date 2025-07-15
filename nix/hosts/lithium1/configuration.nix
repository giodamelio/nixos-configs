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

    # Create server user
    ({pkgs, ...}: {
      users.users.server = {
        extraGroups = ["wheel" "docker" "sound"];
        isNormalUser = true;
        shell = pkgs.zsh;
        openssh.authorizedKeys.keys = homelab.ssh_keys;
      };
      security.sudo.wheelNeedsPassword = false;
      programs.zsh.enable = true;
    })

    # Setup Pocket ID
    ({pkgs, ...}: {
      services.pocket-id = {
        enable = true;

        settings = {
          APP_URL = "https://login.gio.ninja";
          TRUST_PROXY = true;
          ENCRYPTION_KEY_FILE = "\${CREDENTIALS_DIRECTORY}/pocket-id-encryption-key";
          ANALYTICS_DISABLED = true;
        };
      };

      # Load the encrypted encryption key
      systemd.services.pocket-id.serviceConfig = {
        LoadCredentialEncrypted = "pocket-id-encryption-key:/var/lib/credstore/pocket-id-encryption-key";
      };

      # Setup Caddy as a reverse proxy
      networking.firewall.allowedTCPPorts = [80 443];
      services.caddy = {
        enable = true;

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
      };
    })

    # Run Headscale for easy networking
    {
      networking.firewall.allowedTCPPorts = [80 443];

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
            nameservers.global = ["8.8.8.8" "8.8.4.4"];
          };

          oidc = {
            only_start_if_oidc_is_available = true;
            issuer = "https://login.gio.ninja";
            client_id = "251934f5-6b41-4665-9a7f-c475ca534c92";
            client_secret_path = "\${CREDENTIALS_DIRECTORY}/headscale-oidc-client-secret";
            scope = ["openid" "profile" "email" "groups"];
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
    ({pkgs, ...}: {
      environment.systemPackages = [
        pkgs.pgcli
      ];

      services.postgresql = {
        enable = true;
        extensions = with pkgs.postgresql16Packages; [ timescaledb timescaledb_toolkit ];
        settings.shared_preload_libraries = [ "timescaledb" ];
        ensureDatabases = ["telegraf"];
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
        ];
      };
    })

    # Collect some metrics with Telegraf
    ({lib, pkgs, ...}: {
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
              { unittype = "service"; }
              { unittype = "timer"; }
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
    })

    # Active probe based monitoring
    ({pkgs, ...}: let
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
        ];
      };
      jsonFormat = pkgs.formats.json {};
      cloudproberConfigFile = jsonFormat.generate "cloudprober.json" config;
    in {
      systemd.services.cloudprober = {
        description = "Cloudprober monitoring service";
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "simple";
          DynamicUser = true;
          User = "cloudprober";
          Group = "cloudprober";

          ExecStart = "${pkgs.cloudprober}/bin/cloudprober -config_file=${cloudproberConfigFile}";

          # Increase capabilities so all the probes work
          CapabilityBoundingSet = ["CAP_NET_RAW" "CAP_NET_BIND_SERVICE"];
          AmbientCapabilities = ["CAP_NET_RAW" "CAP_NET_BIND_SERVICE"];
        };
      };
    })
  ];

  nixpkgs.config.allowUnfree = true;
  system.stateVersion = "25.05";
}
