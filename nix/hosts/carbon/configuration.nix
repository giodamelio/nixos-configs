{flake, ...}: let
  homelab = builtins.fromTOML (builtins.readFile ../../../homelab.toml);
in {
  imports = [
    # Setup hardware
    ./disko.nix
    ./hardware.nix

    flake.nixosModules.basic-packages
    flake.nixosModules.basic-settings
    flake.nixosModules.onepassword
    flake.nixosModules.lil-scripts

    # Dynamic DNS with Cloudflare
    (
      _: {
        services.cloudflare-dyndns = {
          enable = true;
          # We are overriding the loading to use encrypted credentials
          apiTokenFile = "/noop";
          domains = ["home.gio.ninja"];
          proxied = false;
        };

        # Load the Cloudflare token
        systemd.services.cloudflare-dyndns.serviceConfig = {
          LoadCredential = null;
          LoadCredentialEncrypted = "apiToken:/var/lib/credstore/apiToken";
        };
      }
    )

    # Setup Wireguard VPNs
    (
      {pkgs, ...}: let
        wireguardPort = 51820;
      in {
        environment.systemPackages = with pkgs; [
          wireguard-tools
        ];

        # Allow forwarding of traffic
        boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

        # Use Networkd
        networking = {
          useNetworkd = true;
          useDHCP = false;
          interfaces."eno1".useDHCP = true;

          firewall = {
            enable = true;
            allowPing = true;
            # TODO: Might need this later
            # allowedUDPPorts = [
            #   5353 # mdns
            # ];
          };
          nftables = {
            enable = true;
          };
        };

        systemd.network = {
          enable = true;

          netdevs."50-wg0" = {
            netdevConfig = {
              Kind = "wireguard";
              Name = "wg0";
            };

            wireguardConfig = {
              PrivateKey = "@wireguard-wg0-private-key";
              ListenPort = wireguardPort;
            };

            wireguardPeers = [
              {
                PublicKey = "GOPX3KoKUxmtIqdI0qWxvv3aCv8Qa/rug/9V6vWXNxU=";
                AllowedIPs = ["10.10.10.2/32"];
              }
            ];
          };

          networks."50-wg0" = {
            matchConfig.Name = "wg0";
            address = ["10.10.10.1/24"];
            networkConfig = {
              IPv4Forwarding = true;
            };
          };
        };

        # Load wireguard private key into systemd-networkd
        # This allows us to load the credential via systemd.netdev directly
        # See systemd.netdev(5), search for "PrivateKey="
        systemd.services."systemd-networkd" = {
          serviceConfig = {
            LoadCredentialEncrypted = [
              "wireguard-wg0-private-key:/var/lib/credstore/wireguard-wg0-private-key"
            ];
          };
        };

        networking.firewall = {
          allowedUDPPorts = [wireguardPort];
          trustedInterfaces = ["wg0"];
        };

        networking.nat = {
          enable = true;
          externalInterface = "eno1";
          internalInterfaces = ["wg0"];
        };
      }
    )

    # Setup CoreDNS server with fixed list of records
    (
      {
        pkgs,
        lib,
        ...
      }: let
        records = {
          "10.0.128.125" = [
            "cadmium"
          ];
          "10.0.128.210" = [
            "carbon"
          ];
        };
        zoneFile = pkgs.writeText "gio.ninja.zone" ''
          $ORIGIN gio.ninja.
          @ IN SOA @ @ 1 1h 15m 30d 2h
            IN NS @

          ${lib.pipe records [
            (builtins.mapAttrs (ip: hosts: builtins.map (host: "${host} IN A ${ip}") hosts))
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
  system.stateVersion = "25.05";
}
