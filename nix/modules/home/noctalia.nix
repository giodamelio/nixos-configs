{
  inputs,
  config,
  lib,
  pkgs,
  flake,
  ...
}: let
  inherit (pkgs.stdenv.hostPlatform) system;
  claude-usage-plugin = flake.packages.${system}.noctalia-claude-usage;
in {
  imports = [inputs.noctalia.homeModules.default];

  programs.noctalia-shell = {
    enable = true;

    plugins = {
      version = 2;
      sources = [
        {
          enabled = true;
          name = "Noctalia Plugins";
          url = "https://github.com/noctalia-dev/noctalia-plugins";
        }
      ];
      states = {
        claude-usage = {
          enabled = true;
          sourceUrl = "";
        };
        network-indicator = {
          enabled = true;
          sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins";
        };
      };
    };
  };

  # Symlink the plugin into noctalia's plugin directory
  home.file.".config/noctalia/plugins/claude-usage".source = claude-usage-plugin;

  # Clear Noctalia QML cache when the plugin changes so Qt picks up new code
  home.activation.clearNoctaliaQmlCache = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ ! -f "$HOME/.cache/noctalia-qs/.claude-usage-store-path" ] || \
       [ "$(cat "$HOME/.cache/noctalia-qs/.claude-usage-store-path" 2>/dev/null)" != "${claude-usage-plugin}" ]; then
      find "$HOME/.cache/noctalia-qs/qmlcache" -type f -delete 2>/dev/null || true
      echo "${claude-usage-plugin}" > "$HOME/.cache/noctalia-qs/.claude-usage-store-path"
    fi
  '';

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
