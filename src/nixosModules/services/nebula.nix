{lib, ...}: {
  pkgs,
  config,
  ...
}: let
  cfg = config.services.nebula-homelab;
in {
  options.services.nebula-homelab = {
    enable = lib.mkEnableOption "nebula homelab network";

    cert = lib.mkOption {
      description = "Path to file containing Nebula device cert";
      type = lib.types.path;
    };

    key = lib.mkOption {
      description = "Path to file containing Nebula device key";
      type = lib.types.path;
    };

    isLighthouse = lib.mkOption {
      description = "Is this device a Lighthosue";
      type = lib.types.bool;
      default = false;
    };

    isRelay = lib.mkOption {
      description = "Is this device a Relay";
      type = lib.types.bool;
      default = false;
    };
  };

  config = lib.mkIf cfg.enable {
    # Add the Nebula to the system for management
    environment.systemPackages = with pkgs; [nebula qrtool];

    # Setup secrets
    age.secrets.nebula-ca-cert = {
      file = ../../../secrets/nebula-ca.crt.age;
      owner = "nebula-homelab";
      group = "nebula-homelab";
    };

    services.nebula.networks.homelab = lib.mkMerge [
      {
        enable = true;
        ca = config.age.secrets.nebula-ca-cert.path;

        inherit (cfg) cert key isLighthouse isRelay;

        firewall = {
          outbound = [
            {
              host = "any";
              port = "any";
              proto = "any";
            }
          ];
          inbound = [
            {
              host = "any";
              port = "any";
              proto = "any";
            }
          ];
        };
      }

      # Configure lighthouses on non lighthouse nodes
      (lib.mkIf (!cfg.isLighthouse) {
        lighthouses = [
          "10.101.0.1" # zirconium
        ];

        staticHostMap = {
          # zirconium
          "10.101.0.1" = [
            "zirconium.gio.ninja:4242"
          ];
        };
      })
    ];

    # Allow all traffic over the Nebula network
    networking.firewall.trustedInterfaces = ["nebula.homelab"];
  };
}
