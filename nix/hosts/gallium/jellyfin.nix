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
      "nzbget" = {
        host = "localhost";
        port = 6789;
      };
      "prowlarr" = {
        host = "localhost";
        port = 9696;
      };
      "sonarr" = {
        host = "localhost";
        port = 8989;
      };
    };
  };

  services.prowlarr = {
    enable = true;
  };

  services.sonarr = {
    enable = true;
  };

  services.nzbget = {
    enable = true;
    settings = {};
  };
}
