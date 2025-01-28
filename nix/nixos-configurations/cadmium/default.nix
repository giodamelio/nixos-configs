{
  inputs,
  self,
  homelab,
  ezModules,
  ...
}: {
  imports = [
    inputs.colmena.nixosModules.deploymentOptions
    inputs.home-manager.nixosModules.home-manager
    inputs.ragenix.nixosModules.default

    # Hardware stuff
    ./disko.nix
    ./hardware.nix
    ./bootloader.nix

    # Create giodamelio user
    ({ pkgs, ... }: {
      users.users.giodamelio = {
        extraGroups = ["wheel" "docker" "sound"];
        isNormalUser = true;
        shell = pkgs.zsh;
        openssh.authorizedKeys.keys = homelab.ssh_keys;
      };
      programs.zsh.enable = true;

      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
    })

    # Basic packages I want on every system
    ezModules.basic-packages
    ezModules.basic-packages-desktop
    ezModules.basic-settings

    # Setup user programs/services
    ezModules.modern-coreutils-replacements
    ezModules.programs-atuind

    # Autosnapshot ZFS and send to NAS
    ezModules.zfs-backup
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
    ezModules.software-development

    # Easy key rebinding
    ezModules.keyd

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
    })
  ];
}
