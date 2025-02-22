{
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

    # Hardware stuff
    ./disko.nix
    ./hardware.nix
    ./bootloader.nix

    # Create giodamelio user
    ({pkgs, ...}: {
      users.users.giodamelio = {
        extraGroups = ["wheel" "docker" "sound"];
        isNormalUser = true;
        shell = pkgs.zsh;
        openssh.authorizedKeys.keys = homelab.ssh_keys;
      };
      programs.zsh.enable = true;
    })

    # Basic packages I want on every system
    flake.nixosModules.basic-packages
    flake.nixosModules.basic-packages-desktop
    flake.nixosModules.basic-settings

    # Setup user programs/services
    flake.nixosModules.modern-coreutils-replacements
    flake.nixosModules.programs-atuind
    flake.nixosModules.monitoring
    ./3d-printing.nix

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

    # Software Development tools
    flake.nixosModules.software-development

    # Easy key rebinding
    flake.nixosModules.keyd

    # Connect to our self hosted Headscale instance
    {
      services.tailscale = {
        enable = true;
      };
    }

    ({pkgs, ...}: {
      programs.sway = {
        enable = true;
        wrapperFeatures.gtk = true;
      };
      services.dbus.enable = true;
      xdg.portal = {
        enable = true;
        wlr.enable = true;
        extraPortals = with pkgs; [
          xdg-desktop-portal-gtk
        ];
      };
      services.displayManager = {
        sessionPackages = [
          pkgs.sway
        ];
        ly.enable = true;
      };
      # services.xserver = {
      #   enable = true;
      #   # displayManager.gdm.enable = true;
      #   desktopManager.gnome.enable = true;
      #   videoDrivers = [
      #     "amdgpu"
      #     "modesetting"
      #     "fbdev"
      #   ];
      # };

      # Gaming
      programs.steam = {
        enable = true;
      };
      environment.systemPackages = with pkgs; [
        discord
        # gnomeExtensions.pop-shell
      ];
    })

    (_: {
      virtualisation.docker = {
        enable = true;
      };
      programs.ssh.startAgent = true;

      networking.hostId = "3c510ad9";

      nixpkgs.config.allowUnfree = true;

      system.stateVersion = "25.05";
    })
  ];
}
