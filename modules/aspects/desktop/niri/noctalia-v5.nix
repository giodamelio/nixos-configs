{inputs, ...}: {
  # Needs the NixOS half, not home.packages: the module sets the setcap wrapper
  # on gsr-kms-server that promptless capture depends on.
  den.aspects.noctalia-v5.nixos = _: {
    programs.gpu-screen-recorder.enable = true;
  };

  den.aspects.noctalia-v5.homeManager = {
    config,
    lib,
    pkgs,
    perSystem,
    ...
  }: let
    claude-usage-plugin = perSystem.self.noctalia-claude-usage-v5;
  in {
    imports = [inputs.noctalia.homeModules.default];

    programs.noctalia = {
      enable = true;

      # Only plugins and widget placement are declared here; theme, wallpaper and
      # the rest stay owned by the settings GUI in ~/.local/state/noctalia.
      settings = {
        plugins.enabled = ["giodamelio/claude_usage"];
        bar.default.end = [
          "giodamelio/claude_usage:usage"
          "tray"
          "notifications"
          "clipboard"
          "network"
          "bluetooth"
          "volume"
          "brightness"
          "battery"
          "control-center"
          "session"
        ];
      };
    };

    # Carried over from v4's screen-toolkit plugin. v5 has screenshot, clipboard
    # and recording built in, so these are only kept because they are useful on
    # their own; prune once you know which you still want.
    home.packages = with pkgs; [
      grim
      slurp
      imagemagick
      ffmpeg
      jq
      gifski
      tesseract
      zbar
      translate-shell
      wl-screenrec
    ];

    # ~/.local/share/noctalia/plugins is the built-in "local" plugin source.
    # Symlinking here rather than adding a store path as a [[plugins.source]]
    # keeps config.toml stable across plugin rebuilds.
    home.file.".local/share/noctalia/plugins/claude-usage".source = claude-usage-plugin;

    programs.niri.settings = lib.mkIf (config.programs ? niri) {
      spawn-at-startup = [
        {argv = ["noctalia"];}
      ];
    };

    gio.niri.binds = lib.mkIf (config.programs ? niri) {
      "Mod+Space".action.spawn = ["noctalia" "msg" "panel-toggle" "launcher"];
      "Mod+S".action.spawn = ["noctalia" "msg" "panel-toggle" "control-center"];
      "Mod+Escape".action.spawn = ["noctalia" "msg" "session" "lock"];
      "Mod+Shift+V".action.spawn = ["noctalia" "msg" "panel-toggle" "clipboard"];

      "XF86AudioRaiseVolume".action.spawn = ["noctalia" "msg" "volume-up"];
      "XF86AudioLowerVolume".action.spawn = ["noctalia" "msg" "volume-down"];
      "XF86AudioMute".action.spawn = ["noctalia" "msg" "volume-mute"];

      "XF86MonBrightnessUp".action.spawn = ["noctalia" "msg" "brightness-up"];
      "XF86MonBrightnessDown".action.spawn = ["noctalia" "msg" "brightness-down"];
    };
  };
}
