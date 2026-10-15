# nats — JetStream-enabled NATS in a two-node homelab cluster (carbon + gallium).
# Shared server aspect; the websocket GUI vhost is declared per-host as a
# fleet.services endpoint (only gallium owns nats-ws.gio.ninja). Converted from
# nix/modules/nixos/nats.nix.
_: {
  den.aspects.nats.nixos = {
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
      4248 # NATS clustering
      4222 # client connections
    ];
  };
}
