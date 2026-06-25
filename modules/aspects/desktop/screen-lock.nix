# screen-lock — swaylock-effects + swayidle: lock the session after a short
# idle, then blank the displays after a longer idle, without ever suspending
# the machine. WM-agnostic; each compositor supplies its own display-power
# command via gio.screen-lock.displayOffCommand (niri:
# `niri msg action power-off-monitors`, sway: `swaymsg output '*' dpms off`).
{
  den.aspects.screen-lock.homeManager = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.gio.screen-lock;
    lock = "${cfg.package}/bin/swaylock -f";
  in {
    options.gio.screen-lock = {
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.swaylock-effects;
        defaultText = lib.literalExpression "pkgs.swaylock-effects";
        description = "The swaylock package to use.";
      };

      lockTimeout = lib.mkOption {
        type = lib.types.ints.positive;
        default = 300;
        description = "Seconds of idle before the screen locks.";
      };

      displayOffTimeout = lib.mkOption {
        type = lib.types.ints.positive;
        default = 600;
        description = "Seconds of idle before the displays power off. Keep larger than lockTimeout so the screen locks before it blanks.";
      };

      displayOffCommand = lib.mkOption {
        type = lib.types.str;
        example = "niri msg action power-off-monitors";
        description = ''
          Compositor-specific command to power the displays off. niri and sway
          turn the displays back on automatically on input; compositors that
          need an explicit wake should also set displayOnCommand.
        '';
      };

      displayOnCommand = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "swaymsg output '*' dpms on";
        description = "Optional resume command paired with displayOffCommand.";
      };
    };

    config = {
      programs.swaylock = {
        enable = true;
        inherit (cfg) package;
        settings = {
          screenshots = true;
          effect-blur = "7x5";
          indicator = true;
          clock = true;
        };
      };

      # Let rofi/launchers offer a manual lock.
      xdg.desktopEntries.swaylock = {
        name = "Lock Screen";
        exec = "${cfg.package}/bin/swaylock";
      };

      # Lock, then blank the displays — but never suspend (no idle suspend
      # timeout, so the machine stays awake).
      services.swayidle = {
        enable = true;
        timeouts = [
          {
            timeout = cfg.lockTimeout;
            command = lock;
          }
          ({
              timeout = cfg.displayOffTimeout;
              command = cfg.displayOffCommand;
            }
            // lib.optionalAttrs (cfg.displayOnCommand != null) {
              resumeCommand = cfg.displayOnCommand;
            })
        ];
        events = [
          {
            event = "before-sleep";
            command = lock;
          }
        ];
      };
    };
  };
}
