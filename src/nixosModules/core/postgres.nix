_: {
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.gio.services.postgres;
in {
  options = with lib; {
    gio.services.postgres = {
      enable = mkEnableOption (lib.mdDoc "PostgreSQL with Create DB and Users");
      timescaledb = mkOption {
        type = types.bool;
        default = false;
      };
      databases = mkOption {
        type = types.listOf types.str;
      };
    };
  };

  # Ensure there is a database created for each item in cfg.databases
  # Also create a user with the same name that is the databases owner
  config.services.postgresql = lib.mkIf cfg.enable (lib.mkMerge [
    {
      enable = true;
      package = pkgs.postgresql_15;

      ensureDatabases = cfg.databases;
      ensureUsers =
        builtins.map (name: {
          inherit name;
          ensureDBOwnership = true;
        })
        cfg.databases;
    }

    # TimescaleDB
    (lib.mkIf cfg.timescaledb {
      extraPlugins = [pkgs.postgresql15Packages.timescaledb];
      settings.shared_preload_libraries = "timescaledb";
    })
  ]);

  # Simple service that waits until PostgreSQL is ready
  # Intended so other services can wait to start until they can access the db
  config.systemd.services.postgres-ready = lib.mkIf cfg.enable {
    description = "Wait for PostgreSQL to be ready";
    wantedBy = ["default.target"];
    requires = ["postgresql.service"];
    serviceConfig = {
      Type = "oneshot";
    };
    script = ''
      while ! ${pkgs.postgresql}/bin/pg_isready
      do
        echo "$(date) - waiting for database to start"
        sleep 0.25
      done
    '';
  };

  # Backup database with Restic
  config.systemd.services.postgres-backup = {
    description = "Backup postgres";
    requires = ["postgresql.service"];
    after = ["postgres-ready.service"];
    serviceConfig = {
      Type = "oneshot";
      LoadCredentialEncrypted = [
        "postgres-backup-restic"
        "postgres-backup-restic-password"
      ];
      User = "postgres";
    };
    script = ''
      # ${pkgs.restic}/bin/restic init
      set -o pipefail
      ${pkgs.postgresql}/bin/pg_dumpall | ${pkgs.restic}/bin/restic backup --stdin --stdin-filename="${config.networking.hostName}.sql"
    '';
    environment = {
      RESTIC_REPOSITORY = "s3:garage.gio.ninja/backup-postgres";
      RESTIC_PASSWORD_FILE = "%d/postgres-backup-restic-password";

      AWS_DEFAULT_REGION = "garage";
      AWS_SHARED_CREDENTIALS_FILE = "%d/postgres-backup-restic";
    };
  };

  # Add pgcli the nicer CLI to the system
  config.environment.systemPackages = lib.mkIf cfg.enable [
    pkgs.pgcli
  ];
}
