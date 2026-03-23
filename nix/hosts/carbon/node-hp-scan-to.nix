{perSystem, ...}: {
  # Dedicated scanner system user in the paperless group
  users.users.node-hp-scan-to = {
    isSystemUser = true;
    group = "node-hp-scan-to";
    extraGroups = ["paperless"];
  };
  users.groups.node-hp-scan-to = {};

  # Ensure consume directory is group-writable for the paperless group
  systemd.tmpfiles.rules = [
    "d /var/lib/paperless/consume 0770 paperless paperless -"
  ];

  # Systemd service for node-hp-scan-to
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

  # Consul health check
  gio.services.node-hp-scan-to.consul = {
    name = "node-hp-scan-to";
    address = "carbon";
    port = 19201;
    checks = [
      {
        http = "http://localhost:19201/";
        interval = "60s";
      }
    ];
  };
}
