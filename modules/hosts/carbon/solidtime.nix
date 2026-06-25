# solidtime — Laravel time tracker (solidtime.gio.ninja) on PHP-FPM, postgres
# with peer auth. APP_KEY moves to a fleet.secrets secret with two use-sites: a
# credential file for the migrate oneshot and an env-wrapper (APP_KEY) for the
# php-fpm pool. The php_fastcgi vhost needs the package store path, so it is set
# directly on services.gio.reverse-proxy in the nixos block (perSystem-scoped);
# the fleet endpoint is DNS/consul/healthcheck only. Converted from
# nix/hosts/carbon/solidtime.nix.
_: {
  den.aspects.carbon.nixos = {
    config,
    lib,
    pkgs,
    perSystem,
    ...
  }: let
    solidtime = perSystem.giopkgs.solidtime;
    solidtimeRoot = "${solidtime}/share/php/solidtime";
    stateDir = "/var/lib/solidtime";

    php = pkgs.php83.withExtensions ({
      enabled,
      all,
    }:
      enabled
      ++ (with all; [
        bcmath
        exif
        gd
        intl
        mbstring
        pdo
        pdo_pgsql
        tokenizer
        zip
      ]));

    laravelEnv = {
      APP_NAME = "Solidtime";
      APP_ENV = "production";
      APP_URL = "https://solidtime.gio.ninja";

      LOG_CHANNEL = "stderr";
      LOG_LEVEL = "warning";

      DB_CONNECTION = "pgsql";
      DB_HOST = "/run/postgresql";
      DB_PORT = "5432";
      DB_DATABASE = "solidtime";
      DB_USERNAME = "solidtime";

      CACHE_STORE = "file";
      SESSION_DRIVER = "file";
      QUEUE_CONNECTION = "sync";

      APP_STORAGE_PATH = "${stateDir}/storage";
      APP_CONFIG_CACHE = "${stateDir}/bootstrap-cache/config.php";
      APP_ROUTES_CACHE = "${stateDir}/bootstrap-cache/routes-v7.php";
      APP_EVENTS_CACHE = "${stateDir}/bootstrap-cache/events.php";
      APP_SERVICES_CACHE = "${stateDir}/bootstrap-cache/services.php";
      APP_PACKAGES_CACHE = "${stateDir}/bootstrap-cache/packages.php";
    };

    envExports = lib.concatStringsSep "\n" (
      lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}") laravelEnv
    );
  in {
    users.users.solidtime = {
      isSystemUser = true;
      group = "solidtime";
      home = stateDir;
    };
    users.groups.solidtime = {};

    services.postgresql = {
      ensureDatabases = ["solidtime"];
      ensureUsers = [
        {
          name = "solidtime";
          ensureDBOwnership = true;
        }
      ];
      identMap = lib.mkAfter ''
        solidtime root solidtime
        solidtime solidtime solidtime
      '';
      authentication = lib.mkAfter ''
        local all solidtime peer map=solidtime
      '';
    };

    services.phpfpm.pools.solidtime = {
      user = "solidtime";
      group = "solidtime";
      phpPackage = php;
      settings = {
        "listen.owner" = config.services.caddy.user;
        "listen.group" = config.services.caddy.group;
        "pm" = "dynamic";
        "pm.max_children" = 5;
        "pm.start_servers" = 2;
        "pm.min_spare_servers" = 1;
        "pm.max_spare_servers" = 3;
        "php_admin_value[error_log]" = "stderr";
        "php_admin_flag[log_errors]" = true;
        "catch_workers_output" = true;
        "clear_env" = "no";
      };
      phpEnv = laravelEnv;
    };

    systemd.services.solidtime-setup = {
      description = "Solidtime setup (migrations and cache)";
      after = ["postgresql.service" "network.target"];
      requires = ["postgresql.service"];
      before = ["phpfpm-solidtime.service"];
      requiredBy = ["phpfpm-solidtime.service"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "solidtime";
        Group = "solidtime";
        StateDirectory = "solidtime";
        WorkingDirectory = solidtimeRoot;
      };

      script = ''
        mkdir -p ${stateDir}/storage/{app/public,framework/{cache,sessions,views},logs}
        mkdir -p ${stateDir}/bootstrap-cache

        ${envExports}
        export APP_KEY="$(cat "$CREDENTIALS_DIRECTORY/solidtime-app-key")"

        ${php}/bin/php ${solidtime}/bin/artisan migrate --force
      '';
    };

    # php_fastcgi vhost (needs the package store path → set here, not in the
    # fleet endpoint). Merges with the renderer's other vhosts.
    services.gio.reverse-proxy = {
      enable = true;
      virtualHosts.solidtime = {
        socket_path = "/run/phpfpm/solidtime.sock";
        reverseProxy = false;
        extraConfig = ''
          root * ${solidtimeRoot}/public
          php_fastcgi unix//run/phpfpm/solidtime.sock
          file_server
        '';
      };
    };
  };

  # DNS/consul/healthcheck only — the vhost is provided above.
  den.hosts.x86_64-linux.carbon.services.solidtime = {
    endpoint = {
      domain = "solidtime";
      proxy = false;
    };
    healthcheck.target = "https://solidtime.gio.ninja";
  };

  fleet.secrets.solidtime-app-key = {
    origin = "carbon";
    use.carbon.services.solidtime-setup.type = "credential";
    use.carbon.services.phpfpm-solidtime = {
      type = "env-wrapper";
      env-wrapper.variable = "APP_KEY";
    };
  };
}
