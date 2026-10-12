# netdata child on gallium — streams metrics to carbon's netdata parent
# (carbon.gio.ninja:19999). The shared stream api-key is a fleet.secrets credential
# (declared on the carbon parent, origin=carbon; this child is a use-site); it is
# read from /run/credentials/netdata.service/netdata-api-key.
#
# cronitor (the dead-man's-switch the Blueprint child also carried) is NOT ported
# here — the parent's own health alarms cover a child going stale.
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
      # Feed it our nixpkgs' netdata, as carbon does. Bare, giopkgs supplies its
      # own older pin, which predates the plugins.d/go.d.plugin -> godplugin
      # rename the nixpkgs module's security.wrapper expects.
      package = perSystem.giopkgs.netdata.override {inherit (pkgs) netdata;};
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

  # The shared netdata-api-key is now declared in modules/hosts/carbon/netdata.nix
  # (origin=carbon, the parent); this child is a use-site there. It still reads the
  # key from /run/credentials/netdata.service/netdata-api-key.
}
