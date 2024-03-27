_: {pkgs, ...}: {
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
      defaultNetwork = {
        format-ethernet = "{ifname} {ipaddr} 󰛳";
        format-linked = "{ifname} 󰅛";
        format-disconnected = "{ifname} 󰅛";
        format-alt = "{ifname}: {ipaddr}/{cidr}";
        tooltip-format = ''
          {ifname} {ipaddr}/{cidr}

          Down: {bandwidthDownBytes}
          Up:   {bandwidthUpBytes}
        '';
      };
    in {
      main = {
        layer = "top";
        position = "top";
        output = ["DP-1"];

        # modules-left = ["hyprland/workspaces" "hyprland/submap"];
        # modules-center = ["hyprland/window"];
        modules-left = ["sway/mode" "sway/workspaces"];
        modules-center = ["sway/window"];
        modules-right = ["network#wg0" "network" "cpu" "memory" "pulseaudio" "tray" "clock"];

        inherit clock;

        network =
          defaultNetwork
          // {
            interface = "enp0*";
          };

        "network#wg0" =
          defaultNetwork
          // {
            interface = "wg0";
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

        pulseaudio = {
          format = "{volume}% {icon}";
          format-icons = {
            headphone = "";
            default = ["" ""];
          };
          on-click = "pavucontrol";
          on-click-right = "${pkgs.pw-volume}/bin/pw-volume mute toggle";
        };
      };

      secondary = {
        layer = "top";
        position = "top";
        output = ["DP-2" "DP-3"];

        # modules-left = ["hyprland/workspaces"];
        modules-left = ["sway/workspaces"];
        modules-right = ["clock"];

        inherit clock;
      };
    };
  };
}
