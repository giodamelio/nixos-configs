_: {
  services.syncthing = {
    enable = true;
    dataDir = "/tank/syncthing";
    guiAddress = "127.0.0.1:8384";
    settings.gui = {
      insecureSkipHostcheck = true;
    };
  };

  services.gio.reverse-proxy = {
    enable = true;
    virtualHosts = {
      "syncthing-gallium" = {
        host = "localhost";
        port = 8384;
      };
    };
  };

  # Allow local connections from peers
  networking.firewall.allowedTCPPorts = [
    22000
  ];
  networking.firewall.allowedUDPPorts = [
    22000
  ];
}
