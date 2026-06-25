{
  lib,
  config,
  ...
}: let
  inherit (import ./_types.nix {inherit lib;}) hostARecords;
  net = import ../network/_lib.nix {inherit lib;};
  domain = config.fleet.dns.domain;

  # Only hosts that participate in DNS contribute records.
  denHosts = lib.filterAttrs (_name: host: host.dns.enable) (lib.concatMapAttrs (_system: hosts: hosts) config.den.hosts);

  # ns.<domain> round-robins across every host that serves DNS (and has a static
  # address), matching the default SOA/NS nameserver name. Multiple hosts
  # contributing an A record to the same name is the dns.nix list-merge in action.
  nsIPs = net.dnsServerAddresses denHosts;
in {
  # Fold host-derived records into the primary zone (service-endpoint records
  # are contributed separately by the fleet.services aspect, which merges into
  # the same dns.nix `subdomains` option). SOA/NS are mkDefault so a consumer can
  # override but never has to supply them.
  config.fleet.dns.zones.${domain} = {
    SOA = lib.mkDefault {
      nameServer = "ns.${domain}.";
      adminEmail = "hostmaster@${domain}";
      serial = 1;
    };
    NS = lib.mkDefault ["ns.${domain}."];
    subdomains = lib.mkMerge [
      (hostARecords denHosts)
      (lib.optionalAttrs (nsIPs != []) {ns.A = nsIPs;})
    ];
  };
}
