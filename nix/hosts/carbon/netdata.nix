{flake, ...}: {
  imports = [
    flake.nixosModules.netdata-parent
  ];

  services.gio.reverse-proxy = {
    enable = true;
    virtualHosts.netdata = {
      host = "localhost";
      port = 19999;
    };
  };

  gio.services.netdata.consul = {
    name = "netdata";
    address = "netdata.gio.ninja";
    port = 443;
    checks = [
      {
        http = "https://netdata.gio.ninja";
        interval = "60s";
      }
    ];
  };
}
