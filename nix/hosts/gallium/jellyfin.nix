_: let
  mediaGroup = "media";
in {
  users.groups = {
    ${mediaGroup} = {
      members = [
        "jellyfin"
        "nzbget"
        "prowlarr"
        "sonarr"
      ];
    };
  };
  services.jellyfin = {
    enable = true;
    group = mediaGroup;
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
    # TODO: allow setting group
    # group = mediaGroup;
  };

  services.sonarr = {
    enable = true;
    group = mediaGroup;
  };

  services.nzbget = {
    enable = true;
    group = mediaGroup;
    settings = {};
  };
}
