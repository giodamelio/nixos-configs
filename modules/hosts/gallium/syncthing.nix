# syncthing on gallium. Daemon + peer firewall ports are host config; the GUI's
# reverse-proxy vhost + consul registration + health check collapse into one
# fleet.services entry. Converted from nix/hosts/gallium/syncthing.nix.
_: {
  den.aspects.gallium.nixos = {
    services.syncthing = {
      enable = true;
      dataDir = "/tank/syncthing";
      guiAddress = "127.0.0.1:8384";
      settings.gui.insecureSkipHostcheck = true;
    };

    # Peer sync (BEP) — proxied GUI comes via fleet.services below.
    networking.firewall.allowedTCPPorts = [22000];
    networking.firewall.allowedUDPPorts = [22000];
  };

  # syncthing-gallium.gio.ninja -> localhost:8384, registered in consul with the
  # health check the old gio.services block carried.
  den.hosts.x86_64-linux.gallium.services.syncthing = {
    endpoint = {
      domain = "syncthing-gallium";
      backend.host = "localhost";
      backend.port = 8384;
    };
    healthcheck.target = "https://syncthing-gallium.gio.ninja/";
  };
}
