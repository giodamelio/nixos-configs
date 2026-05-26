{
  inputs,
  flake,
  perSystem,
  ...
}: let
  homelab = builtins.fromTOML (builtins.readFile ../../../homelab.toml);
in {
  imports = [
    inputs.home-manager.nixosModules.home-manager

    # Hardware and boot
    ./hardware.nix

    # Core system modules
    flake.nixosModules.wifi
    flake.nixosModules.nh
    flake.nixosModules.optnix
    flake.nixosModules.required
    flake.nixosModules.basic-packages
    flake.nixosModules.basic-packages-desktop
    flake.nixosModules.basic-settings
    flake.nixosModules.onepassword
    flake.nixosModules.fonts
    flake.nixosModules.remote-builder-user
    flake.nixosModules.attic-client
    flake.nixosModules.pipewire

    # Create giodamelio user
    (
      {pkgs, ...}: {
        users.users.giodamelio = {
          extraGroups = [
            "wheel"
            "networkmanager"
            "audio"
          ];
          isNormalUser = true;
          shell = pkgs.zsh;
          openssh.authorizedKeys.keys = homelab.ssh_keys;
        };
        programs.zsh.enable = true;
      }
    )

    # Niri compositor
    ./niri.nix

    # Remote Wayland session to cadmium (WIP)
    ./remote-wayland-cadmium.nix

    # Battery and power management
    flake.nixosModules.battery-optimization

    # KDE Connect firewall ports (auto-enabled when any HM user enables kdeconnect)
    flake.nixosModules.kde-connect

    # Development tools
    flake.nixosModules.software-development

    # GVFS for Nautilus network share browsing (SMB, etc.)
    {services.gvfs.enable = true;}

    # Random software
    {
      environment.systemPackages = [
        perSystem.giopkgs.emdash
      ];
    }

    (_: {
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      networking.hostId = "98a5ee60";

      nixpkgs.config.allowUnfree = true;

      system.stateVersion = "26.05";
    })
  ];
}
