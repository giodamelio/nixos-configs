{lib}: rec {
  # A healthcheck facet entry -> a Consul check. ICMP has no Consul equivalent,
  # so it yields null and is filtered out.
  healthcheckToCheck = hc:
    if hc.protocol == "tcp"
    then {
      tcp = hc.target;
      inherit (hc) interval;
    }
    else if hc.protocol == "http" || hc.protocol == "https"
    then {
      http = hc.target;
      inherit (hc) interval method;
    }
    else null;

  # The service's primary endpoint (the one consul/derivations key off): the
  # `default` key (singular sugar) if present, else the first declared, else null.
  primaryEndpoint = svc: let
    eps = svc.endpoints or {};
  in
    eps.default or (
      if eps != {}
      then lib.head (lib.attrValues eps)
      else null
    );

  # Derive a service's Consul registration (a service object for consul.d JSON),
  # or null when registration is disabled. zone is the fleet DNS domain.
  consulRegistration = zone: svc: let
    primary = primaryEndpoint svc;
    address =
      if svc.consul.address != null
      then svc.consul.address
      else if primary != null
      then "${primary.domain}.${zone}"
      else "${svc.consul.name}.${zone}";
    port =
      if svc.consul.port != null
      then svc.consul.port
      else if primary != null
      then primary.port
      else 443;
    checks = lib.filter (c: c != null) (map healthcheckToCheck (lib.attrValues (svc.healthchecks or {})));
  in
    if !svc.consul.enable
    then null
    else
      {
        inherit (svc.consul) name tags meta;
        inherit address port;
      }
      // lib.optionalAttrs (checks != []) {inherit checks;};

  # Every enabled registration on a set of services (host.services), filtered.
  consulRegistrationsOf = zone: services:
    lib.filter (r: r != null) (lib.mapAttrsToList (_name: consulRegistration zone) services);

  # Endpoint domains declared more than once across a set of endpoint entries.
  # Each domain maps to exactly one DNS record and one Caddy vhost, so a duplicate
  # would silently drop one (both keyed by domain via listToAttrs). Used by the
  # fleet-wide uniqueness assertion.
  duplicateDomains = endpoints: let
    domains = map (e: e.domain) endpoints;
  in
    lib.unique (lib.filter (d: lib.count (x: x == d) domains > 1) domains);

  # Does an endpoint serve anything (vs. being a DNS-only record)? A vhost is
  # emitted when it auto-proxies or carries custom Caddy directives.
  endpointServes = ep: ep.proxy || ep.extraConfig != "";

  # An endpoint facet entry -> a `services.gio.reverse-proxy.virtualHosts` value.
  # `port` is the BACKEND port (matches the reverse-proxy aspect + deployed-apps);
  # `listenPort` is the public one. The aspect renders Caddy TLS + directives.
  endpointToVHost = ep: {
    inherit (ep) domain extraConfig tls;
    listenPort = ep.port;
    reverseProxy = ep.proxy;
    protocol = ep.backend.protocol;
    host = ep.backend.host;
    port = ep.backend.port;
    socket_path = ep.backend.socket;
  };

  # A prometheus `job` name + its prometheus-endpoint entries -> one prometheus
  # scrape_config. Entries sharing a job become multiple static_configs (the same
  # exporter across several hosts). Job-level fields (metrics_path/scheme/params/
  # authorization) come from the first entry — entries in one job share them.
  scrapeConfigOf = job: entries: let
    head = lib.head entries;
    mkAuth = a:
      {type = "Bearer";}
      // lib.optionalAttrs (a.credentials != null) {inherit (a) credentials;}
      // lib.optionalAttrs (a.credentialsFile != null) {credentials_file = a.credentialsFile;};
    mkStatic = e: {targets = [e.target];} // lib.optionalAttrs (e.labels != {}) {inherit (e) labels;};
  in
    {
      job_name = job;
      static_configs = map mkStatic entries;
    }
    // lib.optionalAttrs (head.path != "/metrics") {metrics_path = head.path;}
    // lib.optionalAttrs (head.scheme != "http") {inherit (head) scheme;}
    // lib.optionalAttrs (head.params != {}) {inherit (head) params;}
    // lib.optionalAttrs (head.auth != null) {authorization = mkAuth head.auth;};

  # A dashboard facet entry -> a homer item (subtitle/logo only when set).
  dashboardToItem = d:
    {
      name = d.title;
      inherit (d) url;
    }
    // lib.optionalAttrs (d.subtitle != null) {inherit (d) subtitle;}
    // lib.optionalAttrs (d.logo != null) {inherit (d) logo;};

  # A category + its dashboard entries -> a homer service group.
  homerGroupOf = category: entries: {
    name = category;
    items = map dashboardToItem entries;
  };
}
