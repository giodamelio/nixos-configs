{
  config,
  pkgs,
  lib,
  flake,
  ...
}: let
  inherit (flake.lib.homelab.machines.cadmium) monitor-names;
  modifier = "Mod4";
  flameshotModified = pkgs.flameshot.override {enableWlrSupport = true;};
in {
  home.packages = with pkgs; [
    libnotify # For sending notifications

    # Setup good screenshots
    flameshotModified # For nice screenshots
    grim # Required backend for Wayland screenshots
    slurp # For area selection (optional but recommended)
    wl-clipboard # For clipboard functionality
  ];

  home.sessionVariables = {
    # Help QT applications work better with Wayland
    QT_QPA_PLATFORM = "wayland";
    SDL_VIDEODRIVER = "wayland";
    _JAVA_AWT_WM_NONREPARENTING = "1";
    XDG_CURRENT_DESKTOP = "sway";
    XDG_SESSION_DESKTOP = "sway";
  };

  wayland.windowManager.sway = {
    enable = true;
    xwayland = true;

    extraConfigEarly = ''
      for_window [app_id="flameshot" title="flameshot"] border pixel 0, floating enable, fullscreen disable, move absolute position 0 0
    '';

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

        # Screenshots
        "Print" = "exec flameshot gui";
        "Shift+Print" = "exec flameshot gui --clipboard";
        "${modifier}+Print" = "exec flameshot full --clipboard";
        "${modifier}+Shift+Print" = "exec flameshot full --path ~/Pictures/Screenshots/";
        "${modifier}+ctrl+Print" = "exec flameshot gui --delay 3000";
      };

      # Assign certin programs to certin workspaces
      assigns = {
        "10" = [
          {app_id = "thunderbird";}
          {app_id = "spotify";}
        ];
      };
    };
  };

  # Notification daemon
  services.swaync = {
    enable = true;
    settings = {
      "$schema" = "/etc/xdg/swaync/configSchema.json";
      ignore-gtk-theme = true;
      positionX = "right";
      positionY = "top";
      layer = "overlay";
      control-center-layer = "top";
      layer-shell = true;
      layer-shell-cover-screen = true;
      cssPriority = "highest";
      control-center-margin-top = 0;
      control-center-margin-bottom = 0;
      control-center-margin-right = 0;
      control-center-margin-left = 0;
      notification-2fa-action = true;
      notification-inline-replies = false;
      notification-body-image-height = 100;
      notification-body-image-width = 200;
      timeout = 10;
      timeout-low = 5;
      timeout-critical = 0;
      fit-to-screen = true;
      relative-timestamps = true;
      control-center-width = 500;
      control-center-height = 600;
      notification-window-width = 500;
      keyboard-shortcuts = true;
      notification-grouping = true;
      image-visibility = "when-available";
      transition-time = 200;
      hide-on-clear = false;
      hide-on-action = true;
      text-empty = "No Notifications";
      script-fail-notify = true;
      widgets = [
        "buttons-grid"
        "mpris"
        "inhibitors"
        "title"
        "dnd"
        "notifications"
      ];
      widget-config = {
        inhibitors = {
          text = "Inhibitors";
          button-text = "Clear All";
          clear-all-button = true;
        };
        title = {
          text = "Notifications";
          clear-all-button = true;
          button-text = "Clear All";
        };
        dnd = {
          text = "Do Not Disturb";
        };
        label = {
          max-lines = 5;
          text = "Label Text";
        };
        mpris = {
          blacklist = [
          ];
          autohide = false;
          show-album-art = "always";
          loop-carousel = false;
        };
        buttons-grid = {
          buttons-per-row = 7;
          actions = [
            {
              label = "直";
              type = "toggle";
              active = true;
              command = "sh -c '[[ $SWAYNC_TOGGLE_STATE == true ]] && nmcli radio wifi on || nmcli radio wifi off'";
              update-command = "sh -c '[[ $(nmcli radio wifi) == \"enabled\" ]] && echo true || echo false'";
            }
          ];
        };
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
      sway = {
        default = ["wlr" "gtk"];
        "org.freedesktop.impl.portal.Screenshot" = ["wlr"];
        "org.freedesktop.impl.portal.ScreenCast" = ["wlr"];
      };
    };
    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
    ];
  };

  # Setup Flameshot for screenshots
  services.flameshot = {
    enable = true;
    package = flameshotModified;
    settings = {
      General = {
        # Basic settings
        showStartupLaunchMessage = false;
        savePath = "${config.home.homeDirectory}/Pictures/Screenshots";
        savePathFixed = true;

        # UI settings
        drawColor = "#ff0000";
        drawThickness = 2;

        # Wayland specific (if needed)
        useJpgForClipboard = false;
        disabledGrimWarning = true;
      };
    };
  };
  # Override a few env vars
  systemd.user.services.flameshot.Service.Environment = [
    "QT_FONT_DPI=250"
    "QT_ENABLE_HIGHDPI_SCALING=0.5"
    "QT_AUTO_SCREEN_SCALE_FACTOR=0"
  ];

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
