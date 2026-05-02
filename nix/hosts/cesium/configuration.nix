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
    flake.nixosModules.lix
    flake.nixosModules.wifi
    flake.nixosModules.nh
    flake.nixosModules.optnix
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

    # Niri compositor (via niri-flake)
    inputs.niri.nixosModules.niri
    ({
      lib,
      pkgs,
      ...
    }: let
      niriPackage = perSystem.giopkgs.niri.overrideAttrs (old: {
        passthru =
          old.passthru or {}
          // {
            providedSessions = ["niri"];
          };
        postFixup =
          old.postFixup or ""
          + ''
            substituteInPlace $out/share/systemd/user/niri.service \
              --replace-fail "ExecStart=niri" "ExecStart=$out/bin/niri"
          '';
      });
    in {
      programs.niri.enable = true;
      programs.niri.package = niriPackage;

      # The gnome portal refuses to expose FileChooser without Mutter,
      # so route it to the GTK portal explicitly.
      xdg.portal.extraPortals = [pkgs.xdg-desktop-portal-gtk];
      xdg.portal.config.niri = {
        "org.freedesktop.impl.portal.FileChooser" = ["gtk"];
      };

      # Fix portal services starting before niri-session has exported
      # WAYLAND_DISPLAY. See: https://github.com/sodiboo/niri-flake/issues/509
      systemd.user.services.xdg-desktop-portal = {
        after = ["xdg-desktop-autostart.target"];
      };
      systemd.user.services.xdg-desktop-portal-gtk = {
        after = ["xdg-desktop-autostart.target"];
      };
      systemd.user.services.xdg-desktop-portal-gnome = {
        after = ["xdg-desktop-autostart.target"];
      };
      systemd.user.services.niri-flake-polkit = {
        after = ["xdg-desktop-autostart.target"];
      };

      services.displayManager.ly.enable = true;

      # Workaround for NixOS/nixpkgs#427414: ly's shell session pipes
      # stdout/stderr to systemd-cat, making command output invisible.
      # Disable journal redirect so shell logins behave normally.
      services.displayManager.logToJournal = false;

      # Register niri systemd user units in /etc/systemd/user/ so Ly can
      # find them. Setting PATH = null prevents NixOS from injecting a
      # restricted PATH that would break spawned programs — niri inherits
      # the user's full environment via niri-session's import-environment.
      systemd.user.services.niri = {
        description = "A scrollable-tiling Wayland compositor";
        bindsTo = ["graphical-session.target"];
        before = ["graphical-session.target" "xdg-desktop-autostart.target"];
        wants = ["graphical-session-pre.target" "xdg-desktop-autostart.target"];
        after = ["graphical-session-pre.target"];
        environment.PATH = lib.mkForce null;
        serviceConfig = {
          Slice = "session.slice";
          Type = "notify";
          ExecStart = "${niriPackage}/bin/niri --session";
        };
      };

      systemd.user.targets.niri-shutdown = {
        description = "Shutdown running niri session";
        conflicts = ["graphical-session.target" "graphical-session-pre.target"];
        after = ["graphical-session.target" "graphical-session-pre.target"];
        unitConfig = {
          DefaultDependencies = false;
          StopWhenUnneeded = true;
        };
      };

      # Ensure systemd user services have the full NixOS PATH available
      # (same approach as the Hyprland NixOS module)
      systemd.user.extraConfig = ''
        DefaultEnvironment="PATH=/run/wrappers/bin:/etc/profiles/per-user/%u/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"
      '';

      # Noctalia prerequisites
      services.upower.enable = true;
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

    # Battery and power management
    flake.nixosModules.battery-optimization

    # KDE Connect firewall ports (auto-enabled when any HM user enables kdeconnect)
    flake.nixosModules.kde-connect

    (_: {
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      networking.hostId = "98a5ee60";

      nixpkgs.config.allowUnfree = true;

      system.stateVersion = "26.05";
    })
  ];
}
