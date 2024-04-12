_: {pkgs, ...}: let
  db_name = "tsdb";
in {
  # Setup TimescaleDB database
  gio.services.postgres = {
    enable = true;
    timescaledb = true;
    databases = [db_name];
  };
  # Map telegraf system user to correct username
  services.postgresql = {
    authentication = ''
      # Allow unix socket connections with a username map for tsdb
      local tsdb ${db_name} peer map=tsdb
    '';
    identMap = ''
      tsdb telegraf ${db_name}
    '';
  };

  # Configure Telegraf to send stats to to TSDB
  services.telegraf = {
    enable = true;
    extraConfig = {
      inputs = {
        # System Stats
        cpu = {};
        disk = {};
        diskio = {};
        kernel = {};
        linux_sysctl_fs = {};
        mem = {};
        netstat = {};
        processes = {};
        smart = {
          path_smartctl = "${pkgs.smartmontools}/bin/smartctl";
          path_nvme = "${pkgs.nvme-cli}/bin/nvme";
        };
        swap = {};
        system = {};
        systemd_units = [
          {unittype = "service";}
          {unittype = "timer";}
        ];
        zfs = {};

        # Monitor PostgreSQL
        postgresql = {
          address = "host=/run/postgresql user=${db_name} sslmode=disable";
        };
      };
      outputs.postgresql = {
        connection = "host=/run/postgresql dbname=${db_name} user=${db_name} sslmode=disable";

        # Make it work with TSDB
        tags_as_foreign_keys = true;
        create_templates = [
          "CREATE EXTENSION IF NOT EXISTS timescaledb"
          "CREATE TABLE {{ .table }} ({{ .columns }})"
          "SELECT create_hypertable({{ .table|quoteLiteral }}, by_range('time', INTERVAL '1 week'), if_not_exists := true)"
        ];
      };
    };
  };
}
