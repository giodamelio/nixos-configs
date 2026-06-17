{lib}: rec {
  # denHosts -> [{ host, name, <all service facets...> }]
  servicesOf = denHosts:
    lib.pipe denHosts [
      (lib.mapAttrsToList (hostName: host:
        lib.mapAttrsToList (svcName: svc:
          {
            host = hostName;
            name = svcName;
          }
          // svc)
        (host.services or {})))
      lib.flatten
    ];

  # Flatten one plural facet across every service, tagging each instance with
  # its owning host, service, and key. denHosts -> [{ host, service, key, <facet fields> }]
  facetEntries = plural: denHosts:
    lib.pipe (servicesOf denHosts) [
      (map (svc:
        lib.mapAttrsToList (key: val:
          {
            inherit (svc) host;
            service = svc.name;
            inherit key;
          }
          // val)
        (svc.${plural} or {})))
      lib.flatten
    ];

  endpointsOf = facetEntries "endpoints";
  healthchecksOf = facetEntries "healthchecks";
  prometheusEndpointsOf = facetEntries "prometheus-endpoints";
  dashboardsOf = facetEntries "dashboards";

  # Service endpoints as a dns.nix `subdomains` fragment: { <domain> = ...; }.
  # When the owning host is static the domain gets A records straight to its
  # address(es); otherwise a CNAME to "<host>.lan." (resolved upstream). This is
  # how fleet.services contributes to fleet.dns.zones.
  serviceZoneRecords = denHosts: let
    net = import ../network/_lib.nix {inherit lib;};
    recordFor = ep: let
      addrs = net.addressesOf (denHosts.${ep.host} or {});
    in {
      name = ep.domain;
      value =
        if addrs != []
        then {A = addrs;}
        else {CNAME = ["${ep.host}.lan."];};
    };
  in
    builtins.listToAttrs (map recordFor (endpointsOf denHosts));

  # All declared prometheus-endpoints across the fleet -> prometheus scrapeConfigs,
  # grouped by job (one scrape_config per job, a static_config per declaring host).
  scrapeConfigsOf = denHosts: let
    l = import ./_lib.nix {inherit lib;};
  in
    lib.mapAttrsToList l.scrapeConfigOf (lib.groupBy (e: e.job) (prometheusEndpointsOf denHosts));

  # All declared dashboards across the fleet -> homer `services` groups (one group
  # per category, items in declaration order).
  homerServicesOf = denHosts: let
    l = import ./_lib.nix {inherit lib;};
  in
    lib.mapAttrsToList l.homerGroupOf (lib.groupBy (d: d.category) (dashboardsOf denHosts));
}
