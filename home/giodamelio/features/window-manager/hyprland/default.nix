{ pkgs, inputs, ... }:

{
  imports = [
    # inputs.hyprland.nixosModules.default
    inputs.hyprland.homeManagerModules.default
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    package = inputs.hyprland.packages.${pkgs.system}.default;
    extraConfig = "\n" + (builtins.readFile ./hyprland.conf);
  };

  # home.packages = [
  #   inputs.hyprland.nixosModules.default
  # ];
  programs.waybar = {
    enable = true;
    package = inputs.hyprland.packages.${pkgs.system}.waybar-hyprland;
    settings = let 
      clock-config = {
        format = "{:%I:%M%p}";
        format-alt = "{:%A, %B %d, %Y (%R)}";
        tooltip-format = "<tt><small>{calendar}</small></tt>";
      };
    in {
      mainBar = {
        layer = "top";
        position = "top";
        output = [
          "DP-3"
        ];

        modules-left = [ "wlr/workspaces" "hyprland/submap" ];
        modules-center = [ "hyprland/window" ];
        modules-right = [ "clock" "cpu" "memory" "network" "tray" ];

        clock = clock-config;

        "wlr/workspaces" = {
          format = "{icon}";
        };

        cpu = {
          format = "{usage}% ";
        };

        memory = {
          format = "{}% ";
        };

        network = {
          format = "{ifname}: {ipaddr} 󰱓";
          tooltip-format = ''
            {ifname}
            IP: {ipaddr}
            Gateway: {gwaddr}
            Down (b/s): {bandwidthDownBytes}
            Up (b/s): {bandwidthUpBytes}
          '';
        };
      };
      leftBar = {
        layer = "top";
        position = "top";
        output = [
          "DP-2"
        ];

        modules-left = [ "wlr/workspaces" "hyprland/submap" ];
        modules-right = [ "clock" ];

        clock = clock-config;
      };
      rightBar = {
        layer = "top";
        position = "top";
        output = [
          "DP-1"
        ];

        modules-left = [ "wlr/workspaces" "hyprland/submap" ];
        modules-right = [ "clock" ];

        clock = clock-config;
      };
    };
  };
}
