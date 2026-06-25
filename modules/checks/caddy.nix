# Boots one den host running two independent Caddy modular-service instances over
# plain HTTP (so no Cloudflare token / ACME is needed) plus a disabled third, and
# proves: each instance is its own caddy-<name>.service process, vhosts +
# reverse_proxy render and serve, a disabled instance never runs, the config lands
# in /etc via the framework's configData, and the instances keep separate state
# dirs. Per-instance plugin builds (caddy.withPlugins) are not exercised — a real
# plugin build is too costly for a VM test; package-override capability is covered
# structurally by each instance importing the service independently.
_: {
  perSystem.denTests.caddy = {
    fleet = {den, ...}: {
      den.hosts.x86_64-linux.web.ssh.hostKey = null;
      den.aspects.web = {
        includes = [den.aspects.caddy];
        nixos = {pkgs, ...}: {
          system.stateVersion = "25.11";

          # A TCP upstream for the beta instance's reverse_proxy.
          systemd.services.upstream = {
            wantedBy = ["multi-user.target"];
            serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 -m http.server 9000 --bind 127.0.0.1 --directory ${pkgs.writeTextDir "index.html" "beta-upstream-ok"}";
          };

          gio.caddy.instances = {
            alpha.virtualHosts."http://alpha.test:8080".extraConfig = ''respond "alpha-ok" 200'';
            beta.virtualHosts."http://beta.test:8081".extraConfig = "reverse_proxy 127.0.0.1:9000";
            off = {
              enable = false;
              virtualHosts."http://off.test:8082".extraConfig = ''respond "should-never-run" 200'';
            };
          };
        };
      };
    };

    nodes.web = "web";
    node = _: {pkgs, ...}: {environment.systemPackages = [pkgs.curl];};

    testScript = ''
      web.start()
      web.wait_for_unit("upstream.service")
      web.wait_for_unit("caddy-alpha.service")
      web.wait_for_unit("caddy-beta.service")
      web.wait_for_open_port(8080)
      web.wait_for_open_port(8081)

      def get(host, port):
          return web.succeed(f"curl -sS -H 'Host: {host}' http://localhost:{port}/")

      with subtest("each instance is its own process serving its own vhost"):
          assert "alpha-ok" in get("alpha.test", 8080), "alpha instance failed"
          assert "beta-upstream-ok" in get("beta.test", 8081), "beta reverse_proxy failed"

      with subtest("disabled instance never runs"):
          web.fail("systemctl is-active caddy-off.service")

      with subtest("config is materialised in /etc via configData"):
          web.succeed("test -e /etc/system-services/caddy-alpha/caddy_config")

      with subtest("instances have separate state directories"):
          web.succeed("test -d /var/lib/caddy-alpha")
          web.succeed("test -d /var/lib/caddy-beta")
          web.fail("test -d /var/lib/caddy-off")
    '';
  };
}
