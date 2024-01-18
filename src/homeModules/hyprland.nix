_: {pkgs, ...}: {
  wayland.windowManager.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  programs.waybar = {
    enable = true;
  };

  # environment.systemPackages = with pkgs; [
  #   kitty
  # ];
}
