_: {
  services.jellyfin = {
    enable = true;
  };

  services.gio.reverse-proxy = {
    enable = true;
    virtualHosts = {
      "jellyfin" = {
        host = "localhost";
        port = 8096;
      };
    };
  };
}
