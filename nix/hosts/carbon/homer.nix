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
}
