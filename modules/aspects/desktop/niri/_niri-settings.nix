# Raw Home-Manager/evalModules module for niri-settings (layout, input,
# window-rules and the full keybind set). The leading underscore keeps
# import-tree from loading it as a flake-parts module: it is imported by
# ./niri-settings.nix (the aspect wrapper) and directly by minimal
# `evalModules` contexts (cadmium's single-display niri config).
{
  lib,
  pkgs,
  ...
}: {
  programs.niri.settings = {
    input = {
      keyboard.xkb.layout = "us";
      touchpad = {
        tap = true;
        dwt = true;
        natural-scroll = false;
        scroll-factor = 0.5;
      };
    };

    gestures.hot-corners.enable = false;

    layout = {
      gaps = lib.mkDefault 0;
      default-column-width.proportion = 0.5;
      focus-ring = {
        width = 2;
        active.color = "#88c0d0";
        inactive.color = "#4c566a";
      };
      border.enable = false;
    };

    spawn-at-startup = [
      # {argv = [];}
    ];

    window-rules = [
      {
        matches = [{app-id = "io.gitlab.news_flash.NewsFlash";}];
        default-column-width.proportion = 1.0;
      }
    ];

    prefer-no-csd = true;
    screenshot-path = "~/Pictures/Screenshots/%Y-%m-%d_%H-%M-%S.png";
  };

  gio.niri.binds = {
    # Terminal
    "Mod+Return".action.spawn = "wezterm";

    # Close window
    "Mod+Q".action.close-window = {};

    # Show Help
    "Super+Slash" = {
      action.show-hotkey-overlay = {};
      label = "Show Hotkey Overlay";
      icon = "help-about";
    };

    # Focus
    "Mod+H".action.focus-column-or-monitor-left = {};
    "Mod+L".action.focus-column-or-monitor-right = {};
    "Mod+K".action.focus-window-or-workspace-up = {};
    "Mod+J".action.focus-window-or-workspace-down = {};

    # Focus Monitors
    "Mod+Alt+H".action.focus-monitor-left = {};
    "Mod+Alt+L".action.focus-monitor-right = {};

    # Move windows
    ## Normal directions
    "Mod+Shift+H".action.move-column-left-or-to-monitor-left = {};
    "Mod+Shift+L".action.move-column-right-or-to-monitor-right = {};
    "Mod+Shift+K" = {
      action.move-window-up-or-to-workspace-up = {};
      label = "Move Window Up/To Workspace Up";
    };
    "Mod+Shift+J" = {
      action.move-window-down-or-to-workspace-down = {};
      label = "Move Window Down/To Workspace Down";
    };
    ## Between monitors
    "Mod+Shift+Alt+H" = {
      action.move-window-to-monitor-left = {};
      label = "Move Window to Monitor Left";
      icon = "go-previous";
    };
    "Mod+Shift+Alt+L" = {
      action.move-window-to-monitor-right = {};
      label = "Move Window to Monitor Right";
      icon = "go-next";
    };
    "Mod+Shift+Alt+K" = {
      action.move-window-to-monitor-down = {};
      label = "Move Window to Monitor Down";
      icon = "go-down";
    };
    "Mod+Shift+Alt+J" = {
      action.move-window-to-monitor-up = {};
      label = "Move Window to Monitor Up";
      icon = "go-up";
    };

    # Columns
    "Mod+Comma" = {
      action.consume-window-into-column = {};
      label = "Consume Window Into Column";
    };
    "Mod+Period" = {
      action.expel-window-from-column = {};
      label = "Expel Window From Column";
    };
    "Mod+BracketLeft" = {
      action.consume-or-expel-window-left = {};
      label = "Consume/Expel Window Left";
    };
    "Mod+BracketRight" = {
      action.consume-or-expel-window-right = {};
      label = "Consume/Expel Window Right";
    };
    "Mod+T".action.toggle-column-tabbed-display = {};

    # Sizing
    "Mod+F" = {
      action.maximize-column = {};
      label = "Maximize Column";
      icon = "view-fullscreen";
    };
    "Mod+Shift+F" = {
      action.fullscreen-window = {};
      label = "Fullscreen Window";
      icon = "view-fullscreen";
    };
    "Mod+Minus".action.set-column-width = "-10%";
    "Mod+Equal".action.set-column-width = "+10%";
    "Mod+Backslash" = {
      action.set-column-width = "50%";
      label = "Column Width 50%";
    };
    "Mod+Shift+Backslash" = {
      action.set-column-width = "100%";
      label = "Column Width 100%";
    };
    "Mod+Shift+Minus".action.set-window-height = "-10%";
    "Mod+Shift+Equal".action.set-window-height = "+10%";

    # Workspaces
    "Mod+1".action.focus-workspace = 1;
    "Mod+2".action.focus-workspace = 2;
    "Mod+3".action.focus-workspace = 3;
    "Mod+4".action.focus-workspace = 4;
    "Mod+5".action.focus-workspace = 5;
    "Mod+Shift+1".action.move-column-to-workspace = 1;
    "Mod+Shift+2".action.move-column-to-workspace = 2;
    "Mod+Shift+3".action.move-column-to-workspace = 3;
    "Mod+Shift+4".action.move-column-to-workspace = 4;
    "Mod+Shift+5".action.move-column-to-workspace = 5;

    # Scroll through workspaces
    "Mod+WheelScrollDown".action.focus-workspace-down = {};
    "Mod+WheelScrollUp".action.focus-workspace-up = {};

    # Screenshots
    "Print".action.spawn-sh = ''grim -t png -g "$(slurp -o -d -F monospace)" - | satty --filename - --copy-command=wl-copy --output-filename="$(xdg-user-dir PICTURES)/Screenshots/Screenshot from %Y-%m-%d %H:%M:%S.png" --actions-on-enter="save-to-file,exit" --actions-on-escape="save-to-clipboard,exit" --brush-smooth-history-size=5 --initial-tool=arrow --fullscreen=current-screen'';
    "Alt+Print" = {
      action.screenshot-window = {};
      label = "Screenshot Window";
      icon = "screenshot";
    };

    # Toggle floating
    "Mod+V" = {
      action.toggle-window-floating = {};
      label = "Toggle Floating";
    };

    # Switch between floating and tiling focus
    "Mod+Shift+T" = {
      action.switch-focus-between-floating-and-tiling = {};
      label = "Switch Floating/Tiling Focus";
    };

    # Overview
    "Mod+Tab" = {
      action.toggle-overview = {};
      label = "Toggle Overview";
    };

    # Exit niri
    "Mod+Shift+E" = {
      action.quit = {};
      label = "Exit Niri";
      icon = "system-log-out";
    };

    # Voice to text (handy)
    "Mod+Alt+Space" = {
      action.spawn = ["${pkgs.procps}/bin/pkill" "-USR2" "-n" "handy"];
      label = "Voice to Text";
      icon = "audio-input-microphone";
    };
    "XF86Calculator".action.spawn = ["${pkgs.procps}/bin/pkill" "-USR2" "-n" "handy"];

    # Power controls
    "Mod+Shift+P" = {
      action.power-off-monitors = {};
      label = "Power Off Monitors";
      icon = "display-brightness";
    };

    # Media Keys
    "XF86AudioPlay".action.spawn = ["${lib.getExe pkgs.playerctl}" "play-pause"];
    "XF86AudioPause".action.spawn = ["${lib.getExe pkgs.playerctl}" "play-pause"];
    "XF86AudioNext".action.spawn = ["${lib.getExe pkgs.playerctl}" "next"];
    "XF86AudioPrev".action.spawn = ["${lib.getExe pkgs.playerctl}" "previous"];
  };
}
