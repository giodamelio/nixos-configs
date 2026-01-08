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
  ];
}
