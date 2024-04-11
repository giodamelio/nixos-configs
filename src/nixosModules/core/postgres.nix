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
      databases = mkOption {
        type = types.listOf types.str;
      };
    };
  };

  # Ensure there is a database created for each item in cfg.databases
  # Also create a user with the same name that is the databases owner
  config.services.postgresql = lib.mkIf cfg.enable {
    enable = true;
    ensureDatabases = cfg.databases;
    ensureUsers =
      builtins.map (name: {
        inherit name;
        ensureDBOwnership = true;
      })
      cfg.databases;
  };

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

  # Add pgcli the nicer CLI to the system
  config.environment.systemPackages = lib.mkIf cfg.enable [
    pkgs.pgcli
  ];
}
