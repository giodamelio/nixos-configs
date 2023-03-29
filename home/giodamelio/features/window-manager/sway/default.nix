{ pkgs, ... }: {
  imports = [
  ];

  wayland.windowManager.sway = {
    enable = true;
    config = {
      modifier = "Mod4";
      terminal = "${pkgs.kitty}/bin/kitty";
    };
  };

  home.packages = with pkgs; [
    kitty
  ];
}
