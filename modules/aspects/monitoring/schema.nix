# Fleet facts for monitoring. `monitor.enable` is the single source of truth:
# it both runs the health-collector on a host and enrolls that host into the
# fleet monitor. `monitor.hub` picks the host that runs the monitor (Gatus).
{lib, ...}: let
  inherit (lib) mkOption types;
in {
  den.schema.host.imports = [
    {
      options.monitor = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Run the health-collector here and enroll this host in the fleet monitor.";
        };
        hub = mkOption {
          type = types.bool;
          default = false;
          description = "Run the fleet monitor (Gatus) on this host, polling every monitor.enable host.";
        };
        alert = mkOption {
          type = types.bool;
          default = true;
          description = "false = dashboard-only (never pages); for hosts expected to be offline, e.g. workstations.";
        };
      };
    }
  ];
}
