{
  inputs,
  perSystem,
  config,
  lib,
  ...
}: let
  port = 3002;
  workerUuid = "4f7f7bfb-6013-405a-9a5f-fc98449725d7";
in {
  imports = [
    inputs.gradient.nixosModules.default
  ];

  environment.systemPackages = [
    perSystem.gradient.gradient-cli
  ];

  services.gradient = {
    enable = true;
    domain = "gradient.gio.ninja";
    listenAddr = "127.0.0.1";
    inherit port;

    jwtSecretFile = "/run/credentials/gradient-server.service/gradient-jwt-secret";
    cryptSecretFile = "/run/credentials/gradient-server.service/gradient-crypt-secret";

    configurePostgres = false;

    reverseProxy = {
      nginx.enable = false;
      caddy.enable = false;
    };

    metricsTokenFile = "/run/credentials/gradient-server.service/gradient-metrics-token";

    s3 = {
      enable = true;
      bucket = "gradient-cache";
      region = "garage";
      endpoint = "https://s3.garage.gio.ninja";
      accessKeyId = "GKb766c18968f8306d6255f700";
      secretAccessKeyFile = "/run/credentials/gradient-server.service/gradient-s3-secret-key";
      virtualHostedStyle = false;
    };

    oidc = {
      enable = true;
      required = true;
      clientId = "cbb53080-6e3e-4aa5-bb83-9b206522c6f3";
      clientSecretFile = "/run/credentials/gradient-server.service/gradient-oidc-client-secret";
      discoveryUrl = "https://login.gio.ninja/.well-known/openid-configuration";
      scopes = ["openid" "email" "profile"];
    };

    # Instance-wide GitHub App, registered once on GitHub. Gates the
    # /api/v1/hooks/github webhook handler (without it Gradient returns
    # 503 "github app integration not configured"). The webhook secret is
    # the same one webhookcatcher verifies at the edge before forwarding.
    githubApp = {
      enable = true;
      appId = 3999286;
      privateKeyFile = "/run/credentials/gradient-server.service/gradient_github_app_private_key";
      webhookSecretFile = "/run/credentials/gradient-server.service/gradient_github_app_webhook_secret";
    };

    state = {
      users.gio = {
        email = "gio@damelio.net";
        superuser = true;
        email_verified = true;
      };

      organizations.default = {
        display_name = "gio.ninja";
        private_key_file = "/run/credentials/gradient-server.service/gradient-org-private-key";
        created_by = "gio";
        # Bind the GitHub App installation (on the `giodamelio` account) to this
        # org. The auto-link matches org *name* to the GitHub login, which would
        # require renaming this org from "default" to "giodamelio"; setting the
        # installation id explicitly avoids that. The provisioner writes it on
        # every reconcile and seeds the auto-managed `github` inbound/outbound
        # integration rows that the nixos-configs push trigger references.
        github_installation_id = 138901592;
      };

      workers.carbon-local = {
        display_name = "carbon-local";
        worker_id = workerUuid;
        organizations = ["default"];
        token_file = "/run/credentials/gradient-server.service/gradient-worker-token";
        created_by = "gio";
        enable_fetch = true;
        enable_eval = true;
        enable_build = true;
      };

      caches.main = {
        display_name = "Main Cache";
        organizations = ["default"];
        signing_key_file = "/run/credentials/gradient-server.service/gradient-cache-signing-key";
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
          # Report CI status back to Forgejo commits. On the Actions framework
          # this is no longer automatic for an outbound integration — it must be
          # declared as a forge_status_report action. Events are derived from
          # build state, so the events list must stay empty.
          {
            name = "forgejo-status";
            type = "forge_status_report";
            config = {
              integration = "forgejo-outbound";
            };
          }
          # Notify the gradient-deployer agent when an evaluation finishes
          # successfully. evaluation.completed fires once per run (unlike
          # build.completed, which fires per derivation). The agent resolves the
          # entry-point build output via the Gradient API and deploys it.
          # token_file is the runtime location of the bearer credential
          # (gradient_action_deploy-webhook_token, in the server's encrypted
          # creds); the agent compares incoming bearers against the same secret.
          {
            name = "deploy-webhook";
            type = "send_web_request";
            events = ["evaluation.completed"];
            config = {
              # Posts to webhookcatcher (a hostname — Gradient's SSRF guard blocks
              # the loopback ingress directly), which verifies the bearer and
              # forwards to the local Restate ingress → gradient-deployer.
              url = "https://hooks.gio.ninja:47291/gradient-deploy-yesman";
              token_file = "/run/credentials/gradient-server.service/gradient_action_deploy-webhook_token";
            };
          }
        ];
      };

      projects.nixos-configs = {
        organization = "default";
        display_name = "NixOS Configs";
        repository = "https://github.com/giodamelio/nixos-configs.git";
        # Build every machine's system closure (so deploys pull from the cache)
        # plus the flake's own packages. Comma-separated include patterns.
        wildcard = "nixosConfigurations.*.config.system.build.toplevel,packages.x86_64-linux.*";
        created_by = "gio";

        # Fire on pushes delivered via the GitHub App webhook. "github" is the
        # reserved, auto-seeded inbound integration created when the org carries
        # a github_installation_id (above); it is not declared in `integrations`.
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
          secret_file = "/run/credentials/gradient-server.service/gradient-forgejo-webhook-secret";
          created_by = "gio";
        };
        forgejo-outbound = {
          organization = "default";
          kind = "outbound";
          forge_type = "forgejo";
          endpoint_url = "https://forgejo.gio.ninja";
          access_token_file = "/run/credentials/gradient-server.service/gradient-forgejo-access-token";
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

  # Gradient module generates LoadCredential entries from *File paths,
  # but we use systemd-creds encrypted files. Adding LoadCredentialEncrypted
  # with the same credential names overrides the module's entries ("last one wins").
  systemd.services.gradient-server.serviceConfig.LoadCredentialEncrypted = [
    "gradient_jwt_secret"
    "gradient_crypt_secret"
    "gradient_oidc_client_secret"
    "gradient_s3_secret_access_key"
    "gradient_metrics_token"
    "gradient_org_default_private_key"
    "gradient_cache_main_signing_key"
    "gradient_worker_${workerUuid}_token"
    "gradient_integration_forgejo-inbound_secret"
    "gradient_integration_forgejo-outbound_token"
    "gradient_action_deploy-webhook_token"
    "gradient_github_app_private_key"
    "gradient_github_app_webhook_secret"
  ];

  systemd.services.gradient-worker.serviceConfig.LoadCredentialEncrypted = [
    "gradient_worker_peers"
  ];

  # Prometheus needs the metrics token to scrape Gradient
  gio.credentials = {
    enable = true;
    services.prometheus.loadCredentialEncrypted = ["gradient_metrics_token"];
  };

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

  gio.services.gradient.consul = {
    name = "gradient";
    address = "gradient.gio.ninja";
    port = 443;
    checks = [
      {
        http = "https://gradient.gio.ninja/api/health";
        interval = "60s";
      }
    ];
  };
}
