# netdata parent on carbon (netdata.gio.ninja) — dbengine store, cloud UI, accepts
# child streams (gallium) authenticated by the shared api-key, which agevault
# holds a copy of for each host. Pushover health alerts.
_: {
  den.aspects.carbon.nixos = {
    pkgs,
    perSystem,
    config,
    lib,
    ...
  }: {
    services.netdata = {
      enable = true;
      package = perSystem.giopkgs.netdata.override {
        netdata = pkgs.netdata.override {withCloudUi = true;};
      };
      enableAnalyticsReporting = false;

      config = {
        global = {
          "memory mode" = "dbengine";
          "update every" = 1;
        };
        web = {
          "bind to" = "*";
          "allow connections from" = "localhost *";
          "allow dashboard from" = "localhost *";
        };
      };

      configDir."stream.conf" = pkgs.writeText "stream.conf" ''
        [file:/run/credentials/netdata.service/netdata_api_key]
            enabled = yes
            allow from = *
      '';
    };

    environment.etc."netdata/health_alarm_notify.conf".source = pkgs.writeText "health_alarm_notify.conf" ''
      SEND_PUSHOVER="YES"
      PUSHOVER_APP_TOKEN="$(cat /run/credentials/netdata.service/netdata_pushover_app_token)"
      DEFAULT_RECIPIENT_PUSHOVER="$(cat /run/credentials/netdata.service/netdata_pushover_user_token)"
    '';

    fleet.credentials.needs = [
      "netdata_api_key"
      "netdata_pushover_app_token"
      "netdata_pushover_user_token"
    ];
    systemd.services.netdata.serviceConfig.LoadCredentialEncrypted = [
      "netdata_api_key"
      "netdata_pushover_app_token"
      "netdata_pushover_user_token"
    ];

    # netdata postgres collector (was netdata-integrations.nix); carbon runs postgres.
    services.postgresql = lib.mkIf config.services.postgresql.enable {
      ensureUsers = [{name = "netdata";}];
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

    networking.firewall.allowedTCPPorts = [19999];
  };

  den.hosts.x86_64-linux.carbon.services.netdata = {
    endpoint = {
      domain = "netdata";
      backend.host = "localhost";
      backend.port = 19999;
    };
    healthcheck.target = "https://netdata.gio.ninja";
  };
}
