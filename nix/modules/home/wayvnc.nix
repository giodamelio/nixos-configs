# wayvnc with socket activation and automatic idle shutdown
#
# Architecture:
#   1. wayvnc.socket listens on 127.0.0.1:5900 (starts with sway session)
#   2. VNC connection triggers wayvnc.service via socket activation (-x 3)
#   3. wayvnc.service pulls in wayvnc-idle-shutdown.path
#   4. Path unit watches for %t/wayvncctl (wayvnc's control socket)
#   5. When control socket appears, triggers wayvnc-idle-shutdown.service
#   6. Sidecar monitors wayvnc events via wayvncctl
#   7. When last client disconnects (connection_count == 0), sends wayvnc-exit
#   8. All services stop, socket keeps listening for next connection
{
  pkgs,
  flake,
  ...
}: {
  home.packages = [pkgs.wayvnc];

  systemd.user.sockets.wayvnc = {
    Unit = {
      Description = "VNC server socket";
      BindsTo = ["sway-session.target"];
      After = ["sway-session.target"];
    };
    Socket = {
      ListenStream = "127.0.0.1:5900";
    };
    Install = {
      WantedBy = ["sway-session.target"];
    };
  };

  systemd.user.services.wayvnc = {
    Unit = {
      Description = "VNC server for wlroots-based compositors";
      BindsTo = ["sway-session.target"];
      After = ["sway-session.target"];
      Wants = ["wayvnc-idle-shutdown.path"];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.wayvnc}/bin/wayvnc --render-cursor --log-level=info -x 3";
    };
  };

  systemd.user.paths.wayvnc-idle-shutdown = {
    Unit = {
      Description = "Watch for wayvnc control socket";
      BindsTo = ["wayvnc.service"];
      After = ["wayvnc.service"];
    };
    Path = {
      PathExists = "%t/wayvncctl";
    };
  };

  systemd.user.services.wayvnc-idle-shutdown = {
    Unit = {
      Description = "Shutdown wayvnc when all clients disconnect";
      BindsTo = ["wayvnc.service"];
      After = ["wayvnc.service"];
    };
    Service = {
      Type = "simple";
      ExecStart = let
        script = flake.lib.writeNushellApplication pkgs {
          name = "wayvnc-idle-shutdown";
          runtimeInputs = [pkgs.wayvnc];
          source = ''
            def main [] {
              wayvncctl --wait --json event-receive
                | lines
                | each { from json }
                | where method == "client-disconnected"
                | where params.connection_count == 0
                | each {
                    # Grace period for output cycling (causes brief disconnect)
                    sleep 60sec
                    let clients = (wayvncctl --json client-list | from json | get clients | length)
                    if $clients == 0 {
                      print "All VNC clients disconnected, shutting down wayvnc"
                      wayvncctl wayvnc-exit out+err>| ignore
                    }
                }
                | ignore
            }
          '';
        };
      in "${script}/bin/wayvnc-idle-shutdown";
    };
  };
}
