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
        dns.ip = "10.0.0.5"; # -> alpha.gio.ninja A 10.0.0.5 (derived)
        dns.serve.enable = true;
      };
      den.hosts.x86_64-linux.beta = {
        ssh.hostKey = null;
        dns.ip = "10.0.0.6";
        dns.serve.enable = true; # only declared (not booted); still contributes records
      };

      # Explicit records in the dns.nix shape, merged with the derived ones.
      fleet.dns.zones."gio.ninja".subdomains = {
        static.A = ["10.0.0.9"];
        ext.CNAME = ["external.example."];
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

      with subtest("a host's dns.ip becomes an A record"):
          alpha.succeed("dig +short @127.0.0.1 alpha.gio.ninja A | grep -x 10.0.0.5")

      with subtest("explicit CNAME resolves"):
          alpha.succeed("dig +short @127.0.0.1 ext.gio.ninja CNAME | grep -x external.example.")

      with subtest("ns.<domain> round-robins across all dns-serving hosts"):
          out = alpha.succeed("dig +short @127.0.0.1 ns.gio.ninja A")
          addrs = set(out.split())
          assert addrs == {"10.0.0.5", "10.0.0.6"}, f"expected both ns IPs, got {addrs!r}"
    '';
  };
}
