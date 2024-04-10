_: {pkgs, ...}: {
  # home.packages = with pkgs; [];

  wayland.windowManager.hyprland = {
    enable = true;
    xwayland.enable = true;

    settings = {
      "$mainMod" = "SUPER";

      bind = [
        # Launch Kitty with mod+enter
        "$mainMod, Return, exec, kitty"

        # Launch programs with Rofi
        "$mainMod, d, exec, ${pkgs.wofi}/bin/wofi --show=drun --allow-images"

        # Exit Hyprland
        "$mainMod SHIFT, E, exit"

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
      ];
    };
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
