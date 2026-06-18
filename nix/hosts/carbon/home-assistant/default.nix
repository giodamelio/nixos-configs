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

        packages.bedroom_ac_schedule = "!include ${./bedroom-ac-schedule.yaml}";
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
      "matter"
    ];
  };

  services.matter-server = {
    enable = true;
    # Bind to the isolated IOT VLAN so Matter device discovery (link-local +
    # mDNS) happens on the same L2 as the devices. HA reaches matter-server
    # over localhost, so no cross-VLAN path is involved.
    extraArgs.primary-interface = "iot0";
  };

  # Firewall holes scoped to the IOT VLAN only. carbon's input firewall would
  # otherwise drop inbound traffic on iot0.
  networking.firewall.interfaces.iot0 = {
    # matter-server <-> device traffic: mDNS discovery (5353) and the Matter
    # operational/commissioning protocol (5540). The HA<->matter-server API on
    # 5580 stays localhost-only and is intentionally NOT exposed here.
    allowedUDPPorts = [5353 5540];
    # Home Assistant's direct port, for commissioning the AC from a phone on the
    # IOT VLAN. HA still lives behind Caddy (:443 on eno1) for normal use; this
    # only exposes the raw :8123 to the IOT network. Safe to remove once
    # commissioning is done.
    allowedTCPPorts = [8123];
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

  gio.services.home-assistant.consul = {
    name = "home-assistant";
    address = "home-assistant.gio.ninja";
    port = 443;
    checks = [
      {
        http = "https://home-assistant.gio.ninja/";
        interval = "60s";
      }
    ];
  };
}
