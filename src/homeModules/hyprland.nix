_: {pkgs, ...}: {
  home.packages = with pkgs; [
    rofi-wayland
    swww
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    xwayland.enable = true;

    settings = {
      "$mainMod" = "SUPER";

      bind = [
        # Launch Kitty with mod+enter
        "$mainMod, Return, exec, kitty"

        # Launch programs with Rofi
        "$mainMod, d, exec, rofi -show drun"
        "$mainMod SHIFT, d, exec, rofi -show run"

        # Exit Hyprland
        "$mainMod, M, exit"

        # Move focus with HJKL
        "$mainMod, h, movefocus, l"
        "$mainMod, j, movefocus, d"
        "$mainMod, k, movefocus, u"
        "$mainMod, l, movefocus, r"

        # Move windows with SHIFT HJKL
        "$mainMod SHIFT, H, movewindow, l"
        "$mainMod SHIFT, L, movewindow, r"
        "$mainMod SHIFT, K, movewindow, u"
        "$mainMod SHIFT, J, movewindow, d"

        # Switch workspaces
        "$mainMod, 1, workspace, 1"
        "$mainMod, 2, workspace, 2"
        "$mainMod, 3, workspace, 3"
        "$mainMod, 4, workspace, 4"
        "$mainMod, 5, workspace, 5"
        "$mainMod, 6, workspace, 6"
        "$mainMod, 7, workspace, 7"
        "$mainMod, 8, workspace, 8"
        "$mainMod, 9, workspace, 9"

        # Move active window to workspace
        "$mainMod SHIFT, 1, movetoworkspace, 1"
        "$mainMod SHIFT, 2, movetoworkspace, 2"
        "$mainMod SHIFT, 3, movetoworkspace, 3"
        "$mainMod SHIFT, 4, movetoworkspace, 4"
        "$mainMod SHIFT, 5, movetoworkspace, 5"
        "$mainMod SHIFT, 6, movetoworkspace, 6"
        "$mainMod SHIFT, 7, movetoworkspace, 7"
        "$mainMod SHIFT, 8, movetoworkspace, 8"
        "$mainMod SHIFT, 9, movetoworkspace, 9"
      ];

      # Cadmium monitors
      # Effective resolution is 2560x1440 when scaled to 1.5
      monitor = [
        "DP-1,3840x2160,1440x560,1.5"
        "DP-2,3840x2160,4000x560,1.5"
        "DP-3,3840x2160,0x0,1.5"
        "DP-3,transform,1"
      ];

      exec-once = [
        "waybar"
        "dunst"
        "swww init"
        "swww img /tmp/epic_latest_annotated.png --transition-type none --resize no"
      ];
    };
  };

  programs.waybar = {
    enable = true;

    settings = let
      clock = {
        format = "{:%I:%M %p} ";
        format-alt = "{:%A, %B %d, %Y (%I:%M %p)}";
        tooltip-format = "<tt><small>{calendar}</small></tt>";
        calendar = {
          mode = "month";
          mode-mon-col = 3;
          weeks-pos = "right";
          on-scroll = 1;
          on-click-right = "mode";
          format = {
            months = "<span color='#ffead3'><b>{}</b></span>";
            days = "<span color='#ecc6d9'><b>{}</b></span>";
            weeks = "<span color='#99ffdd'><b>W{}</b></span>";
            weekdays = "<span color='#ffcc66'><b>{}</b></span>";
            today = "<span color='#ff6699'><b><u>{}</u></b></span>";
          };
        };
        actions = {
          on-click-right = "mode";
          on-scroll-up = "shift_up";
          on-scroll-down = "shift_down";
        };
      };
    in {
      main = {
        layer = "top";
        position = "top";
        output = ["DP-1"];

        modules-left = ["hyprland/workspaces" "hyprland/submap"];
        modules-center = ["hyprland/window"];
        modules-right = ["network" "cpu" "memory" "tray" "clock"];

        inherit clock;

        network = {
          interface = "enp0*";
          format-ethernet = "{ipaddr}/{cidr} 󰛳";
          format-linked = "{ifname} 󰅛";
          format-disconnected = "{ifname} 󰅛";
          format-alt = "{ifname}: {ipaddr}/{cidr}";
          tooltip-format = ''
            {ipaddr}/{cidr}

            Down: {bandwidthDownBytes}
            Up:   {bandwidthUpBytes}
          '';
        };

        cpu = {
          format = "{icon0}{icon1}{icon2}{icon3}{icon4}{icon5}{icon6}{icon7}{icon8}{icon9}{icon10}{icon11} {usage}% ";
          interval = 1;
          format-icons = [
            "<span color='#69ff94'>▁</span>" # green
            "<span color='#2aa9ff'>▂</span>" # blue
            "<span color='#f8f8f2'>▃</span>" # white
            "<span color='#f8f8f2'>▄</span>" # white
            "<span color='#ffffa5'>▅</span>" # yellow
            "<span color='#ffffa5'>▆</span>" # yellow
            "<span color='#ff9977'>▇</span>" # orange
            "<span color='#dd532e'>█</span>" # red
          ];
        };

        memory = {
          format = "{percentage}% ({used}GiB) ";
        };
      };

      secondary = {
        layer = "top";
        position = "top";
        output = ["DP-2" "DP-3"];

        modules-left = ["hyprland/workspaces"];
        modules-right = ["clock"];

        inherit clock;
      };
    };
  };

  programs.rofi = {
    enable = true;
    package = pkgs.rofi-wayland;
  };

  services.dunst = {
    enable = true;
    settings = {
      global = {
        follow = "mouse";
      };
    };
  };
}
