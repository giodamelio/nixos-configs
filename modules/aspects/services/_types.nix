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
  consulRegistrationsOf = facetEntries "consuls";

  # Service endpoints as a dns.nix `subdomains` fragment: { <domain> = ...; }.
  # When the owning host has a known IP the domain gets an A record straight to
  # it; otherwise a CNAME to "<host>.lan." (resolved upstream). This is how
  # fleet.services contributes to fleet.dns.zones.
  serviceZoneRecords = denHosts: let
    recordFor = ep: let
      ip = (denHosts.${ep.host} or {}).dns.ip or null;
    in {
      name = ep.domain;
      value =
        if ip != null
        then {A = [ip];}
        else {CNAME = ["${ep.host}.lan."];};
    };
  in
    builtins.listToAttrs (map recordFor (endpointsOf denHosts));
}
