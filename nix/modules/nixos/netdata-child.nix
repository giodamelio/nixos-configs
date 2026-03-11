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
    package = perSystem.giopkgs.netdata;
    enableAnalyticsReporting = false;

    config = {
      global = {
        "memory mode" = "ram";
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

  gio.credentials = {
    enable = true;
    services.netdata.loadCredentialEncrypted = ["netdata-api-key"];
  };
}
