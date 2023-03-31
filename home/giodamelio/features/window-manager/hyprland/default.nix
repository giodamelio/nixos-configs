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
    settings = {
      mainBar = {
        layer = "top";
        position = "top";
        output = [
          "DP-3"
        ];

        modules-left = [ "wlr/workspaces" ];
        modules-center = [ "clock" ];
        modules-right = [ "cpu" "memory" "network" "tray" ];

        clock = {
          format = "{:%I:%M%p}";
          format-alt = "{:%A, %B %d, %Y (%R)}";
          tooltip-format = "<tt><small>{calendar}</small></tt>";
        };

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
        };
      };
      leftBar = {
        layer = "top";
        position = "top";
        output = [
          "DP-2"
        ];

        modules-left = [ "wlr/workspaces" ];
      };
      rightBar = {
        layer = "top";
        position = "top";
        output = [
          "DP-1"
        ];

        modules-left = [ "wlr/workspaces" ];
      };
    };
  };
}
