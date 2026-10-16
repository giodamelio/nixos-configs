# node-hp-scan-to — watches the HP scanner and drops scans into paperless'
# consume dir. Custom systemd service, dedicated user in the paperless group;
# health-check only (no vhost), registered in consul by host name.
_: {
  den.aspects.carbon.nixos = {perSystem, ...}: {
    users.users.node-hp-scan-to = {
      isSystemUser = true;
      group = "node-hp-scan-to";
      extraGroups = ["paperless"];
    };
    users.groups.node-hp-scan-to = {};

    systemd.tmpfiles.rules = [
      "d /var/lib/paperless/consume 0770 paperless paperless -"
    ];

    systemd.services.node-hp-scan-to = {
      description = "HP Network Scanner to Paperless";
      wantedBy = ["multi-user.target"];
      wants = ["network-online.target"];
      after = ["network-online.target"];

      environment.SUPPRESS_NO_CONFIG_WARNING = "1";

      serviceConfig = {
        ExecStart = "${perSystem.giopkgs.node-hp-scan-to}/bin/node-hp-scan-to -a 10.0.11.123 --health-check --health-check-port 19201 listen -d /var/lib/paperless/consume -l carbon --add-emulated-duplex --keep-files";
        Restart = "always";
        RestartSec = 10;
        User = "node-hp-scan-to";
        Group = "node-hp-scan-to";
      };
    };
  };

  # Health-check only (no reverse-proxy vhost); registered in consul by host name.
  den.hosts.x86_64-linux.carbon.services.node-hp-scan-to = {
    consul = {
      address = "carbon";
      port = 19201;
    };
    healthcheck = {
      protocol = "http";
      target = "http://localhost:19201/";
    };
  };
}
