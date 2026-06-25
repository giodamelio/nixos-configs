# Boots a Homer host and proves the renderer: services with a dashboard facet
# become Homer tiles grouped by category, served as config.yml through Caddy. The
# homer vhost is forced to plain HTTP so Caddy starts without a Cloudflare token.
_: {
  perSystem.denTests.homer = {
    fleet = _: {
      den.hosts.x86_64-linux.srv = {
        ssh.hostKey = null;
        homer.enable = true;
        services = {
          mealie.dashboard = {
            category = "Services";
            subtitle = "Recipes";
            url = "https://mealie.gio.ninja";
          };
          jellyfin.dashboard = {
            category = "Media";
            url = "https://jellyfin.gio.ninja";
          };
        };
      };
      fleet.homer.title = "Test Lab";
      den.aspects.srv.nixos = {lib, ...}: {
        system.stateVersion = "25.11";
        # Plain HTTP on :80 so Caddy needs no Cloudflare credential in the test
        # (http with the default :443 would violate Caddy's scheme/port convention).
        services.gio.reverse-proxy.virtualHosts.homer = {
          tls = lib.mkForce false;
          listenPort = lib.mkForce 80;
        };
      };
    };

    nodes.srv = "srv";
    node = _: {pkgs, ...}: {environment.systemPackages = [pkgs.curl];};

    testScript = ''
      srv.start()
      srv.wait_for_unit("caddy.service")
      srv.wait_for_open_port(80)

      cfg = "curl -sS -H 'Host: homer.gio.ninja' http://localhost/assets/config.yml"

      with subtest("dashboards render into the homer config grouped by category"):
          out = srv.wait_until_succeeds(cfg)
          assert "Test Lab" in out, f"title missing: {out!r}"
          for token in ["Services", "Media", "mealie", "jellyfin", "Recipes"]:
              assert token in out, f"{token} missing from homer config: {out!r}"

      with subtest("the homer static site is served"):
          srv.succeed("curl -sSf -H 'Host: homer.gio.ninja' http://localhost/ -o /dev/null")
    '';
  };
}
