{
  inputs,
  flake,
  ...
}: let
  homelab = builtins.fromTOML (builtins.readFile ../../../homelab.toml);
in {
  imports = [
    inputs.home-manager.nixosModules.home-manager

    # Hardware and boot
    ./hardware.nix

    # Core system modules
    flake.nixosModules.lix
    flake.nixosModules.wifi
    flake.nixosModules.nh
    flake.nixosModules.optnix
    flake.nixosModules.basic-packages
    flake.nixosModules.basic-settings
    flake.nixosModules.onepassword
    flake.nixosModules.fonts
    flake.nixosModules.remote-builder-user

    # Create giodamelio user
    (
      {pkgs, ...}: {
        users.users.giodamelio = {
          extraGroups = [
            "wheel"
            "networkmanager"
          ];
          isNormalUser = true;
          shell = pkgs.zsh;
          openssh.authorizedKeys.keys = homelab.ssh_keys;
        };
        programs.zsh.enable = true;
      }
    )

    # Niri compositor
    (_: {
      programs.niri.enable = true;

      services.displayManager.ly.enable = true;

      # Audio
      services.pipewire = {
        enable = true;
        alsa.enable = true;
        pulse.enable = true;
      };
    })

    # Chromebook keyboard remapping
    (_: {
      services.keyd = {
        enable = true;
        keyboards.default = {
          ids = ["*"];
          settings = {
            main = {
              # Search key is already leftmeta/Super - keep it as Mod for Niri
              # Make capslock (search key position) act as control when held, escape when tapped
              # Uncomment if you want this instead of Super:
              # capslock = "overload(control, esc)";

              # Top row: map F-keys to Chromebook media functions
              f1 = "back";
              f2 = "forward";
              f3 = "refresh";
              f4 = "zoom"; # fullscreen
              f5 = "scale"; # overview
              f6 = "brightnessdown";
              f7 = "brightnessup";
              f8 = "mute";
              f9 = "volumedown";
              f10 = "volumeup";
            };
            # Search + top row = actual F-keys
            meta = {
              f1 = "f1";
              f2 = "f2";
              f3 = "f3";
              f4 = "f4";
              f5 = "f5";
              f6 = "f6";
              f7 = "f7";
              f8 = "f8";
              f9 = "f9";
              f10 = "f10";
            };
            # Search + Shift + key = missing keys (keeps Mod+arrows free for Niri)
            "meta+shift" = {
              backspace = "delete";
              up = "pageup";
              down = "pagedown";
              left = "home";
              right = "end";
            };
          };
        };
      };
    })

    (_: {
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      networking.hostId = "98a5ee60";

      nixpkgs.config.allowUnfree = true;

      system.stateVersion = "26.05";
    })
  ];
}
