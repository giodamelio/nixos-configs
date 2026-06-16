# Proves the fleet.services registry cross-host: a service declared on one host
# (app-host, never booted) renders into the DNS zone served by another (ns), and
# resolves there. Exercises the singular `endpoint` sugar + domain-defaults-to-
# service-name + the services->dns record bridge.
_: {
  perSystem.denTests.fleet-services = {
    fleet = _: {
      # Producer: declares a service exercising every facet (singular sugar).
      # Only the endpoint affects DNS; the rest is data for future consumers, so
      # declaring it here proves the full schema evaluates in a real fleet.
      den.hosts.x86_64-linux.app-host = {
        ssh.hostKey = null;
        network.interfaces.eth0.address = "10.0.0.10"; # so the service domain promotes to an A record
        services.app = {
          description = "demo app exercising all facets";
          endpoint = {
            backend.port = 8080; # domain defaults to "app"
            mtls = false;
            extraConfig = "encode gzip";
          };
          healthcheck = {
            target = "https://app.gio.ninja/healthz";
            expect.status = [200];
            expect.maxResponseTime = "500ms";
          };
          prometheus-endpoint = {
            target = "app.gio.ninja";
            scheme = "https";
            path = "/metrics";
          };
          dashboard = {
            category = "Services";
            subtitle = "demo";
            url = "https://app.gio.ninja";
          };
          consul.port = 443;
        };
      };

      # Consumer: the DNS server, which folds app-host's service record into its
      # zone purely by reading the fleet registry.
      den.hosts.x86_64-linux.ns = {
        ssh.hostKey = null;
        dns.serve.enable = true;
      };

      den.aspects.app-host.nixos = _: {system.stateVersion = "25.11";};
      den.aspects.ns.nixos = _: {system.stateVersion = "25.11";};
    };

    # Only the DNS host boots; the producer's data arrives through the registry.
    nodes.ns = "ns";
    node = _: {pkgs, ...}: {environment.systemPackages = [pkgs.dnsutils];};

    testScript = ''
      ns.start()
      ns.wait_for_unit("coredns.service")
      ns.wait_for_open_port(53)

      with subtest("a service declared on app-host resolves via the DNS host"):
          ns.succeed("dig +short @127.0.0.1 app.gio.ninja A | grep -x 10.0.0.10")
    '';
  };
}
