# rhodium — Raspberry Pi 4 SD-image host. First pilot migrated from Blueprint to
# den. For now it reuses the existing Blueprint modules via inputs.self.nixosModules.*
# rather than re-expressing them as den aspects; that conversion comes later.
{inputs, ...}: let
  homelab = builtins.fromTOML (builtins.readFile ../../../homelab.toml);

  system = "aarch64-linux";

  # Reproduce Blueprint's per-system package view (perSystem.<input> = that
  # input's packages for this system); basic-packages.nix consumes
  # perSystem.neovim-configs and perSystem.giopkgs. Lazy: only forced entries
  # evaluate.
  perSystem =
    builtins.mapAttrs
    (_name: input: (input.legacyPackages.${system} or {}) // (input.packages.${system} or {}))
    inputs;
in {
  # Declare the host (platform comes from the attr path). The aspect named
  # `rhodium` attaches to it by convention.
  #
  # TEMPORARY SCAFFOLDING — remove this whole `instantiate` override once the
  # reused Blueprint modules below are converted to den-native aspects; rhodium
  # then falls back to den's default `nixosSystem`. Each specialArg drops as its
  # consumer goes away: `flake`/`self` when required→deployed-apps→reverse-proxy
  # stop referencing `flake` in `imports`; `perSystem` when basic-packages.nix
  # does; `hostName` when nothing reads it.
  #
  # Bridge tax: those modules reference `flake`/`perSystem` — `flake` inside
  # their `imports`, so these must be specialArgs (external), not `_module.args`
  # (which would recurse). den's default instantiate passes no specialArgs, so
  # override it to supply the same args Blueprint's nixosSystem does — exactly
  # the use the option's own docs call out.
  den.hosts.aarch64-linux.rhodium.instantiate = args:
    inputs.nixpkgs.lib.nixosSystem (args
      // {
        specialArgs =
          (args.specialArgs or {})
          // {
            inherit inputs perSystem;
            flake = inputs.self;
            hostName = "rhodium";
            self = throw "self was renamed to flake";
          };
      });

  den.aspects.rhodium.nixos = {
    modulesPath,
    pkgs,
    lib,
    ...
  }: {
    imports = [
      inputs.nixos-hardware.nixosModules.raspberry-pi-4
      "${modulesPath}/installer/sd-card/sd-image.nix"

      # Existing Blueprint modules, reused as-is during migration.
      inputs.self.nixosModules.required
      inputs.self.nixosModules.basic-packages
      inputs.self.nixosModules.basic-settings

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

      # Server user.
      # REMIND-ME-TO: Model rhodium's server user as a den user entity
      #   (den.hosts.aarch64-linux.rhodium.users.server + define-user/primary-user)
      #   instead of this inline users.users block. date_passed=2026-09-01
      {
        users.users.server = {
          extraGroups = ["wheel"];
          isNormalUser = true;
          shell = pkgs.zsh;
          openssh.authorizedKeys.keys = homelab.ssh_keys;
        };
        security.sudo.wheelNeedsPassword = false;
        programs.zsh.enable = true;
      }
    ];

    nixpkgs.config.allowUnfree = true;
    system.stateVersion = "25.11";
  };
}
