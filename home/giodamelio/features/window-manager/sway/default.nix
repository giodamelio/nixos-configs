{ pkgs, ... }: {
  imports = [
  ];

  wayland.windowManager.sway = {
    enable = true;
  };
}
