# keyd — capslock as control-when-held / escape-when-tapped (and esc becomes
# capslock). Converted from nix/modules/nixos/keyd.nix. cesium carries its own
# Chromebook-specific keyd config in its host aspect instead of this one.
_: {
  den.aspects.keyd.nixos = {lib, ...}: {
    services.keyd = {
      enable = true;

      keyboards.default = {
        ids = ["*"];
        settings = {
          main = {
            # Make capslock be control when held and escape when tapped
            capslock = "overload(control, esc)";

            # Make esc be capslock
            esc = "capslock";
          };
        };
      };
    };

    # keyd only opens its control socket to this group; the app mapper needs it
    users.groups.keyd = {};

    # keyd 2.6.0's daemon setgid()s to the keyd group so the control socket is
    # group-owned (ipc.c:chgid). The upstream module's hardening forbids that
    # call three ways, so the daemon exits with "setgid: Operation not
    # permitted" the moment the keyd group exists. Re-permit just setgid.
    systemd.services.keyd.serviceConfig = {
      CapabilityBoundingSet = lib.mkForce ["CAP_SYS_NICE" "CAP_IPC_LOCK" "CAP_SETGID"];
      RestrictSUIDSGID = lib.mkForce false;
      SystemCallFilter = lib.mkForce ["nice" "@system-service" "~@privileged" "setgid" "setgid32"];
    };
  };

  den.aspects.keyd.user.extraGroups = ["keyd"];

  den.aspects.keyd.homeManager = {pkgs, ...}: {
    # Games run inside gamescope, so niri reports the focused app-id as
    # "gamescope" (not raft-exe). Keep the caps<->esc swap but drop the
    # overload, so capslock is a plain escape in-game and never fires crouch.
    # Raft launched without gamescope reports its Steam app-id under Xwayland
    # and raft-exe under GE-Proton's Wine-Wayland.
    xdg.configFile."keyd/app.conf".text = ''
      [gamescope]
      capslock = esc
      esc = capslock

      [steam-app-648800]
      capslock = esc
      esc = capslock

      [raft-exe]
      capslock = esc
      esc = capslock
    '';

    systemd.user.services.keyd-application-mapper = {
      Unit = {
        Description = "keyd per-application key remapping";
        PartOf = ["graphical-session.target"];
        After = ["graphical-session.target"];
      };
      Service = {
        ExecStart = "${pkgs.keyd}/bin/keyd-application-mapper";
        # The mapper shells out to a bare `keyd` on every window change; it
        # isn't on the user unit's PATH, so point it at the absolute binary.
        Environment = ["KEYD_BIN=${pkgs.keyd}/bin/keyd"];
        Restart = "on-failure";
      };
      Install.WantedBy = ["graphical-session.target"];
    };
  };
}
