{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.gio.cronitor;

  checkScript = pkgs.writeShellScript "cronitor-check" ''
    set -e

    API_KEY=$(cat "$CREDENTIALS_DIRECTORY/cronitor-api-key")
    MONITOR="systemd-service-active-${config.networking.hostName}-$1"

    if systemctl is-active --quiet "$1"; then
      ${lib.getExe pkgs.curl} -sf "https://cronitor.link/p/$API_KEY/$MONITOR?state=complete"
    else
      ${lib.getExe pkgs.curl} -sf "https://cronitor.link/p/$API_KEY/$MONITOR?state=fail"
    fi
  '';
in {
  options.gio.cronitor = {
    enable = lib.mkEnableOption "cronitor monitoring for systemd units";

    units = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of systemd unit names to monitor via cronitor";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services."cronitor-check@" = {
      description = "Cronitor health check for %i";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${checkScript} %i";
      };
    };

    systemd.timers = lib.pipe cfg.units [
      (map (unit: {
        name = "cronitor-check@${unit}";
        value = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = "*:0/5";
            Persistent = true;
          };
        };
      }))
      builtins.listToAttrs
    ];

    gio.credentials = {
      enable = true;
      services."cronitor-check@".loadCredentialEncrypted = ["cronitor-api-key"];
    };
  };
}
