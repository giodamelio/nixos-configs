{
  pkgs,
  config,
  ...
}: let
  inherit (pkgs) lib;
  mediaGroup = "media";
in {
  users.groups = {
    ${mediaGroup} = {
      members = [
        "jellyfin"
        "prowlarr"
        "sonarr"
        "radarr"
      ];
    };
  };
  services.jellyfin = {
    enable = true;
    group = mediaGroup;
  };

  users.users.server = {
    extraGroups = [mediaGroup];
  };

  environment.systemPackages = with pkgs; [
    filebot
  ];

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
      "radarr" = {
        host = "localhost";
        port = 7878;
      };
      "sabnzbd" = {
        host = "localhost";
        port = 8888;
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

  services.radarr = {
    enable = true;
    group = mediaGroup;
  };

  services.sabnzbd = let
    stateDir = "/var/lib/sabnzbd";
  in {
    enable = true;
    group = mediaGroup;
    configFile = "${stateDir}/sabnzbd.ini";
  };

  systemd.services.sabnzbd = {
    serviceConfig = {
      Type = lib.mkForce "simple";
      ExecStart = lib.mkForce "${config.services.sabnzbd.package}/bin/sabnzbd -f ${config.services.sabnzbd.configFile} -s 127.0.0.1:8888 --disable-file-log";
    };
  };
}
