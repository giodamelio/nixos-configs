# home-assistant — home automation (home-assistant.gio.ninja) + zwave-js on the
# HubZ serial controller. The zwave-js secret moves to a fleet.secrets credential.
# The upstream module hardcodes the credential name `secrets.json` (ExecStartPre
# merges %d/secrets.json), so the fleet credential MUST be named secrets.json.
_: {
  den.aspects.carbon.nixos = {lib, ...}: {
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
        "zwave_js"
        "zha"
        "usb"
        "google_translate"
        "default_config"
        "analytics"
        "met"
        "radio_browser"
        "esphome"
        "matter"
      ];
    };

    services.zwave-js = {
      enable = true;
      serialPort = "/dev/serial/by-id/usb-Silicon_Labs_HubZ_Smart_Home_Controller_515015BA-if00-port0";
      secretsConfigFile = "/run/credentials/zwave-js.service/secrets.json";
      port = 3333;
    };
    # The module's own LoadCredential (secrets.json:secretsConfigFile) is cleared
    # so the fleet.secrets credential dropin is the sole source of %d/secrets.json.
    systemd.services.zwave-js.serviceConfig.LoadCredential = lib.mkForce [];

    services.matter-server = {
      enable = true;
      # Bind to the IOT VLAN so Matter discovery (link-local + mDNS) is on the
      # same L2 as the devices; HA reaches it over localhost.
      extraArgs.primary-interface = "iot0";
    };

    # Scoped to iot0; carbon's input firewall would otherwise drop these.
    networking.firewall.interfaces.iot0 = {
      # mDNS discovery (5353) + Matter operational/commissioning (5540).
      allowedUDPPorts = [5353 5540];
      # Raw :8123 for commissioning from a phone on the IOT VLAN (HA is normally
      # behind Caddy on :443). Safe to remove once commissioning is done.
      allowedTCPPorts = [8123];
    };
  };

  den.hosts.x86_64-linux.carbon.services.home-assistant = {
    endpoint = {
      domain = "home-assistant";
      backend.host = "localhost";
      backend.port = 8123;
    };
    healthcheck.target = "https://home-assistant.gio.ninja/";
  };

  fleet.secrets.zwavejs-secrets = {
    origin = "carbon";
    use.carbon.services.zwave-js = {
      type = "credential";
      credential.name = "secrets.json";
    };
  };
}
