{ inputs, ... }:

{
  imports = [
    # inputs.hyprland.nixosModules.default
    inputs.hyprland.homeManagerModules.default
  ];

  wayland.windowManager.hyprland.enable = true;

  # home.packages = [
  #   inputs.hyprland.nixosModules.default
  # ];
}
