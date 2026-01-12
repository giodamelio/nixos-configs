{flake, ...}: let
  homelab = builtins.fromTOML (builtins.readFile ../../../homelab.toml);
in {
  imports = [
    # Setup hardware
    ./disko.nix
    ./hardware.nix

    flake.nixosModules.basic-packages
    flake.nixosModules.basic-settings
    flake.nixosModules.credential
    flake.nixosModules.onepassword
    flake.nixosModules.lil-scripts
    flake.nixosModules.reverse-proxy
    flake.nixosModules.send-metrics
    flake.nixosModules.zfs-backup
    flake.nixosModules.consul
    flake.nixosModules.nats
    flake.nixosModules.lan-dns

    # TODO: setup auto backup
    ./postgresql.nix # DB to be shared across applications
    ./gatus.nix # Status Page
    ./pocket-id.nix # OIDC Server
    ./prometheus.nix # Metrics Server
    ./loki.nix # Logs Server
    ./grafana.nix # Metrics/Logs UI
    ./mealie.nix # Recipe Manager
    ./homer.nix # Homepage to list all the services
    ./restate.nix # Distributed application platform
    ./windmill.nix # Workflow Engine
    ./rustmailer.nix # Email middleware
    ./grist.nix # Spreadsheets on steroids
    ./hammond.nix # Random automations for my life
    ./home-assistant.nix # Home Automation
    ./openbao.nix # Secret Automation

    # Configure Networking with Systemd Networkd
    {
      # Use Networkd
      networking = {
        useNetworkd = true;
        useDHCP = false;
        interfaces."eno1".useDHCP = true;

        firewall = {
          enable = true;
          allowPing = true;
        };
        nftables = {
          enable = true;
        };
      };

      systemd.network = {
        enable = true;
      };
    }

    {
      gio.zfs_backup = {
        enable = true;
        datasets = [
          "tank"
          "tank/home"
          "tank/nix"
          "tank/reserve"
          "tank/root"
        ];
      };
    }

    # Host specific console configs
    {
      services.consul = {
        webUi = true;
        interface.bind = "eno1";
      };

      # Make it read only by only allowing GET requests though
      services.gio.reverse-proxy = {
        enable = true;
        virtualHosts = {
          "consul" = {
            host = "localhost";
            port = 8500;
            reverseProxy = false;
            extraConfig = ''
              @get_requests {
                method GET
              }

              reverse_proxy @get_requests localhost:8500

              # Respond with 405 for all other methods
              @not_get_requests {
                  not {
                      method GET
                  }
              }

              respond @not_get_requests 405 {
                  body "Method Not Allowed"
              }
            '';
          };
        };
      };
    }

    # Create server user
    (
      {pkgs, ...}: {
        users.users.server = {
          extraGroups = ["wheel"];
          isNormalUser = true;
          shell = pkgs.zsh;
          openssh.authorizedKeys.keys = homelab.ssh_keys;
        };
        security.sudo.wheelNeedsPassword = false;
        programs.zsh.enable = true;
      }
    )
  ];

  nixpkgs.config.allowUnfree = true;
  system.stateVersion = "25.11";
}
