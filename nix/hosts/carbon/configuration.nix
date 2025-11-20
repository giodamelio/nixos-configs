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
    ./nats.nix # Message Broker
    ./grist.nix # Spreadsheets on steroids

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

    # Setup CoreDNS server with fixed list of records
    (
      {
        pkgs,
        lib,
        ...
      }: let
        a_records = homelab.dns."gio.ninja".a;
        cname_records = homelab.dns."gio.ninja".cname;
        zoneFile = pkgs.writeText "gio.ninja.zone" ''
          $ORIGIN gio.ninja.
          @ IN SOA @ @ 1 1h 15m 30d 2h
            IN NS @

          ${lib.pipe a_records [
            (builtins.mapAttrs (ip: hosts: builtins.map (host: "${host} IN A ${ip}") hosts))
            builtins.attrValues
            builtins.concatLists
            (builtins.concatStringsSep "\n")
          ]}

          ${lib.pipe cname_records [
            (builtins.mapAttrs (ip: hosts: builtins.map (host: "${host} IN CNAME ${ip}") hosts))
            builtins.attrValues
            builtins.concatLists
            (builtins.concatStringsSep "\n")
          ]}
        '';
      in {
        # Disable systemd-resolved dns server
        services.resolved = {
          extraConfig = ''
            DNSStubListener=no
          '';
        };

        services.coredns = {
          enable = true;
          config = ''
            gio.ninja:53 {
                file ${zoneFile} {
                  fallthrough
                }
                forward . 1.1.1.1 1.0.0.1
                errors
                cache
            }

            lan:53 {
              forward . 10.0.0.1
              errors
              cache
            }

            .:53 {
                forward . 1.1.1.1 1.0.0.1
                errors
                cache
            }
          '';
        };

        # Open the firewall
        networking.firewall = {
          allowedTCPPorts = [
            53
          ];
          allowedUDPPorts = [
            53
          ];
        };
      }
    )

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
