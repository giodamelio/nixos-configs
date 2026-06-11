# rhodium — Raspberry Pi 4 SD-image host. Fully den-native: the shared base
# (required/deployed-apps/reverse-proxy, basic-packages, basic-settings) now
# arrives via den.default (see modules/den.nix), and the aspect bodies close
# over `inputs` from their file scope — so this host needs no `instantiate`
# specialArgs bridge and no inputs.self.nixosModules.* imports. den's default
# nixosSystem builds it.
{
  inputs,
  den,
  ...
}: let
  homelab = builtins.fromTOML (builtins.readFile ../../../homelab.toml);
in {
  # Declare the host (platform comes from the attr path) with its server user.
  # The aspects named `rhodium` and `server` attach by convention; the base
  # bundle arrives via den.default.
  den.hosts.aarch64-linux.rhodium = {
    role = "server";
    # Plain system account, no Home-Manager (empty classes) — matches the
    # original inline users.users.server (which had no HM).
    users.server.classes = [];
  };

  den.aspects.rhodium.nixos = {
    modulesPath,
    pkgs,
    lib,
    ...
  }: {
    imports = [
      inputs.nixos-hardware.nixosModules.raspberry-pi-4
      "${modulesPath}/installer/sd-card/sd-image.nix"

      # Hardware (was nix/hosts/rhodium/hardware.nix).
      {
        networking.hostName = "rhodium";
        sdImage.compressImage = false;
        console.enable = true;
        boot.kernelParams = [
          "console=ttyAMA0,115200n8"
          "loglevel=7"
          "earlycon"
        ];
        hardware.enableRedistributableFirmware = lib.mkDefault true;
        # No ZFS on this host
        boot.supportedFilesystems.zfs = lib.mkForce false;
        # Allow missing modules — the RPi kernel doesn't have dw-hdmi
        # which vc4 depends on, but it's not needed at boot
        boot.initrd.allowMissingModules = true;
      }

      # Temporary DHCP networking until static IP is confirmed working.
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

      # Raspberry Pi utilities.
      {
        environment.systemPackages = with pkgs; [
          libraspberrypi
          raspberrypi-eeprom
        ];
      }
    ];

    nixpkgs.config.allowUnfree = true;
    system.stateVersion = "25.11";
  };

  # rhodium's server user, modeled as a den user entity (replaces the old inline
  # users.users.server block). define-user + user-shell provide isNormalUser,
  # home, zsh shell and programs.zsh; the `user` class carries the wheel group
  # and SSH keys (forwarded to users.users.server by the os-user battery).
  # Passwordless sudo comes from basic-settings (via den.default).
  den.aspects.server = {
    includes = [
      den.batteries.define-user
      (den.batteries.user-shell "zsh")
    ];
    user = {
      extraGroups = ["wheel"];
      openssh.authorizedKeys.keys = homelab.ssh_keys;
    };
  };
}
