{
  pkgs,
  config,
  ...
}: let
  inherit (pkgs) lib;
in {
  # Setup permissions for the PostgreSQL collector if there is a db on the host
  services.postgresql = lib.mkIf config.services.postgresql.enable {
    ensureUsers = [
      {
        name = "netdata";
      }
    ];
    identMap = lib.mkAfter ''
      netdata root netdata
      netdata netdata netdata
    '';
    authentication = lib.mkAfter ''
      local all netdata peer map=netdata
    '';
  };

  systemd.services.postgresql-setup.script = lib.mkIf config.services.postgresql.enable (lib.mkAfter ''
    psql -tAc "GRANT pg_monitor TO netdata"
  '');
}
