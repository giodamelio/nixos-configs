{
  services.immich = {
    enable = true;
    mediaLocation = "/tank/immich";

    database = {
      enable = true;
      createDB = true;
    };
  };

  services.gio.reverse-proxy = {
    enable = true;
    virtualHosts = {
      "immich" = {
        host = "localhost";
        port = 2283;
      };
    };
  };
}
