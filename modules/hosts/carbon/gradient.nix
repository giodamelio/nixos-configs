# gradient — Nix CI / build cache (gradient.gio.ninja). The long pole: server +
# worker, postgres, OIDC, garage S3 cache, a GitHub App, and ~13 secrets. All
# secrets move to fleet.secrets credentials on gradient-server / gradient-worker;
# the legacy underscore credstore names are hyphenated (fleet.secrets requires
# [a-z0-9-]) and the *File paths point at the matching /run/credentials path. The
# module's own LoadCredential[Encrypted] lists are force-cleared so fleet.secrets'
# dropins are the sole source. The two webhook secrets shared with hooks are
# declared in hooks.nix. The frontend-root vhost needs the package store path, so
# it is set on services.gio.reverse-proxy here; the fleet endpoint is DNS/consul/
# healthcheck only. Converted from nix/hosts/carbon/gradient.nix.
{inputs, ...}: {
  den.aspects.carbon.nixos = {
    perSystem,
    config,
    lib,
    ...
  }: let
    port = 3002;
    workerUuid = "4f7f7bfb-6013-405a-9a5f-fc98449725d7";
    cred = name: "/run/credentials/gradient-server.service/${name}";
  in {
    imports = [
      inputs.gradient.nixosModules.default
    ];

    environment.systemPackages = [
      (perSystem.gradient.gradient-cli.override {cargoFeatures = ["nix"];})
    ];

    services.gradient = {
      enable = true;
      domain = "gradient.gio.ninja";
      listenAddr = "127.0.0.1";
      inherit port;

      jwtSecretFile = cred "gradient-jwt-secret";
      cryptSecretFile = cred "gradient-crypt-secret";

      configurePostgres = false;

      reverseProxy = {
        nginx.enable = false;
        caddy.enable = false;
      };

      metricsTokenFile = cred "gradient-metrics-token";

      s3 = {
        enable = true;
        bucket = "gradient-cache";
        region = "garage";
        endpoint = "https://s3.garage.gio.ninja";
        accessKeyId = "GKb766c18968f8306d6255f700";
        secretAccessKeyFile = cred "gradient-s3-secret-key";
        virtualHostedStyle = false;
      };

      oidc = {
        enable = true;
        required = true;
        clientId = "cbb53080-6e3e-4aa5-bb83-9b206522c6f3";
        clientSecretFile = cred "gradient-oidc-client-secret";
        discoveryUrl = "https://login.gio.ninja/.well-known/openid-configuration";
        scopes = ["openid" "email" "profile"];
      };

      githubApp = {
        enable = true;
        appId = 3999286;
        privateKeyFile = cred "gradient-github-app-private-key";
        webhookSecretFile = cred "gradient-github-app-webhook-secret";
      };

      state = {
        users.gio = {
          email = "gio@damelio.net";
          superuser = true;
          email_verified = true;
        };

        organizations.default = {
          display_name = "gio.ninja";
          private_key_file = cred "gradient-org-private-key";
          created_by = "gio";
          github_installation_id = 138901592;
        };

        workers.carbon-local = {
          display_name = "carbon-local";
          worker_id = workerUuid;
          organizations = ["default"];
          token_file = cred "gradient-worker-token";
          created_by = "gio";
          enable_fetch = true;
          enable_eval = true;
          enable_build = true;
        };

        caches.main = {
          display_name = "Main Cache";
          organizations = ["default"];
          signing_key_file = cred "gradient-cache-signing-key";
          created_by = "gio";
        };

        projects.yesman = {
          organization = "default";
          display_name = "Yesman";
          repository = "https://forgejo.gio.ninja/giodamelio/yesman.git";
          wildcard = "packages.x86_64-linux.default";
          created_by = "gio";

          triggers = [
            {
              type = "reporter_push";
              integration = "forgejo-inbound";
              config = {
                branches = ["main"];
                tags = [];
                releases_only = false;
              };
            }
          ];

          actions = [
            {
              name = "forgejo-status";
              type = "forge_status_report";
              config = {
                integration = "forgejo-outbound";
              };
            }
            {
              name = "deploy-webhook";
              type = "send_web_request";
              events = ["evaluation.completed"];
              config = {
                url = "https://hooks.gio.ninja:47291/gradient-deploy-yesman";
                token_file = cred "gradient-action-deploy-webhook-token";
              };
            }
          ];
        };

        projects.eater-of-feeds = {
          organization = "default";
          display_name = "Eater of Feeds";
          repository = "https://forgejo.gio.ninja/giodamelio/eater-of-feeds.git";
          wildcard = "packages.x86_64-linux.default";
          created_by = "gio";

          triggers = [
            {
              type = "reporter_push";
              integration = "forgejo-inbound";
              config = {
                branches = ["main"];
                tags = [];
                releases_only = false;
              };
            }
          ];

          actions = [
            {
              name = "forgejo-status";
              type = "forge_status_report";
              config = {
                integration = "forgejo-outbound";
              };
            }
            {
              name = "deploy-webhook";
              type = "send_web_request";
              events = ["evaluation.completed"];
              config = {
                url = "https://hooks.gio.ninja:47291/gradient-deploy-eater-of-feeds";
                token_file = cred "gradient-action-deploy-webhook-token";
              };
            }
          ];
        };

        projects.nixos-configs = {
          organization = "default";
          display_name = "NixOS Configs";
          repository = "https://github.com/giodamelio/nixos-configs.git";
          wildcard = "nixosConfigurations.*.config.system.build.toplevel,packages.x86_64-linux.*";
          created_by = "gio";

          triggers = [
            {
              type = "reporter_push";
              integration = "github";
              config = {
                branches = ["main"];
                tags = [];
                releases_only = false;
              };
            }
          ];
        };

        integrations = {
          forgejo-inbound = {
            organization = "default";
            kind = "inbound";
            forge_type = "forgejo";
            secret_file = cred "gradient-forgejo-webhook-secret";
            created_by = "gio";
          };
          forgejo-outbound = {
            organization = "default";
            kind = "outbound";
            forge_type = "forgejo";
            endpoint_url = "https://forgejo.gio.ninja";
            access_token_file = cred "gradient-forgejo-access-token";
            created_by = "gio";
          };
        };
      };
    };

    services.gradient.worker = {
      enable = true;
      serverUrl = "wss://gradient.gio.ninja/proto";
      workerId = workerUuid;
      peersFile = "/run/credentials/gradient-worker.service/gradient-worker-peers";

      reverseProxy = {
        nginx.enable = false;
        caddy.enable = false;
      };

      capabilities = {
        fetch = true;
        eval = true;
        build = true;
        federate = false;
      };

      settings = {
        maxConcurrentBuilds = 8;
        maxConcurrentEvaluations = 1;
        buildMetrics = true;
      };
    };

    nix.settings.trusted-users = ["gradient-worker"];

    services.postgresql = {
      ensureDatabases = ["gradient"];
      ensureUsers = [
        {
          name = "gradient";
          ensureDBOwnership = true;
        }
      ];
      identMap = lib.mkAfter ''
        gradient root gradient
        gradient gradient gradient
      '';
      authentication = lib.mkAfter ''
        local all gradient peer map=gradient
      '';
    };

    # The module derives LoadCredential[Encrypted] entries from the *File paths
    # (legacy underscore names). Clear both lists so fleet.secrets' dropins are the
    # sole source of the (hyphenated) credentials.
    systemd.services.gradient-server.serviceConfig = {
      LoadCredential = lib.mkForce [];
      LoadCredentialEncrypted = lib.mkForce [];
    };
    systemd.services.gradient-worker.serviceConfig = {
      LoadCredential = lib.mkForce [];
      LoadCredentialEncrypted = lib.mkForce [];
    };

    # Frontend-root vhost needs the package store path → set here (perSystem/config
    # scope), not in the fleet endpoint.
    services.gio.reverse-proxy = {
      enable = true;
      virtualHosts.gradient = {
        reverseProxy = false;
        host = "localhost";
        inherit port;
        extraConfig = ''
          handle /api/* {
            reverse_proxy 127.0.0.1:${toString port}
          }
          handle /cache/* {
            reverse_proxy 127.0.0.1:${toString port}
          }
          handle /proto {
            reverse_proxy 127.0.0.1:${toString port}
          }
          handle {
            root * ${config.services.gradient.packages.frontend}/share/gradient-frontend
            try_files {path} /index.html
            file_server
          }
        '';
      };
    };
  };

  # DNS/consul/healthcheck only — vhost provided above.
  den.hosts.x86_64-linux.carbon.services.gradient = {
    endpoint = {
      domain = "gradient";
      proxy = false;
    };
    healthcheck.target = "https://gradient.gio.ninja/api/health";
  };

  # All gradient secrets are existing/coordinated values → manual (paste with
  # `credsync write`). The two webhook secrets shared with hooks are declared in
  # hooks.nix (use-sites on both units). gradient-metrics-token also gets a
  # prometheus use-site in Phase F (merges with this declaration).
  fleet.secrets = let
    onServer = {
      origin = "carbon";
      use.carbon.services.gradient-server.type = "credential";
    };
  in {
    gradient-jwt-secret = onServer;
    gradient-crypt-secret = onServer;
    gradient-metrics-token = onServer;
    gradient-s3-secret-key = onServer;
    gradient-oidc-client-secret = onServer;
    gradient-org-private-key = onServer;
    gradient-cache-signing-key = onServer;
    gradient-worker-token = onServer;
    gradient-github-app-private-key = onServer;
    gradient-forgejo-webhook-secret = onServer;
    gradient-forgejo-access-token = onServer;
    gradient-worker-peers = {
      origin = "carbon";
      use.carbon.services.gradient-worker.type = "credential";
    };
    # Consumed by the deployed-apps gradient-deployer agent (eater/yesman slots).
    gradient-deployer-api-key = {
      origin = "carbon";
      use.carbon.services.gradient-deployer.type = "credential";
    };
  };
}
