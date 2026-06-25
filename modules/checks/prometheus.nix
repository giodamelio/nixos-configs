# Boots a Prometheus host and proves the renderer: declared prometheus-endpoints
# (single + multiple per service) become scrape jobs with the right job names, the
# extraScrapeConfigs escape hatch is appended, and a reachable target scrapes up.
# Targets point at prometheus's own :9090 so they report healthy.
_: {
  perSystem.denTests.prometheus = {
    fleet = _: {
      den.hosts.x86_64-linux.srv = {
        ssh.hostKey = null;
        prometheus.enable = true;
        services = {
          # single endpoint -> job "self" (defaults to the service name)
          self.prometheus-endpoint.target = "localhost:9090";
          # multiple endpoints on one service -> distinct explicit jobs
          multi.prometheus-endpoints = {
            a = {
              target = "localhost:9090";
              job = "multi_a";
            };
            b = {
              target = "localhost:9090";
              job = "multi_b";
            };
          };
        };
      };
      # escape hatch for a non-service job
      fleet.prometheus.extraScrapeConfigs = [
        {
          job_name = "extra";
          static_configs = [{targets = ["localhost:9090"];}];
        }
      ];
      den.aspects.srv.nixos = _: {system.stateVersion = "25.11";};
    };

    nodes.srv = "srv";
    node = _: {pkgs, ...}: {environment.systemPackages = [pkgs.jq pkgs.curl];};

    testScript = ''
      srv.start()
      srv.wait_for_unit("prometheus.service")
      srv.wait_for_open_port(9090)

      api = "curl -sf localhost:9090/api/v1/targets"

      with subtest("declared endpoints render as scrape jobs (single + per-endpoint names + escape hatch)"):
          for job in ["self", "multi_a", "multi_b", "extra"]:
              srv.wait_until_succeeds(
                  f"{api} | jq -e 'any(.data.activeTargets[]; .labels.job==\"{job}\")'"
              )

      with subtest("a reachable target is scraped up"):
          srv.wait_until_succeeds(
              f"{api} | jq -e 'any(.data.activeTargets[]; .labels.job==\"self\" and .health==\"up\")'"
          )
    '';
  };
}
