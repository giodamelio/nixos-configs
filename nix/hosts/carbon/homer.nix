{pkgs, ...}: let
  dashboardLogo = name: "https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons/png/${name}.png";
  settings = {
    title = "Gio's Homelab";
    subtitle = "";

    services = [
      {
        name = "Services";
        icon = "";
        items = [
          {
            name = "PocketID";
            subtitle = "Centralized Auth";
            url = "https://login.gio.ninja";
            logo = dashboardLogo "pocket-id";
          }
          {
            name = "Mealie";
            subtitle = "Recipe Manager";
            url = "https://mealie.gio.ninja";
            logo = dashboardLogo "mealie";
          }
          {
            name = "Immich";
            subtitle = "Photo/Video Sync";
            url = "https://immich.gio.ninja";
            logo = dashboardLogo "immich";
          }
          {
            name = "Windmill";
            subtitle = "Workflow engine for automations";
            url = "https://windmill.gio.ninja";
            logo = dashboardLogo "windmill";
          }
          {
            name = "Gatus";
            subtitle = "Status Page";
            url = "https://gatus.gio.ninja";
            logo = "https://gatus.gio.ninja/logo-512x512.png";
          }
          {
            name = "Home Assistant";
            subtitle = "Home automation";
            url = "https://home-assistant.gio.ninja";
            logo = dashboardLogo "home-assistant";
          }
        ];
      }
      {
        name = "Media";
        icon = "";
        items = [
          {
            name = "Jellyfin";
            subtitle = "Media Server";
            url = "https://jellyfin.gio.ninja";
            logo = dashboardLogo "jellyfin";
          }
          {
            name = "SABnzbd";
            subtitle = "Usenet Binary Newsreader";
            url = "https://sabnzbd.gio.ninja";
            logo = dashboardLogo "sabnzbd";
          }
          {
            name = "Prowlarr";
            subtitle = "Index Manager";
            url = "https://prowlarr.gio.ninja";
            logo = dashboardLogo "prowlarr";
          }
          {
            name = "Sonarr";
            subtitle = "TV Show Tracker";
            url = "https://sonarr.gio.ninja";
            logo = dashboardLogo "sonarr";
          }
          {
            name = "Radarr";
            subtitle = "Movie Tracker";
            url = "https://radarr.gio.ninja";
            logo = dashboardLogo "radarr";
          }
        ];
      }
    ];

    links = [
      {
        name = "Admin";
        icon = "";
        url = "#admin";
      }
    ];
  };
  adminSettings = {
    title = "Gio's Homelab";
    subtitle = "Admin Tools";

    services = [
      {
        name = "Admin";
        icon = "";
        items = [
          {
            name = "Gatus";
            subtitle = "Status Page";
            url = "https://gatus.gio.ninja";
            logo = "https://gatus.gio.ninja/logo-512x512.png";
          }
          {
            name = "Unifi Controller";
            subtitle = "LAN Admin UI";
            url = "https://unifi.gio.ninja:8443";
            logo = dashboardLogo "unifi";
          }
          {
            name = "Grafana";
            subtitle = "Metrics/Logs Dashboard";
            url = "https://grafana.gio.ninja";
            logo = dashboardLogo "grafana";
          }
          {
            name = "Prometheus";
            subtitle = "Metrics Collector";
            url = "https://prometheus.gio.ninja";
            logo = dashboardLogo "prometheus";
          }
          {
            name = "Rustmailer";
            subtitle = "Email middleware";
            url = "https://rustmailer.gio.ninja";
            logo = "https://rustmailer.com/images/logo.svg";
          }
        ];
      }
    ];

    links = [
      {
        name = "Home";
        icon = "";
        url = "/";
      }
    ];
  };
in {
  services.caddy = let
    settingsFormat = pkgs.formats.yaml {};
    configFile = settingsFormat.generate "homer-config.yml" settings;
    adminConfigFile = settingsFormat.generate "admin.yml" adminSettings;
  in {
    virtualHosts."https://homer.gio.ninja".extraConfig = ''
      tls {
        dns cloudflare {file.{$CLOUDFLARE_API_TOKEN_FILE}}
        resolvers 1.1.1.1
      }
      root * ${pkgs.homer}
      file_server
      handle_path /assets/config.yml {
        root * ${configFile}
        file_server
      }
      handle_path /assets/admin.yml {
        root * ${adminConfigFile}
        file_server
      }
    '';
  };

  gio.services.homer.consul = {
    name = "homer";
    address = "homer.gio.ninja";
    port = 443;
    checks = [
      {
        http = "https://homer.gio.ninja";
        interval = "60s";
      }
    ];
  };
}
