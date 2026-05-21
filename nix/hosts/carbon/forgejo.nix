{
  config,
  lib,
  pkgs,
  ...
}: {
  services.forgejo = {
    enable = true;
    package = pkgs.forgejo;

    database = {
      type = "postgres";
      createDatabase = true;
    };

    repositoryRoot = "/mnt/forgejo-repos";

    lfs = {
      enable = true;
      contentDir = "/mnt/forgejo-repos/lfs";
    };

    settings = {
      server = {
        DOMAIN = "forgejo.gio.ninja";
        ROOT_URL = "https://forgejo.gio.ninja/";
        HTTP_ADDR = "127.0.0.1";
        HTTP_PORT = 3300;
      };

      service = {
        DISABLE_REGISTRATION = false;
        ENABLE_OPENID_SIGNIN = false;
        ENABLE_OPENID_SIGNUP = false;
        ALLOW_ONLY_EXTERNAL_REGISTRATION = true;
      };

      "oauth2_client" = {
        ENABLE_AUTO_REGISTRATION = true;
        ACCOUNT_LINKING = "auto";
        USERNAME = "email";
      };

      session = {
        COOKIE_SECURE = true;
        PROVIDER = "db";
      };

      actions = {
        ENABLED = true;
        DEFAULT_ACTIONS_URL = "https://code.forgejo.org";
      };

      "service.explore" = {
        REQUIRE_SIGNIN_VIEW = true;
      };

      repository = {
        DEFAULT_BRANCH = "main";
      };
    };
  };

  services.postgresql = {
    identMap = lib.mkAfter ''
      forgejo root forgejo
      forgejo forgejo forgejo
    '';
    authentication = lib.mkAfter ''
      local all forgejo peer map=forgejo
    '';
  };

  # Forgejo user needs write access to NFS-mounted repos
  users.users.forgejo.extraGroups = ["nfs-forgejo"];

  # Systemd credentials for OIDC and runner
  gio.credentials = {
    enable = true;
    services = {
      forgejo.loadCredentialEncrypted = [
        "forgejo-oidc-client-id"
        "forgejo-oidc-client-secret"
      ];
      "gitea-runner-register-carbon".loadCredentialEncrypted = [
        "forgejo-runner-env"
      ];
    };
  };

  # Reverse proxy with SSO auto-login rewrite
  # https://codeberg.org/forgejo/forgejo/issues/2382
  services.gio.reverse-proxy = {
    enable = true;
    virtualHosts.forgejo = {
      host = "localhost";
      port = 3300;
      extraConfig = ''
        rewrite /user/login /user/oauth2/PocketID
      '';
    };
  };

  # Consul service registration
  gio.services.forgejo.consul = {
    name = "forgejo";
    address = "forgejo.gio.ninja";
    port = 443;
    checks = [
      {
        http = "https://forgejo.gio.ninja/api/v1/version";
        interval = "60s";
      }
    ];
  };

  # Forgejo Actions runner (Podman containers + host-native)
  services.gitea-actions-runner = {
    package = pkgs.forgejo-runner;
    instances.carbon = {
      enable = true;
      name = "carbon";
      url = "https://forgejo.gio.ninja";
      tokenFile = "/run/credentials/gitea-runner-carbon.service/forgejo-runner-env";
      labels = [
        "ubuntu-latest:docker://node:22-bookworm"
        "debian-latest:docker://node:22-bookworm"
        "native:host"
      ];
      settings = {
        log.level = "info";
        runner = {
          capacity = 2;
          timeout = "3h";
        };
        container = {
          network = "bridge";
          privileged = false;
        };
      };
    };
  };

  virtualisation.podman.enable = true;

  # The NixOS module puts runner registration in ExecStartPre with TOKEN from
  # EnvironmentFile, but systemd can't load EnvironmentFile from credential paths.
  # We use a drop-in to clear ExecStartPre/EnvironmentFile, and a separate oneshot
  # that sources the credential then runs the module's registration script.
  systemd.packages = [
    (pkgs.runCommand "gitea-runner-carbon-cred-dropin" {} ''
      mkdir -p "$out/etc/systemd/system/gitea-runner-carbon.service.d"
      cat > "$out/etc/systemd/system/gitea-runner-carbon.service.d/60-clear-pre.conf" <<EOF
      [Service]
      EnvironmentFile=
      ExecStartPre=
      EOF
    '')
  ];

  systemd.services.gitea-runner-register-carbon = let
    registrationScript = builtins.head config.systemd.services.gitea-runner-carbon.serviceConfig.ExecStartPre;
  in {
    description = "Forgejo Runner Registration";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    before = ["gitea-runner-carbon.service"];
    requiredBy = ["gitea-runner-carbon.service"];
    serviceConfig = {
      Type = "oneshot";
      DynamicUser = true;
      User = "gitea-runner";
      StateDirectory = "gitea-runner";
    };
    script = ''
      set -a
      . "$CREDENTIALS_DIRECTORY/forgejo-runner-env"
      set +a
      exec ${registrationScript}
    '';
  };

  # Wait for NFS mount before starting Forgejo
  systemd.services.forgejo = {
    after = ["mnt-forgejo\\x2drepos.mount"];
    requires = ["mnt-forgejo\\x2drepos.mount"];
  };
}
