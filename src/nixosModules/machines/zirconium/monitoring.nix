_: _: let
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
        cpu = {};
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
