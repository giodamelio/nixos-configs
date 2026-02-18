{
  pkgs,
  config,
  ...
}: {
  environment.systemPackages = with pkgs; [
    natscli
    nats-top
  ];

  services.nats = {
    enable = true;
    jetstream = true;
    serverName = config.networking.hostName;
    settings = {
      http = "127.0.0.1:8222";

      websocket = {
        port = 9222;
        no_tls = true;
      };

      cluster = {
        name = "homelab";
        listen = "0.0.0.0:4248";
        routes = [
          "nats://carbon.gio.ninja:4248"
          "nats://gallium.gio.ninja:4248"
        ];
      };
    };
  };

  networking.firewall.allowedTCPPorts = [
    4248 # NATS Clustering
    4222 # Client Connections
  ];

  services.gio.reverse-proxy = {
    enable = true;
    virtualHosts = {
      "nats-ws" = {
        host = "localhost";
        port = 9222;
      };
    };
  };
}
