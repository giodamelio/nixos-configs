{
  flake,
  pkgs,
  ...
}: {
  imports = [
    flake.nixosModules.niri
  ];

  environment.systemPackages = with pkgs; [
    wvkbd
  ];

  # Chromebook keyboard remapping
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = ["*"];
      settings = {
        main = {
          # Top row: map F-keys to Chromebook media functions
          f1 = "back";
          f2 = "forward";
          f3 = "refresh";
          f4 = "zoom"; # fullscreen
          f5 = "scale"; # overview
          f6 = "brightnessdown";
          f7 = "brightnessup";
          f8 = "mute";
          f9 = "volumedown";
          f10 = "volumeup";
        };
        # Search + top row = actual F-keys
        meta = {
          f1 = "f1";
          f2 = "f2";
          f3 = "f3";
          f4 = "f4";
          f5 = "f5";
          f6 = "f6";
          f7 = "f7";
          f8 = "f8";
          f9 = "f9";
          f10 = "f10";
        };
        # Search + Shift + key = missing keys (keeps Mod+arrows free for Niri)
        "meta+shift" = {
          backspace = "delete";
          up = "pageup";
          down = "pagedown";
          left = "home";
          right = "end";
        };
      };
    };
  };
}
