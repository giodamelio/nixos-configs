{
  pkgs,
  lib,
  flake,
  ...
}: let
  inherit (flake.lib.homelab.machines.cadmium) monitor-names;
  modifier = "Mod4";
in {
  wayland.windowManager.sway = {
    enable = true;
    xwayland = true;

    config = {
      # Use the Windows/Apple key as our main modifier
      inherit modifier;

      # Use rofi as our launcher
      menu = "${pkgs.wofi}/bin/wofi --show=drun --allow-images";

      # Use Wezterm as our terminal
      terminal = "${pkgs.wezterm}/bin/wezterm";

      # Replace the built in bars with Waybar
      bars = [];

      # Start some programs automatically
      startup = [
        {
          command = "${pkgs.thunderbird}/bin/thunderbird";
        }
        {
          command = "${pkgs.spotify}/bin/spotify";
        }
      ];

      # Don't make the window focus follow the mouse
      focus.followMouse = "no";

      # Setup our monitors
      output = let
        shared = {
          scale = "2";
          resolution = "3840x2160";
        };
      in
        lib.attrsets.mapAttrs (_: attr: attr // shared) {
          "${monitor-names.middle}" = {
            position = "1080 560";
          };
          "${monitor-names.right}" = {
            position = "3000 560";
          };
          "${monitor-names.left}" = {
            position = "0 0";
            transform = "270";
          };
        };

      # Pin workspaces to monitors
      workspaceOutputAssign = [
        {
          workspace = "1";
          output = monitor-names.middle;
        }
        {
          workspace = "2";
          output = monitor-names.right;
        }
        {
          workspace = "3";
          output = monitor-names.left;
        }
        {
          workspace = "10";
          output = monitor-names.middle;
        }
      ];

      # Add some keybindings
      keybindings = lib.mkOptionDefault {
        # Switch to the last focused windows
        "${modifier}+Tab" = "exec ${pkgs.swayr}/bin/swayr switch-to-urgent-or-lru-window";

        # Clipboard History
        "${modifier}+v" = "exec ${pkgs.cliphist}/bin/cliphist list | ${pkgs.wofi}/bin/wofi --show=dmenu | ${pkgs.cliphist}/bin/cliphist decode | ${pkgs.wl-clipboard}/bin/wl-copy";

        # Make media buttons work
        "XF86AudioRaiseVolume" = "exec ${pkgs.pw-volume}/bin/pw-volume change +2.5%";
        "XF86AudioLowerVolume" = "exec ${pkgs.pw-volume}/bin/pw-volume change -2.5%";
        "XF86AudioMute" = "exec ${pkgs.pw-volume}/bin/pw-volume mute toggle'";
        "XF86AudioPlay" = "exec ${pkgs.playerctl}/bin/playerctl play-pause";
        "XF86Launch6" = "exec ${pkgs.playerctl}/bin/playerctl previous";
        "XF86Launch7" = "exec ${pkgs.playerctl}/bin/playerctl play-pause";
        "XF86Launch8" = "exec ${pkgs.playerctl}/bin/playerctl next";
      };

      # Assign certin programs to certin workspaces
      assigns = {
        "10" = [
          {app_id = "thunderbird";}
        ];
      };
    };
  };

  # Start Network Manager Applet
  services.network-manager-applet.enable = true;

  # XDG Portal
  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
    config = {
      common.default = "*";
    };
    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
    ];
  };

  programs.swayr = {
    enable = true;
    systemd.enable = true;

    settings = {
      menu = {
        executable = "${pkgs.wofi}/bin/wofi";
        args = [
          "--show=dmenu"
          "--allow-markup"
          "--allow-images"
          "--insensitive"
          "--cache-file=/dev/null"
          "--parse-search"
          "--height=40%"
          "--prompt={prompt}"
        ];
      };
    };
  };

  programs.swaylock = {
    enable = true;
    package = pkgs.swaylock-effects;
    settings = {
      screenshots = true;
      effect-blur = "7x5";
      indicator = true;
      clock = true;
    };
  };

  # Add an entry to lock the screen to XDG Desktop so Rofi can pick it up
  xdg.desktopEntries.swaylock = {
    name = "Lock Screen";
    exec = "swaylock";
  };

  services.cliphist.enable = true;

  # Turn the screen off after awhile
  services.swayidle = {
    enable = true;
    timeouts = [
      # { timeout = 5; command = "swaylock"; }
      # { timeout = 5; command = "touch /home/giodamelio/should-have-locked"; }
      # { timeout = 5; command = "swaymsg output * dpms off"; resumeCommand = "swaymsg output * dpms on"; }

      # exec swayidle -w \
      # timeout 1800 'media pause' \
      # timeout 1800 $locker \
      # timeout 900 'swaymsg "output * dpms off"' \
      # timeout 15 'if pgrep -x swaylock; then swaymsg "output * dpms off"; fi' \
      # resume 'swaymsg "output * dpms on"' \
      # before-sleep $locker
    ];
  };
}
