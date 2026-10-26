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
                url = "https://deploy-hooks.external.gio.ninja/yesman";
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
                url = "https://deploy-hooks.external.gio.ninja/eater-of-feeds";
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

    # The gradient module reads each secret from %d/<underscore-id> (its own
    # LoadCredential sources them from the *File paths). fleet.secrets can only
    # name blobs [a-z0-9-], so map each module credential id to the hyphenated
    # credstore blob: LoadCredentialEncrypted=<id>:<blob>, which wins over the
    # module's circular LoadCredential (last-wins, as Blueprint did). The module's
    # own non-secret LoadCredential (gradient_database_url, gradient_state) is left
    # untouched. The blobs are delivered to the credstore by fleet.secrets (origin
    # carbon, below).
    systemd.services.gradient-server.serviceConfig.LoadCredentialEncrypted = [
      "gradient_jwt_secret:gradient-jwt-secret"
      "gradient_crypt_secret:gradient-crypt-secret"
      "gradient_oidc_client_secret:gradient-oidc-client-secret"
      "gradient_s3_secret_access_key:gradient-s3-secret-key"
      "gradient_metrics_token:gradient-metrics-token"
      "gradient_org_default_private_key:gradient-org-private-key"
      "gradient_cache_main_signing_key:gradient-cache-signing-key"
      "gradient_worker_${workerUuid}_token:gradient-worker-token"
      "gradient_integration_forgejo-inbound_secret:gradient-forgejo-webhook-secret"
      "gradient_integration_forgejo-outbound_token:gradient-forgejo-access-token"
      "gradient_action_deploy-webhook_token:gradient-action-deploy-webhook-token"
      "gradient_github_app_private_key:gradient-github-app-private-key"
      "gradient_github_app_webhook_secret:gradient-github-app-webhook-secret"
    ];
    systemd.services.gradient-worker.serviceConfig.LoadCredentialEncrypted = [
      "gradient_worker_peers:gradient-worker-peers"
    ];

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
    "prometheus-endpoint" = {
      target = "gradient.gio.ninja";
      scheme = "https";
      auth.credentialsFile = "/run/credentials/prometheus.service/gradient-metrics-token";
    };
  };

  # All gradient secrets are existing/coordinated values → manual (paste with
  # `credsync write`). gradient-server/worker read them via the underscore
  # credential ids mapped above, so they only need to reach the credstore
  # (origin=carbon, no use-site). metrics-token also has a prometheus use-site
  # (direct path read); the deployer api key is read directly by the agent. The
  # two webhook secrets shared with hooks are declared in hooks.nix (credstore +
  # a webhookcatcher use-site).
  fleet.secrets = let
    inCredstore = {origin = "carbon";};
  in {
    gradient-jwt-secret = inCredstore;
    gradient-crypt-secret = inCredstore;
    gradient-s3-secret-key = inCredstore;
    gradient-oidc-client-secret = inCredstore;
    gradient-org-private-key = inCredstore;
    gradient-cache-signing-key = inCredstore;
    gradient-worker-token = inCredstore;
    gradient-github-app-private-key = inCredstore;
    gradient-forgejo-webhook-secret = inCredstore;
    gradient-forgejo-access-token = inCredstore;
    gradient-worker-peers = inCredstore;
    gradient-metrics-token = {
      origin = "carbon";
      use.carbon.services.prometheus.type = "credential";
    };
    gradient-deployer-api-key = {
      origin = "carbon";
      use.carbon.services.gradient-deployer.type = "credential";
    };
  };
}
