{pkgs, ...}: {
  home.packages = with pkgs; [
    fuzzel
    libnotify
    wl-clipboard
    grim
    slurp
    swayidle
    brightnessctl
  ];

  home.sessionVariables = {
    XDG_CURRENT_DESKTOP = "niri";
    XDG_SESSION_DESKTOP = "niri";
    XDG_SESSION_TYPE = "wayland";
    NIXOS_OZONE_WL = "1";
  };

  xdg.configFile."niri/config.kdl".text = ''
    // Cesium minimal Niri config

    input {
        keyboard {
            xkb {
                layout "us"
            }
        }

        touchpad {
            tap
            natural-scroll
            dwt  // disable while typing
        }
    }

    // Minimal layout
    layout {
        gaps 8

        default-column-width {
            proportion 0.5;
        }

        focus-ring {
            width 2
            active-color "#88c0d0"
            inactive-color "#4c566a"
        }

        border {
            off
        }
    }

    // Spawn terminal on startup for convenience
    spawn-at-startup "wezterm"

    // Prefer server-side decorations
    prefer-no-csd

    // Screenshots
    screenshot-path "~/Pictures/Screenshots/%Y-%m-%d_%H-%M-%S.png"

    binds {
        // Terminal
        Mod+Return { spawn "wezterm"; }

        // Launcher
        Mod+Space { spawn "fuzzel"; }

        // Close window
        Mod+Q { close-window; }

        // Focus
        Mod+Left { focus-column-left; }
        Mod+Right { focus-column-right; }
        Mod+Up { focus-window-or-workspace-up; }
        Mod+Down { focus-window-or-workspace-down; }
        Mod+H { focus-column-left; }
        Mod+L { focus-column-right; }
        Mod+K { focus-window-or-workspace-up; }
        Mod+J { focus-window-or-workspace-down; }

        // Move windows
        Mod+Shift+Left { move-column-left; }
        Mod+Shift+Right { move-column-right; }
        Mod+Shift+Up { move-window-up-or-to-workspace-up; }
        Mod+Shift+Down { move-window-down-or-to-workspace-down; }
        Mod+Shift+H { move-column-left; }
        Mod+Shift+L { move-column-right; }
        Mod+Shift+K { move-window-up-or-to-workspace-up; }
        Mod+Shift+J { move-window-down-or-to-workspace-down; }

        // Sizing
        Mod+F { maximize-column; }
        Mod+Shift+F { fullscreen-window; }
        Mod+Minus { set-column-width "-10%"; }
        Mod+Equal { set-column-width "+10%"; }

        // Workspaces
        Mod+1 { focus-workspace 1; }
        Mod+2 { focus-workspace 2; }
        Mod+3 { focus-workspace 3; }
        Mod+4 { focus-workspace 4; }
        Mod+5 { focus-workspace 5; }
        Mod+Shift+1 { move-column-to-workspace 1; }
        Mod+Shift+2 { move-column-to-workspace 2; }
        Mod+Shift+3 { move-column-to-workspace 3; }
        Mod+Shift+4 { move-column-to-workspace 4; }
        Mod+Shift+5 { move-column-to-workspace 5; }

        // Scroll through workspaces
        Mod+WheelScrollDown { focus-workspace-down; }
        Mod+WheelScrollUp { focus-workspace-up; }

        // Screenshots
        Print { screenshot; }
        Ctrl+Print { screenshot-screen; }
        Alt+Print { screenshot-window; }

        // Toggle floating
        Mod+V { toggle-window-floating; }

        // Switch between floating and tiling focus
        Mod+Shift+V { switch-focus-between-floating-and-tiling; }

        // Exit niri
        Mod+Shift+E { quit; }

        // Power controls
        Mod+Shift+P { power-off-monitors; }
    }
  '';
}
