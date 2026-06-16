# Boots a single-node Consul host and proves the cluster + registration render
# path end to end: the agent forms (gossip key delivered via fleet.secrets,
# generated locally on this origin), an on-by-default service lands in the
# catalog, `consul.enable = false` opts a service out, and a check derived from
# the healthcheck facet is registered and passing.
_: {
  perSystem.denTests.consul = {
    fleet = _: {
      den.hosts.x86_64-linux.srv = {
        ssh.hostKey = null;
        consul.enable = true;
        # eth0 is the VM's primary NIC; static-network gives it this address and
        # consul binds to it (theInterface). A real device (not lo) is required —
        # consul's unit waits on sys-subsystem-net-devices-<iface>.device.
        network.interfaces.eth0.address = "10.99.0.1";
        services = {
          # On by default. A tcp check at consul's own port, so it actually passes.
          demo.healthcheck = {
            protocol = "tcp";
            target = "127.0.0.1:8500";
          };
          # Opted out of Consul registration.
          skip = {
            consul.enable = false;
            healthcheck = {
              protocol = "tcp";
              target = "127.0.0.1:8500";
            };
          };
        };
      };

      den.aspects.srv.nixos = {pkgs, ...}: {
        system.stateVersion = "25.11";
        nixpkgs.config.allowUnfree = true; # consul is unfree (HashiCorp BSL)
        environment.systemPackages = [pkgs.consul];
      };
    };

    nodes.srv = "srv";
    node = _: {pkgs, ...}: {environment.systemPackages = [pkgs.jq pkgs.curl];};

    testScript = ''
      srv.start()
      srv.wait_for_unit("consul.service")
      srv.wait_for_open_port(8500)
      srv.wait_until_succeeds("consul members | grep -qw srv")

      with subtest("on-by-default service is registered in the catalog"):
          srv.wait_until_succeeds("consul catalog services | grep -qx demo")

      with subtest("consul.enable = false opts a service out"):
          srv.fail("consul catalog services | grep -qx skip")

      with subtest("the check derived from the healthcheck facet is registered and passing"):
          srv.wait_until_succeeds(
              "curl -sf localhost:8500/v1/health/checks/demo | jq -e '.[0].Status == \"passing\"'"
          )
    '';
  };
}
