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
      def main [] {
        let image = (satellite-earth-download ${cfg.source} --product ${cfg.product})
        let outputs = (niri msg --json outputs | from json | columns)
        for output in $outputs {
          try { noctalia-shell ipc call wallpaper set $image $output }
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
