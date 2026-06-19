# gallium owns nats-ws.gio.ninja (DNS points the websocket GUI here). The NATS
# daemon itself comes from the shared den.aspects.nats; this only adds the vhost
# as a fleet.services endpoint (no consul registration, as before).
_: {
  den.hosts.x86_64-linux.gallium.services.nats-ws = {
    endpoint = {
      domain = "nats-ws";
      backend.host = "localhost";
      backend.port = 9222;
    };
    consul.enable = false;
  };
}
