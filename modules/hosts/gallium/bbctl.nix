# Self-hosted Beeper bridges, one bridge-manager container per bridge sharing /var/lib/bbctl.
# REMIND-ME-TO: Delete gallium's old bbctrl-* user units and ~server/.local/share/bbctl date_passed=2026-12-08
{inputs, ...}: {
  den.aspects.gallium.nixos = {
    lib,
    pkgs,
    ...
  }: let
    bridges = [
      "sh-bluesky"
      "sh-discord"
      "sh-googlemessages"
      "sh-instagram"
      "sh-signal"
      "sh-whatsapp"
    ];

    id = 2400;
    image = "ghcr.io/beeper/bridge-manager:latest";
    unitOf = bridge: "bbctl-${bridge}";

    refresh = pkgs.writeShellApplication {
      name = "bbctl-refresh";
      runtimeInputs = [pkgs.podman pkgs.systemd];
      # bbctl only checks mau.dev CI for new bridge builds on start, so restart even when the image is unchanged.
      text = ''
        podman pull ${image}
        systemctl restart ${lib.concatMapStringsSep " " (b: "${unitOf b}.service") bridges}
        podman image prune -f
      '';
    };
  in {
    imports = [inputs.quadlet-nix.nixosModules.quadlet];

    users.users.bbctl = {
      isSystemUser = true;
      uid = id;
      group = "bbctl";
    };
    users.groups.bbctl.gid = id;

    systemd.tmpfiles.rules = ["d /var/lib/bbctl 0700 bbctl bbctl -"];

    fleet.credentials.needs = ["bbctl_env"];

    virtualisation.quadlet = {
      autoEscape = true;
      containers = lib.genAttrs' bridges (bridge:
        lib.nameValuePair (unitOf bridge) {
          autoStart = true;
          containerConfig = {
            inherit image;
            exec = bridge;
            user = "${toString id}:${toString id}";
            volumes = ["/var/lib/bbctl:/data"];
            # The image has no home directory for an arbitrary uid.
            environments.HOME = "/data";
            # podman reads --env-file at ExecStart, after this unit's credentials exist.
            environmentFiles = ["/run/credentials/${unitOf bridge}.service/bbctl_env"];
          };
          serviceConfig = {
            LoadCredentialEncrypted = ["bbctl_env"];
            Restart = "always";
            RestartSec = "10s";
          };
        });
    };

    systemd.services.bbctl-refresh = {
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe refresh;
      };
    };

    systemd.timers.bbctl-refresh = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "*-*-* 04:00";
        Persistent = true;
      };
    };
  };
}
