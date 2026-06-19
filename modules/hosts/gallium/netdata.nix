# netdata child on gallium — streams metrics to carbon's netdata parent
# (carbon.gio.ninja:19999, still Blueprint until carbon migrates). Brought
# forward ahead of the carbon phase so monitoring keeps reporting across the
# first den cutover and we can see if the deploy breaks anything.
#
# The shared stream api-key moves from gio.credentials to a fleet.secrets
# credential use-site on netdata.service; stream.conf still reads it from
# /run/credentials/netdata.service/netdata-api-key, so the path is unchanged.
#
# TEMPORARY origin: the key is really carbon's (the parent owns it and validates
# children against it), but carbon isn't a den host yet, so fleet.secrets can't
# use origin = "carbon". It is pinned manually on gallium — paste carbon's
# EXISTING value with `credsync write` so the live parent accepts the stream; a
# freshly generated key would be rejected. When carbon migrates, flip origin to
# carbon and add the parent use-site (the value stays identical).
#
# cronitor (the dead-man's-switch the Blueprint child also carried) is NOT ported
# here — the parent's own health alarms cover a child going stale. Port it
# separately if the watchdog is still wanted.
# Converted from nix/modules/nixos/netdata-child.nix + netdata-integrations.nix.
_: {
  den.aspects.gallium.nixos = {
    pkgs,
    perSystem,
    config,
    lib,
    ...
  }: {
    services.netdata = {
      enable = true;
      package = perSystem.giopkgs.netdata;
      enableAnalyticsReporting = false;

      config = {
        global = {
          "memory mode" = "ram"; # child holds nothing locally; the parent persists
          "update every" = 1;
        };
        web = {
          "bind to" = "127.0.0.1";
        };
      };

      configDir."stream.conf" = pkgs.writeText "stream.conf" ''
        [stream]
            enabled = yes
            destination = carbon.gio.ninja:19999
            api key = file:/run/credentials/netdata.service/netdata-api-key
      '';
    };

    # netdata postgres collector (was netdata-integrations.nix). gallium runs
    # postgres, so grant netdata a read-only monitoring role over a peer socket.
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
  };

  # Shared stream key. Manual (no generator) + temporary gallium origin — see the
  # header. Credential lands at /run/credentials/netdata.service/netdata-api-key.
  fleet.secrets.netdata-api-key = {
    origin = "gallium";
    use.gallium.services.netdata = {
      type = "credential";
      restartOnChange = true;
    };
  };
}
