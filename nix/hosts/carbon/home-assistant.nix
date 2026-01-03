{pkgs, ...}: let
  inherit (pkgs) lib;
in {
  services.home-assistant = {
    enable = true;
    config = {
      homeassistant = {
        name = "Home";
        unit_system = "us_customary";
        time_zone = "America/Los_Angeles";
        # Seattle, not my house
        latitude = "47.608013";
        longitude = "-122.335167";
      };

      http = {
        use_x_forwarded_for = true;
        trusted_proxies = ["127.0.0.1" "::1"];
      };

      default_config = {};

      zha = {
        # usb_path = "/dev/serial/by-id/usb-Silicon_Labs_HubZ_Smart_Home_Controller_515015BA-if01-port0";
        database_path = "/var/lib/hass/zigbee.db";
      };

      automation = [
        {
          alias = "Turn off Grow Light";
          description = "";
          trigger = {
            platform = "time";
            at = "15:00:00";
          };
          condition = [];
          action = {
            type = "turn_off";
            device_id = "6a23d17b71a7c4437088b8e2d6c429ae";
            entity_id = "a531393bef66e2769bb691086c8c5c35";
            domain = "switch";
          };
          mode = "single";
        }
        {
          alias = "Turn on Grow Light";
          description = "";
          trigger = {
            platform = "time";
            at = "10:00:00";
          };
          condition = [];
          action = {
            type = "turn_on";
            device_id = "6a23d17b71a7c4437088b8e2d6c429ae";
            entity_id = "a531393bef66e2769bb691086c8c5c35";
            domain = "switch";
          };
          mode = "single";
        }
      ];
    };
    extraComponents = [
      # Z-Wave
      "zwave_js"

      # Hardware discovery (needed for auto-detection)
      "zha"
      "usb"

      #TTS - this provides gtts
      "google_translate"

      # Basic functionality
      "default_config"
      "analytics"
      "met"
      "radio_browser"
      "esphome"
    ];
  };

  services.zwave-js = {
    enable = true;
    serialPort = "/dev/serial/by-id/usb-Silicon_Labs_HubZ_Smart_Home_Controller_515015BA-if00-port0";
    secretsConfigFile = "/run/credentials/zwave-js.service/zwavejs-secrets.json";
    port = 3333;
  };

  systemd.services.zwave-js.serviceConfig = {
    LoadCredential = lib.mkForce [];
    LoadCredentialEncrypted = ["secrets.json"];
  };

  gio.credentials = {
    enable = true;
    services = {
      "zwave-js" = {
        loadCredentialEncrypted = ["zwavejs-secrets.json"];
      };
    };
  };

  services.gio.reverse-proxy = {
    enable = true;
    virtualHosts = {
      "home-assistant" = {
        host = "localhost";
        port = 8123;
      };
    };
  };
}
