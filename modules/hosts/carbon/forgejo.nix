# forgejo — git forge (forgejo.gio.ninja) with PocketID SSO and a nix Actions
# runner. Repos live on the NFS-mounted /mnt/forgejo-repos (see nfs.nix); the
# forgejo user joins the nfs-forgejo group and the service waits on the mount via
# the fleet.services `mounts` facet. OIDC + runner secrets move to fleet.secrets
# credentials. Converted from nix/hosts/carbon/forgejo.nix.
_: {
  den.aspects.carbon.nixos = {
    lib,
    pkgs,
    ...
  }: let
    settingsFormat = pkgs.formats.yaml {};

    mkRunner = name: {
      url,
      labels,
      user,
      group,
      credential,
      stateDir,
      hostPackages ? [],
      settings ? {},
      extraServiceConfig ? {},
      supplementaryGroups ? [],
    }: let
      configFile = settingsFormat.generate "runner-config-${name}.yaml" settings;
      registrationScript = pkgs.writeShellApplication {
        name = "register-runner-${name}";
        runtimeInputs = [pkgs.forgejo-runner pkgs.coreutils];
        text = ''
          mkdir -p "/var/lib/${stateDir}/${name}"
          cd "/var/lib/${stateDir}/${name}"

          LABELS_WANTED="$(echo '${lib.concatStringsSep "\n" labels}' | sort)"
          LABELS_CURRENT="$(cat .labels 2>/dev/null || echo "")"

          if [ ! -e .runner ] || [ "$LABELS_WANTED" != "$LABELS_CURRENT" ]; then
            rm -f .runner
            # shellcheck source=/dev/null
            . "$CREDENTIALS_DIRECTORY/${credential}"
            act_runner register \
              --no-interactive \
              --instance ${lib.escapeShellArg url} \
              --token "$TOKEN" \
              --name ${lib.escapeShellArg name} \
              --labels ${lib.escapeShellArg (lib.concatStringsSep "," labels)} \
              --config ${configFile}
            echo "$LABELS_WANTED" > .labels
          fi
        '';
      };
    in {
      description = "Forgejo Runner (${name})";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];
      path = hostPackages;
      serviceConfig =
        {
          User = user;
          Group = group;
          StateDirectory = stateDir;
          WorkingDirectory = "-/var/lib/${stateDir}/${name}";
          ExecStartPre = ["${lib.getExe registrationScript}"];
          ExecStart = "${pkgs.forgejo-runner}/bin/act_runner daemon --config ${configFile}";
          Restart = "on-failure";
          RestartSec = 2;
          SupplementaryGroups = supplementaryGroups;
        }
        // extraServiceConfig;
    };
  in {
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

        webhook = {
          ALLOWED_HOST_LIST = "gradient.gio.ninja";
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

    # Forgejo user needs write access to the NFS-mounted repos.
    users.users.forgejo.extraGroups = ["nfs-forgejo"];

    virtualisation.podman.enable = true;

    systemd.services.forgejo-runner-build = mkRunner "forgejo-runner-build" {
      url = "https://forgejo.gio.ninja";
      labels = ["nix:host"];
      user = "forgejo-runner";
      group = "forgejo-runner";
      credential = "forgejo-runner-env";
      stateDir = "forgejo-runner";
      hostPackages = with pkgs; [
        attic-client
        bash
        coreutils
        curl
        gawk
        git
        gnused
        nix
        nodejs
        openssh
        wget
      ];
      settings = {
        log.level = "info";
        runner = {
          capacity = 2;
          timeout = "3h";
        };
      };
    };

    users.users.forgejo-runner = {
      isSystemUser = true;
      group = "forgejo-runner";
      home = "/var/lib/forgejo-runner";
      createHome = true;
    };
    users.groups.forgejo-runner = {};
  };

  den.hosts.x86_64-linux.carbon.services.forgejo = {
    endpoint = {
      domain = "forgejo";
      backend.host = "localhost";
      backend.port = 3300;
      # SSO auto-login (https://codeberg.org/forgejo/forgejo/issues/2382).
      extraConfig = "rewrite /user/login /user/oauth2/PocketID";
    };
    healthcheck.target = "https://forgejo.gio.ninja/api/v1/version";
    mounts = ["forgejo"]; # wait for the NFS repo mount before starting
  };

  fleet.secrets = {
    forgejo-oidc-client-id.origin = "carbon";
    forgejo-oidc-client-id.use.carbon.services.forgejo.type = "credential";
    forgejo-oidc-client-secret.origin = "carbon";
    forgejo-oidc-client-secret.use.carbon.services.forgejo.type = "credential";
    forgejo-runner-env.origin = "carbon";
    forgejo-runner-env.use.carbon.services.forgejo-runner-build.type = "credential";
  };
}
