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
}
