{
  pkgs,
  inputs,
  flake,
  ...
}: let
  homelab = builtins.fromTOML (builtins.readFile ../../../homelab.toml);
in {
  imports = [
    inputs.colmena.nixosModules.deploymentOptions
    inputs.home-manager.nixosModules.home-manager
    inputs.ragenix.nixosModules.default

    ./disko.nix
    ./hardware.nix
    ./prometheus.nix

    flake.nixosModules.basic-packages
    flake.nixosModules.basic-settings
    flake.nixosModules.monitoring

    # Create server user
    ({pkgs, ...}: {
      users.users.server = {
        extraGroups = ["wheel" "docker" "sound"];
        isNormalUser = true;
        shell = pkgs.zsh;
        openssh.authorizedKeys.keys = homelab.ssh_keys;
      };
      security.sudo.wheelNeedsPassword = false;
      programs.zsh.enable = true;
    })

    # Autosnapshot ZFS and send to NAS
    flake.nixosModules.zfs-backup
    (_: {
      gio.services.zfs_backup = {
        enable = true;
        syncToGallium = true;
        datasets = [
          "tank/home"
          "tank/nix"
          "tank/root"
        ];
      };
    })

    # Connect to our self hosted Headscale instance
    ({
      services.tailscale = {
        enable = true;
      };
    })

    # Simple Status Page
    ({
      services.gatus = {
        enable = true;
        openFirewall = true;
        settings = {
          metrics = true;
          storage = {
            type = "sqlite";
            path = "/var/lib/gatus/data.db";
          };
          endpoints = let
            mkPingEndpoint = name: host: {
              inherit name;
              group = "Hosts";
              url = "icmp://${host}";
              interval = "5m";
              conditions = [
                "[CONNECTED] == true"
              ];
            };
          in [
            {
              name = "Headscale";
              url = "https://headscale.gio.ninja/health";
              interval = "5m";
              conditions = [
                "[STATUS] == 200"
                "[BODY].status == pass"
                "[RESPONSE_TIME] < 300"
              ];
            }
            {
              name = "Prometheus";
              url = "http://manganese.h.gio.ninja:9090/-/healthy";
              interval = "5m";
              conditions = [
                "[STATUS] == 200"
                "[RESPONSE_TIME] < 300"
              ];
            }
            {
              name = "Google";
              url = "https://google.com";
              interval = "10m";
              conditions = [
                "[STATUS] == 200"
              ];
            }
            (mkPingEndpoint "cadmium" "cadmium.h.gio.ninja")
            (mkPingEndpoint "lithium1" "lithium1.h.gio.ninja")
            (mkPingEndpoint "manganese" "manganese.h.gio.ninja")
          ];
        };
      };

      # Allow Gatus to send ICMP traffic
      systemd.services.gatus = {
        serviceConfig = {
          CapabilityBoundingSet = "CAP_NET_RAW";
          AmbientCapabilities = "CAP_NET_RAW";
        };
      };
    })
  ];

  # ZFS snapshot browsing
  environment.systemPackages = [pkgs.httm];

  system.stateVersion = "25.05";
}
