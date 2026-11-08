{
  lib,
  config,
  ...
}: let
  net = import ../network/_lib.nix {inherit lib;};
  cfg = config.fleet.telemetry;
  domain = config.fleet.dns.domain;
  denHosts = lib.concatMapAttrs (_system: hosts: hosts) config.den.hosts;
  memberAddresses = map (member: net.theAddress denHosts.${member}) cfg.clusterNodes;
in {
  # Manual records, not fleet.services endpoints: those assert one host per
  # domain, and both names round-robin across every member.
  config.fleet.dns.zones.${domain}.subdomains = lib.mkMerge [
    (lib.mkIf cfg.dns.enable {
      telemetry.A = memberAddresses;
      "push.telemetry".A = memberAddresses;
    })
    (lib.mkIf cfg.ui.enable (lib.genAttrs ["vmui" "logs" "alertmanager"] (_: {
      CNAME = ["${cfg.ui.host}.${domain}."];
    })))
  ];
}
