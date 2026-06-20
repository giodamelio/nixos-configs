# netdata parent on carbon (netdata.gio.ninja) — dbengine store, cloud UI, accepts
# child streams (gallium) authenticated by the shared api-key. Pushover health
# alerts. Now that carbon is a den host the shared netdata-api-key flips to
# origin=carbon (the parent owns it) and is consumed by both the carbon parent and
# the gallium child; gallium/netdata.nix no longer declares it. cronitor (the
# Blueprint watchdog) is not ported — no den cronitor aspect yet. Converted from
# nix/hosts/carbon/netdata.nix + netdata-parent.nix + netdata-integrations.nix.
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
        [file:/run/credentials/netdata.service/netdata-api-key]
            enabled = yes
            allow from = *
      '';
    };

    environment.etc."netdata/health_alarm_notify.conf".source = pkgs.writeText "health_alarm_notify.conf" ''
      SEND_PUSHOVER="YES"
      PUSHOVER_APP_TOKEN="$(cat /run/credentials/netdata.service/netdata-pushover-app-token)"
      DEFAULT_RECIPIENT_PUSHOVER="$(cat /run/credentials/netdata.service/netdata-pushover-user-token)"
    '';

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
    systemd.services.postgresql-setup.script =
      lib.mkIf config.services.postgresql.enable (lib.mkAfter ''
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

  fleet.secrets = {
    # Shared stream key — origin is now carbon (the parent validates children
    # against it); delivered to both the carbon parent and the gallium child.
    netdata-api-key = {
      origin = "carbon";
      use.carbon.services.netdata.type = "credential";
      use.gallium.services.netdata = {
        type = "credential";
        restartOnChange = true;
      };
    };
    netdata-pushover-app-token = {
      origin = "carbon";
      use.carbon.services.netdata.type = "credential";
    };
    netdata-pushover-user-token = {
      origin = "carbon";
      use.carbon.services.netdata.type = "credential";
    };
  };
}
