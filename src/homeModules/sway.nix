{...}: {pkgs, ...}: let
  lib = pkgs.lib;
in {
  wayland.windowManager.sway = {
    enable = true;
    xwayland = true;

    config = {
      # Use the Windows/Apple key as our main modifier
      modifier = "Mod4";

      # Use rofi as our launcher
      menu = "rofi -show drun";

      # Use Kitty as our terminal
      terminal = "${pkgs.kitty}/bin/kitty";

      # Replace the built in bars with Waybar
      bars = [];
      startup = [
        {
          command = "${pkgs.waybar}/bin/waybar";
        }
      ];

      # Setup our monitors
      output = let
        shared = {
          scale = "2";
          resolution = "3840x2160";
        };
      in
        lib.attrsets.mapAttrs (_: attr: attr // shared) {
          DP-1 = {
            position = "1080 560";
          };
          DP-2 = {
            position = "3000 560";
          };
          DP-3 = {
            position = "0 0";
            transform = "270";
          };
        };
    };
  };
}
