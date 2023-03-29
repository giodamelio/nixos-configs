{ pkgs, ... }: {
  imports = [
  ];

  wayland.windowManager.sway = {
    enable = true;
    config = {
      modifier = "Mod4";
      terminal = "${pkgs.kitty}/bin/kitty";

      # Configure monitors
      # Remember to take scaling into account when calculating positions
      # The height of 420 is to vertically align the landscape monitors with the portrait one
      #
      # +------+
      # |      | +----------+ +----------+
      # |      | |          | |          |
      # | DP-2 | |   DP-3   | |   DP-1   |
      # |      | |          | |          |
      # |      | +----------+ +----------+
      # +------+
      output = {
        DP-2 = {
          transform = "270";
          scale = "2";
          position = "0 0";
        };

        DP-3 = {
          scale = "2";
          position = "1080 420";
        };

        DP-1 = {
          scale = "2";
          position = "3000 420";
        };
      };
    };
  };
}
