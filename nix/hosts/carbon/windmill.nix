{
  flake,
  pkgs,
  config,
  ...
}: let
  inherit (flake.packages.${pkgs.stdenv.system}) windmill;
in {
  services.windmill = {
    enable = true;
    package = windmill;
    baseUrl = "https://windmill.gio.ninja";
    database = {
      createLocally = true;
    };
  };

  services.gio.reverse-proxy = {
    enable = true;
    virtualHosts = {
      "windmill" = {
        host = "localhost";
        port = config.services.windmill.serverPort;
      };
    };
  };
}
