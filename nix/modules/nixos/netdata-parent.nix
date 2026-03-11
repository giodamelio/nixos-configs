{
  pkgs,
  perSystem,
  ...
}: {
  imports = [
    ./netdata-integrations.nix
  ];

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

  gio.credentials = {
    enable = true;
    services.netdata.loadCredentialEncrypted = [
      "netdata-api-key"
      "netdata-pushover-app-token"
      "netdata-pushover-user-token"
    ];
  };

  networking.firewall.allowedTCPPorts = [19999];
}
