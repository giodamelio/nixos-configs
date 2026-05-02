{
  pkgs,
  lib,
  config,
  flake,
  ...
}: let
  satellite-earth-download = flake.packages.${pkgs.stdenv.hostPlatform.system}.satellite-earth-download;

  cfg = config.services.satellite-wallpaper;

  set-wallpaper = flake.lib.writeNushellApplication pkgs {
    name = "satellite-set-wallpaper";
    runtimeInputs = [satellite-earth-download];
    source = ''
      use std/log

      def main [] {
        log info "Starting satellite wallpaper update"
        let image = (satellite-earth-download ${cfg.source} --product ${cfg.product} | str trim)
        log info $"Downloaded image: ($image)"

        let outputs = (niri msg --json outputs | from json | columns)
        log info $"Found outputs: ($outputs)"

        for output in $outputs {
          log info $"Setting wallpaper on output: ($output)"
          try {
            noctalia-shell ipc call wallpaper set $image $output
            log info $"Successfully set wallpaper on ($output)"
          } catch {|e|
            log error $"Failed to set wallpaper on ($output): ($e.msg)"
          }
        }
      }
    '';
  };
in {
  options.services.satellite-wallpaper = {
    source = lib.mkOption {
      type = lib.types.str;
      default = "goes-east";
      description = "Satellite source: goes-east, goes-west, himawari";
    };
    product = lib.mkOption {
      type = lib.types.str;
      default = "natural_color";
      description = "Image product type: natural_color, geocolor";
    };
  };

  config = {
    home.packages = [satellite-earth-download];

    systemd.user.services.satellite-wallpaper = lib.mkIf config.programs.noctalia-shell.enable {
      Unit = {
        Description = "Set wallpaper to latest satellite Earth image";
        After = ["graphical-session.target"];
        Requires = ["graphical-session.target"];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${set-wallpaper}/bin/satellite-set-wallpaper";
      };
      Install.WantedBy = ["graphical-session.target"];
    };

    systemd.user.timers.satellite-wallpaper = lib.mkIf config.programs.noctalia-shell.enable {
      Unit.Description = "Update wallpaper with latest satellite Earth image";
      Timer = {
        OnCalendar = "*:00/30";
        Persistent = true;
      };
      Install.WantedBy = ["timers.target"];
    };
  };
}
