{
  inputs,
  flake,
  modulesPath,
  ...
}: let
  homelab = builtins.fromTOML (builtins.readFile ../../../homelab.toml);
in {
  imports = [
    inputs.nixos-hardware.nixosModules.raspberry-pi-4

    # "${inputs.nixpkgs}/nixos/modules/installer/sd-card/sd-image.nix"
    "${modulesPath}/installer/sd-card/sd-image.nix"
    ./hardware.nix
    # ./disko.nix

    flake.nixosModules.basic-packages
    flake.nixosModules.basic-settings
    # flake.nixosModules.credential
    # flake.nixosModules.onepassword
    # flake.nixosModules.lil-scripts
    # flake.nixosModules.homelab
    # flake.nixosModules.lan-dns
    # flake.nixosModules.consul
    # flake.nixosModules.comin

    # Temporary DHCP networking until static IP is confirmed working
    {
      networking = {
        useNetworkd = true;
        useDHCP = false;
        firewall = {
          enable = true;
          allowPing = true;
        };
        nftables.enable = true;
      };

      systemd.network = {
        enable = true;
        networks."10-lan" = {
          matchConfig.Name = "eth0";
          networkConfig.DHCP = "yes";
          linkConfig.RequiredForOnline = "routable";
        };
      };
    }

    # Raspberry Pi utilities
    ({pkgs, ...}: {
      environment.systemPackages = with pkgs; [
        libraspberrypi
        raspberrypi-eeprom
      ];
    })

    # Host specific Consul configs
    # {
    #   services.consul = {
    #     interface.bind = "eth0";
    #   };
    # }

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
