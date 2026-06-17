# Boots a gatus host plus a second host and proves the friendly checks option
# renders working Gatus endpoints: http/tcp checks against gatus's own listener go
# healthy, and an icmp (ping) check reaches the other booted host by name (the test
# framework resolves node names via /etc/hosts; NixOS allows ping by default).
_: {
  perSystem.denTests.gatus = {
    fleet = {den, ...}: {
      den.hosts.x86_64-linux.srv.ssh.hostKey = null;
      den.aspects.srv = {
        includes = [den.aspects.gatus];
        nixos = _: {
          system.stateVersion = "25.11";
          gio.gatus = {
            enable = true;
            checks = {
              # http check against gatus's own API (200) -> healthy
              self.url = "http://127.0.0.1:4444/api/v1/config";
              # tcp check against the same port -> healthy
              selfport = {
                type = "tcp";
                host = "127.0.0.1:4444";
              };
              # group + response-time knob
              api = {
                group = "Admin";
                url = "http://127.0.0.1:4444/api/v1/config";
                maxResponseTime = "2s";
              };
              # icmp ping to the other booted host (resolved by node name).
              peer = {
                type = "icmp";
                group = "Hosts";
                host = "peer";
              };
            };
          };
        };
      };

      # A second host for the ping check to reach.
      den.hosts.x86_64-linux.peer.ssh.hostKey = null;
      den.aspects.peer.nixos = _: {system.stateVersion = "25.11";};
    };

    nodes = {
      srv = "srv";
      peer = "peer";
    };
    node = _: {pkgs, ...}: {environment.systemPackages = [pkgs.jq pkgs.curl];};

    testScript = ''
      start_all()
      peer.wait_for_unit("multi-user.target")
      srv.wait_for_unit("gatus.service")
      srv.wait_for_open_port(4444)

      api = "curl -sf localhost:4444/api/v1/endpoints/statuses"

      with subtest("friendly checks render as gatus endpoints"):
          srv.wait_until_succeeds(f"{api} | jq -e 'length >= 4'")
          srv.wait_until_succeeds(f"{api} | jq -e 'any(.[]; .name==\"self\" and .group==\"Services\")'")
          srv.wait_until_succeeds(f"{api} | jq -e 'any(.[]; .name==\"api\" and .group==\"Admin\")'")
          srv.wait_until_succeeds(f"{api} | jq -e 'any(.[]; .name==\"peer\" and .group==\"Hosts\")'")

      with subtest("http + tcp checks report healthy"):
          srv.wait_until_succeeds(
              f"{api} | jq -e 'any(.[]; .name==\"self\" and (.results|length>0) and .results[-1].success==true)'"
          )
          srv.wait_until_succeeds(
              f"{api} | jq -e 'any(.[]; .name==\"selfport\" and (.results|length>0) and .results[-1].success==true)'"
          )

      with subtest("icmp ping to the other host reports healthy"):
          srv.wait_until_succeeds(
              f"{api} | jq -e 'any(.[]; .name==\"peer\" and (.results|length>0) and .results[-1].success==true)'"
          )
    '';
  };
}
