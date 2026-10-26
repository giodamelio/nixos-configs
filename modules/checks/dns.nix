# Boots a den host as the authoritative DNS server and proves the fleet.dns
# aspect end to end: an explicit A record, an explicit CNAME, a host-IP-derived
# A record, and — across TWO dns-serving hosts — that same-name/same-type A
# records from different machines merge into a round-robin ns.<domain>.
_: {
  perSystem.denTests.fleet-dns = {
    fleet = _: {
      # Two hosts both serve DNS; each contributes its IP to ns.gio.ninja.
      den.hosts.x86_64-linux.alpha = {
        ssh.hostKey = null; # enabled hosts must set this (even to null)
        # eth0 won't match the VM's vlan NIC, so the render is inert on hardware
        # while the fact still drives the derived A record.
        network.interfaces.eth0.address = "10.0.0.5"; # -> alpha.gio.ninja A 10.0.0.5
        dns.serve.enable = true;
      };
      den.hosts.x86_64-linux.beta = {
        ssh.hostKey = null;
        network.interfaces.eth0.address = "10.0.0.6";
        dns.serve.enable = true; # only declared (not booted); still contributes records
      };

      # Explicit records in the dns.nix shape, merged with the derived ones.
      fleet.dns.zones."gio.ninja".subdomains = {
        static.A = ["10.0.0.9"];
        ext.CNAME = ["external.example."];
        "*.wild".CNAME = ["static.gio.ninja."];
      };

      den.aspects.alpha.nixos = _: {system.stateVersion = "25.11";};
      den.aspects.beta.nixos = _: {system.stateVersion = "25.11";};
    };

    nodes.alpha = "alpha";
    node = _: {pkgs, ...}: {environment.systemPackages = [pkgs.dnsutils];};

    testScript = ''
      alpha.start()
      alpha.wait_for_unit("coredns.service")
      alpha.wait_for_open_port(53)

      with subtest("explicit A record resolves"):
          alpha.succeed("dig +short @127.0.0.1 static.gio.ninja A | grep -x 10.0.0.9")

      with subtest("a host's network address becomes an A record"):
          alpha.succeed("dig +short @127.0.0.1 alpha.gio.ninja A | grep -x 10.0.0.5")

      with subtest("explicit CNAME resolves"):
          alpha.succeed("dig +short @127.0.0.1 ext.gio.ninja CNAME | grep -x external.example.")

      with subtest("a wildcard CNAME answers any name under it"):
          for name in ("auth", "notes"):
              alpha.succeed(f"dig +short @127.0.0.1 {name}.wild.gio.ninja A | grep -x 10.0.0.9")

      with subtest("ns.<domain> round-robins across all dns-serving hosts"):
          out = alpha.succeed("dig +short @127.0.0.1 ns.gio.ninja A")
          addrs = set(out.split())
          assert addrs == {"10.0.0.5", "10.0.0.6"}, f"expected both ns IPs, got {addrs!r}"

      with subtest("TTLs in the fleet zone are capped at 60s"):
          ttl = int(alpha.succeed("dig +noall +answer @127.0.0.1 static.gio.ninja A | awk '{print $2}'").strip())
          assert ttl <= 60, f"expected TTL <= 60, got {ttl}"

      # What `fleet-dns push` does: atomically replace the live zone with one
      # carrying a new record and a new serial.
      zone = "/var/lib/fleet-dns/gio.ninja.zone"
      alpha.succeed(
          f"sed -E 's/\\(([0-9]+) /(4242 /' {zone} > /tmp/pushed.zone",
          "echo 'pushed.gio.ninja. IN A 10.0.0.42' >> /tmp/pushed.zone",
          f"mv -f /tmp/pushed.zone {zone}",
      )

      with subtest("a pushed zone is served without restarting coredns"):
          alpha.wait_until_succeeds("dig +short @127.0.0.1 pushed.gio.ninja A | grep -x 10.0.0.42", timeout=30)

      with subtest("re-running an unchanged deploy keeps the pushed zone"):
          out = alpha.succeed("/run/current-system/activate 2>&1")
          assert "zones unchanged since the last deploy" in out, out
          alpha.sleep(12)
          alpha.succeed("dig +short @127.0.0.1 pushed.gio.ninja A | grep -x 10.0.0.42")
    '';
  };
}
