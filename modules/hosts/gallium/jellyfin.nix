# jellyfin media stack on gallium: jellyfin + prowlarr/sonarr/radarr/sabnzbd
# (+ an nzbget proxy vhost), shared `media` group, Intel QSV transcoding. Each
# service's vhost + consul registration becomes a fleet.services entry (consul
# address/port derive from the endpoint). Converted from nix/hosts/gallium/jellyfin.nix.
_: let
  mediaGroup = "media";
in {
  den.aspects.gallium.nixos = {
    pkgs,
    config,
    lib,
    ...
  }: {
    users.groups.${mediaGroup} = {
      members = [
        "jellyfin"
        "prowlarr"
        "sonarr"
        "radarr"
      ];
    };

    services.jellyfin = {
      enable = true;
      group = mediaGroup;
      hardwareAcceleration = {
        enable = true;
        type = "qsv";
        device = "/dev/dri/renderD128";
      };
      transcoding = {
        enableHardwareEncoding = true;
      };
    };
    users.users.jellyfin.extraGroups = ["render" "video"];

    users.users.server.extraGroups = [mediaGroup];

    environment.systemPackages = [pkgs.filebot];

    services.prowlarr.enable = true;
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

    systemd.services.sabnzbd.serviceConfig = {
      Type = lib.mkForce "simple";
      ExecStart = lib.mkForce "${config.services.sabnzbd.package}/bin/sabnzbd -f ${config.services.sabnzbd.configFile} -s 127.0.0.1:8888 --disable-file-log";
    };
  };

  den.hosts.x86_64-linux.gallium.services = {
    jellyfin = {
      endpoint = {
        domain = "jellyfin";
        backend.host = "localhost";
        backend.port = 8096;
      };
      healthcheck.target = "https://jellyfin.gio.ninja/health";
    };
    prowlarr = {
      endpoint = {
        domain = "prowlarr";
        backend.host = "localhost";
        backend.port = 9696;
      };
      healthcheck.target = "https://prowlarr.gio.ninja/ping";
    };
    sonarr = {
      endpoint = {
        domain = "sonarr";
        backend.host = "localhost";
        backend.port = 8989;
      };
      healthcheck.target = "https://sonarr.gio.ninja/ping";
    };
    radarr = {
      endpoint = {
        domain = "radarr";
        backend.host = "localhost";
        backend.port = 7878;
      };
      healthcheck.target = "https://radarr.gio.ninja/ping";
    };
    sabnzbd = {
      endpoint = {
        domain = "sabnzbd";
        backend.host = "localhost";
        backend.port = 8888;
      };
      healthcheck.target = "https://sabnzbd.gio.ninja/";
    };
    # nzbget had a proxy vhost but no consul registration in Blueprint.
    nzbget = {
      endpoint = {
        domain = "nzbget";
        backend.host = "localhost";
        backend.port = 6789;
      };
      consul.enable = false;
    };
  };
}
