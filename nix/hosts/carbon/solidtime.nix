{
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

  # All Laravel environment variables (except APP_KEY which is a secret)
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

  # Shell export lines for the setup service
  envExports = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}") laravelEnv
  );
in {
  # System user
  users.users.solidtime = {
    isSystemUser = true;
    group = "solidtime";
    home = stateDir;
  };
  users.groups.solidtime = {};

  # PostgreSQL database with peer auth via socket
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

  # PHP-FPM pool
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

  # Credentials: APP_KEY injected into both services
  gio.credentials = {
    enable = true;
    services = {
      "solidtime-setup".loadCredentialEncrypted = ["solidtime-app-key"];
      "phpfpm-solidtime" = {
        loadCredentialEncrypted = ["solidtime-app-key"];
        execStartWrapper.environment = {
          APP_KEY = "solidtime-app-key";
        };
      };
    };
  };

  # Setup oneshot: create dirs, run migrations
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
      # Create writable Laravel directories
      mkdir -p ${stateDir}/storage/{app/public,framework/{cache,sessions,views},logs}
      mkdir -p ${stateDir}/bootstrap-cache

      # Export Laravel environment
      ${envExports}
      export APP_KEY="$(cat "$CREDENTIALS_DIRECTORY/solidtime-app-key")"

      # Run migrations
      ${php}/bin/php ${solidtime}/bin/artisan migrate --force
    '';
  };

  # Caddy reverse proxy with php_fastcgi
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

  # Consul service registration
  gio.services.solidtime.consul = {
    name = "solidtime";
    address = "solidtime.gio.ninja";
    port = 443;
    checks = [
      {
        http = "https://solidtime.gio.ninja";
        interval = "60s";
      }
    ];
  };
}
