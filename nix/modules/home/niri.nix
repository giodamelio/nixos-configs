{
  pkgs,
  perSystem,
  ...
}: {
  home.pointerCursor = {
    name = "Adwaita";
    package = pkgs.adwaita-icon-theme;
    size = 24;
    gtk.enable = true;
  };

  home.packages =
    [perSystem.giopkgs.niri]
    ++ (with pkgs; [
      nautilus
      xwayland-satellite
      libnotify
      wl-clipboard
      swayidle
      brightnessctl
      slurp # Allow selecting screen area (returns geometry)
      grim # Takes screenshots
      satty # Screenshot annotation
      xdg-user-dirs # Easily get XDG dirs inside scripts
    ]);

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
      gaps = 0;
      default-column-width.proportion = 0.5;
      focus-ring = {
        width = 2;
        active.color = "#88c0d0";
        inactive.color = "#4c566a";
      };
      border.enable = false;
    };

    spawn-at-startup = [
      {argv = ["wezterm"];}
    ];

    prefer-no-csd = true;
    screenshot-path = "~/Pictures/Screenshots/%Y-%m-%d_%H-%M-%S.png";

    binds = {
      # Terminal
      "Mod+Return".action.spawn = "wezterm";

      # Close window
      "Mod+Q".action.close-window = {};

      # Show Help
      "Super+Slash".action.show-hotkey-overlay = {};

      # Focus
      "Mod+Left".action.focus-column-left = {};
      "Mod+Right".action.focus-column-right = {};
      "Mod+Up".action.focus-window-or-workspace-up = {};
      "Mod+Down".action.focus-window-or-workspace-down = {};
      "Mod+H".action.focus-column-left = {};
      "Mod+L".action.focus-column-right = {};
      "Mod+K".action.focus-window-or-workspace-up = {};
      "Mod+J".action.focus-window-or-workspace-down = {};

      # Move windows
      "Mod+Shift+Left".action.move-column-left = {};
      "Mod+Shift+Right".action.move-column-right = {};
      "Mod+Shift+Up".action.move-window-up-or-to-workspace-up = {};
      "Mod+Shift+Down".action.move-window-down-or-to-workspace-down = {};
      "Mod+Shift+H".action.move-column-left = {};
      "Mod+Shift+L".action.move-column-right = {};
      "Mod+Shift+K".action.move-window-up-or-to-workspace-up = {};
      "Mod+Shift+J".action.move-window-down-or-to-workspace-down = {};

      # Sizing
      "Mod+F".action.maximize-column = {};
      "Mod+Shift+F".action.fullscreen-window = {};
      "Mod+Minus".action.set-column-width = "-10%";
      "Mod+Equal".action.set-column-width = "+10%";

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
      "Print".action.screenshot = {};
      "Ctrl+Print".action.screenshot-screen = {};
      "Alt+Print".action.screenshot-window = {};

      # Toggle floating
      "Mod+V".action.toggle-window-floating = {};

      # Switch between floating and tiling focus
      "Mod+Shift+V".action.switch-focus-between-floating-and-tiling = {};

      # Overview
      "Mod+Tab".action.toggle-overview = {};

      # Exit niri
      "Mod+Shift+E".action.quit = {};

      # Power controls
      "Mod+Shift+P".action.power-off-monitors = {};
    };
  };
}
