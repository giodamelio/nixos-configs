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
      package = mkOption {
        type = types.package;
        default = pkgs.postgresql_15;
      };
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
      inherit (cfg) enable package;

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

  config.systemd = lib.mkIf cfg.enable {
    targets = {
      # After this target, PostgreSQL is ready for applications to access it
      # Setup scripts have run and it is listening for connections
      postgresql-ready = let
        waitFor = ["postgresql-ready.service"];
      in {
        description = "PostgreSQL ready for applications";
        requires = waitFor;
        after = waitFor;
      };
    };

    services = {
      postgresql-ready = {
        description = "Wait for PostgreSQL to be ready";
        wantedBy = ["default.target"];
        requires = ["postgresql.service"];
        serviceConfig = {
          Type = "oneshot";
        };
        script = ''
          while ! ${cfg.package}/bin/pg_isready
          do
            echo "$(date) - waiting for database to start"
            sleep 0.25
          done
        '';
      };
    };
  };

  # Backup database with Restic
  # config.systemd.services.postgres-backup = {
  #   description = "Backup postgres";
  #   requires = ["postgresql.service"];
  #   after = ["postgres-ready.service"];
  #   serviceConfig = {
  #     Type = "oneshot";
  #     LoadCredentialEncrypted = [
  #       "postgres-backup-restic"
  #       "postgres-backup-restic-password"
  #     ];
  #     User = "postgres";
  #   };
  #   script = ''
  #     # ${pkgs.restic}/bin/restic init
  #     set -o pipefail
  #     ${pkgs.postgresql}/bin/pg_dumpall | ${pkgs.restic}/bin/restic backup --stdin --stdin-filename="${config.networking.hostName}.sql"
  #   '';
  #   environment = {
  #     RESTIC_REPOSITORY = "s3:garage.gio.ninja/backup-postgres";
  #     RESTIC_PASSWORD_FILE = "%d/postgres-backup-restic-password";
  #
  #     AWS_DEFAULT_REGION = "garage";
  #     AWS_SHARED_CREDENTIALS_FILE = "%d/postgres-backup-restic";
  #   };
  # };

  # Add pgcli the nicer CLI to the system
  config.environment.systemPackages = lib.mkIf cfg.enable [
    pkgs.pgcli
  ];
}
