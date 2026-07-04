# fleet-monitor — Gatus on the monitor.hub host, polling the health verdict of
# every monitor.enable host by <hostname>.<domain>, so both static and DHCP hosts
# (desktops/laptops) are reachable. Endpoints derive from den.hosts — no host
# list. In-memory store (the verdict is disposable; alerts are pushed).
{
  lib,
  config,
  ...
}: let
  ports = import ./_lib.nix;
  domain = config.fleet.dns.domain;

  denHosts = lib.concatMapAttrs (_system: hosts: hosts) config.den.hosts;
  monitored = lib.filterAttrs (_n: h: h.monitor.enable) denHosts;
in {
  den.aspects.fleet-monitor.nixos = {
    host,
    lib,
    config,
    ...
  }: let
    inherit (lib) mkOption mkIf types;
    cfg = config.gio.fleet-monitor;

    endpoints =
      lib.mapAttrsToList (name: h: {
        inherit name;
        # alert hosts group together; dashboard-only hosts sit apart (and will
        # get no alerts attached once alerting exists).
        group =
          if h.monitor.alert
          then "servers"
          else "workstations";
        url = "http://${name}.${domain}:${toString ports.healthPort}/";
        inherit (cfg) interval;
        conditions = ["[STATUS] == 200"];
      })
      monitored;
  in {
    options.gio.fleet-monitor = {
      port = mkOption {
        type = types.port;
        default = 8080;
        description = "Web UI / API port for the fleet monitor (Gatus).";
      };
      interval = mkOption {
        type = types.str;
        default = "30s";
        description = "How often to poll each host's health verdict.";
      };
    };

    config = mkIf host.monitor.hub {
      services.gatus = {
        enable = true;
        settings = {
          web.port = cfg.port;
          storage.type = "memory";
          inherit endpoints;
        };
      };

      networking.firewall.allowedTCPPorts = [cfg.port];
    };
  };
}
