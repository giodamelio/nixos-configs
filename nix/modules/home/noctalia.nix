{
  inputs,
  config,
  lib,
  ...
}: {
  imports = [inputs.noctalia.homeModules.default];

  programs.noctalia-shell = {
    enable = true;
  };

  # When niri is enabled, add noctalia keybindings and spawn the shell at startup
  programs.niri.settings = lib.mkIf (config.programs ? niri) {
    spawn-at-startup = [
      {argv = ["noctalia-shell"];}
    ];

    binds = {
      # Noctalia launcher
      "Mod+Space".action.spawn = ["noctalia-shell" "ipc" "call" "launcher" "toggle"];

      # Noctalia control center
      "Mod+S".action.spawn = ["noctalia-shell" "ipc" "call" "controlCenter" "toggle"];

      # Noctalia settings
      "Mod+Comma".action.spawn = ["noctalia-shell" "ipc" "call" "settings" "toggle"];

      # Media controls (Noctalia OSD)
      "XF86AudioRaiseVolume".action.spawn = ["noctalia-shell" "ipc" "call" "volume" "increase"];
      "XF86AudioLowerVolume".action.spawn = ["noctalia-shell" "ipc" "call" "volume" "decrease"];
      "XF86AudioMute".action.spawn = ["noctalia-shell" "ipc" "call" "volume" "muteOutput"];
      "XF86MonBrightnessUp".action.spawn = ["noctalia-shell" "ipc" "call" "brightness" "increase"];
      "XF86MonBrightnessDown".action.spawn = ["noctalia-shell" "ipc" "call" "brightness" "decrease"];
    };
  };
}
