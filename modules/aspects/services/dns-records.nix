{
  lib,
  config,
  ...
}: let
  inherit (import ./_types.nix {inherit lib;}) serviceZoneRecords;
  # Only hosts that participate in DNS contribute service records.
  denHosts = lib.filterAttrs (_name: host: host.dns.enable) (lib.concatMapAttrs (_system: hosts: hosts) config.den.hosts);
in {
  # fleet.services builds on fleet.dns: every service endpoint contributes a
  # record into the primary zone. It lands in the same dns.nix `subdomains`
  # option as host records, so the two merge natively.
  config.fleet.dns.zones.${config.fleet.dns.domain}.subdomains = serviceZoneRecords denHosts;
}
