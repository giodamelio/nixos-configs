{ pkgs, inputs, ... }:

{
  imports = [
    inputs.hyprland.homeManagerModules.default
  ];

  wayland.windowManager.hyprland.enable = true;

  home.packages = with pkgs; [];
}
