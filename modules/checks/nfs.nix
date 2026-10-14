# End-to-end fleet.nfs test on real den hosts: nfs-a exports to nfs-b over NFS
# with mutual TLS (tlshd). nfs-c is an intruder holding a valid certificate from
# the same CA but not listed as a client, so the per-client export and firewall
# rule must keep it out. Certificates come from a throwaway CA and are dropped
# where nfs-cert-enroll would leave them (enrollment is covered by nfs-cert.nix).
# Also proves the fleet.services -> nfs-wait bridge binds a service to its mount.
_: {
  perSystem = {
    pkgs,
    lib,
    ...
  }: let
    hosts = ["nfs-a" "nfs-b" "nfs-c"];
    pki = pkgs.runCommand "fleet-nfs-test-pki" {nativeBuildInputs = [pkgs.openssl];} ''
      mkdir $out && cd $out
      openssl ecparam -name prime256v1 -genkey -noout -out ca.key
      openssl req -new -x509 -sha256 -key ca.key -out ca.crt -subj "/CN=fleet-nfs test CA" -days 36500
      for h in ${toString hosts}; do
        openssl ecparam -name prime256v1 -genkey -noout -out $h.key
        openssl req -new -sha256 -key $h.key -out $h.csr -subj "/CN=$h.gio.ninja"
        printf 'subjectAltName=DNS:%s.gio.ninja,DNS:%s\nextendedKeyUsage=serverAuth,clientAuth\n' $h $h > $h.ext
        openssl x509 -req -in $h.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
          -out $h.crt -days 36500 -sha256 -extfile $h.ext
      done
    '';
    # The test driver numbers vlan addresses by sorted node name (nfsa, nfsb,
    # nfsc), so these match the VMs' real eth1 addresses.
    addressOf = {
      nfs-a = "192.168.1.1";
      nfs-b = "192.168.1.2";
      nfs-c = "192.168.1.3";
    };
    # The driver's own IPv6 addresses, which its /etc/hosts entries already use.
    ulaOf = {
      nfs-a = "2001:db8:1::1";
      nfs-b = "2001:db8:1::2";
      nfs-c = "2001:db8:1::3";
    };
  in {
    denTests.fleet-nfs = {
      fleet = _: {
        den.hosts.x86_64-linux =
          lib.recursiveUpdate (lib.genAttrs hosts (h: {
            ssh.hostKey = null;
            nfs.enable = true;
            network.interfaces.eth1 = {
              address = addressOf.${h};
              ula = "${ulaOf.${h}}/64";
            };
          })) {
            nfs-b.services.demo-consumer = {
              unit = "demo-consumer";
              mounts = ["demo"];
            };
          };

        fleet.nfs.caRoot = "${pki}/ca.crt";
        # Fluent chain: server nfs-a:/srv/demo -> client nfs-b:/mnt/demo.
        fleet.nfs.mounts.demo.nfs-a."/srv/demo".nfs-b."/mnt/demo" = {};

        den.aspects.nfs-a.nixos = _: {
          system.stateVersion = "25.11";
          # all_squash maps client writes to the nfs-demo anon uid/gid, so the
          # export source must be writable by it.
          system.activationScripts.demoExport = "install -d -m 0777 /srv/demo";
        };
        den.aspects.nfs-b.nixos = _: {
          system.stateVersion = "25.11";
          systemd.services.demo-consumer.serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${pkgs.coreutils}/bin/true";
          };
        };
        den.aspects.nfs-c.nixos = _: {
          system.stateVersion = "25.11";
          # Not a fleet client, but it needs the NFS client stack to try.
          boot.supportedFilesystems = ["nfs"];
        };
      };

      nodes = {
        nfsa = "nfs-a";
        nfsb = "nfs-b";
        nfsc = "nfs-c";
      };

      node = vmName: {
        nodes,
        lib,
        ...
      }: {
        networking.nftables.enable = true;
        # AAAA records too, as the real zone has: mount.nfs prefers them, while
        # exports and the firewall are IPv4-only.
        networking.extraHosts = lib.mkAfter ''
          ${nodes.nfsa.networking.primaryIPAddress} nfs-a nfs-a.gio.ninja
          ${nodes.nfsb.networking.primaryIPAddress} nfs-b nfs-b.gio.ninja
          ${nodes.nfsc.networking.primaryIPAddress} nfs-c nfs-c.gio.ninja
          ${ulaOf.nfs-a} nfs-a nfs-a.gio.ninja
          ${ulaOf.nfs-b} nfs-b nfs-b.gio.ninja
          ${ulaOf.nfs-c} nfs-c nfs-c.gio.ninja
        '';
        # Stand-in for a completed nfs-cert-enroll. The VM's hostname is the
        # node name (nfsa), so map it back to the den host.
        system.activationScripts.nfsTestCert = let
          h =
            {
              nfsa = "nfs-a";
              nfsb = "nfs-b";
              nfsc = "nfs-c";
            }.${
              vmName
            };
        in ''
          install -D -m 0644 ${pki}/${h}.crt /var/lib/step-nfs/cert.pem
          install -D -m 0600 ${pki}/${h}.key /var/lib/step-nfs/key.pem
        '';
      };

      testScript = ''
        start_all()
        for m, addr in ((nfsa, "${addressOf.nfs-a}"), (nfsb, "${addressOf.nfs-b}"), (nfsc, "${addressOf.nfs-c}")):
            m.wait_for_unit("multi-user.target")
            m.wait_for_unit("tlshd.service")
            # The exports and firewall are rendered from addressOf; catch the
            # driver ever numbering the vlan differently.
            assert f"{addr}/" in m.succeed("ip -4 -o addr show eth1"), f"{m.name} is not {addr}"

        with subtest("the server's name resolves to IPv6 first, as on the real LAN"):
            first = nfsb.succeed("getent ahosts nfs-a.gio.ninja | head -1").split()[0]
            assert ":" in first, f"nfs-a.gio.ninja resolves to {first} first"

        with subtest("the export is restricted to the client's address and requires mTLS"):
            nfsa.wait_for_unit("nfs-server.service")
            print(nfsa.execute("journalctl -b -u nfs-server.service --no-pager | tail -20")[1])
            exports = nfsa.succeed("exportfs -v")
            assert "192.168.1.2" in exports and "xprtsec=mtls" in exports, exports
            assert "192.168.1.3" not in exports, exports
            nfsa.succeed("echo fleet-nfs-ok > /srv/demo/hello")

        def probe(m, sec):
            """Try to reach the share's data without the expected transport.
            Returns whether a file could be read; the mount call alone can
            succeed on NFSv4 through the pseudo-root."""
            m.succeed("mkdir -p /mnt/probe")
            # nosharecache: otherwise the kernel hands back the superblock of any
            # existing mount of the same export, with its xprtsec, ignoring ours.
            # proto=tcp so the export ACL is what refuses, not the IPv6 firewall.
            rc, out = m.execute(
                f"timeout 60 mount -t nfs -o nfsvers=4.2,proto=tcp,nosharecache,xprtsec={sec} "
                "nfs-a.gio.ninja:/srv/demo /mnt/probe 2>&1"
            )
            if rc != 0:
                print(f"{m.name} xprtsec={sec}: mount refused (rc={rc}): {out.strip()}")
                return False
            rc, out = m.execute("timeout 30 cat /mnt/probe/hello 2>&1")
            print(f"{m.name} xprtsec={sec}: mounted; read rc={rc}: {out.strip()}")
            print(m.execute("grep ' /mnt/probe ' /proc/mounts")[1])
            m.execute("umount -f -l /mnt/probe")
            return rc == 0

        # The real mount may already be up from boot; take it down so the probes
        # get fresh NFS client state rather than its mTLS transport.
        with subtest("the export refuses the listed client without a client certificate"):
            nfsb.succeed("systemctl stop mnt-demo.mount")
            nfsb.fail("mountpoint -q /mnt/demo")
            leaks = [sec for sec in ("none", "tls") if probe(nfsb, sec)]
            assert not leaks, f"share data readable with xprtsec={leaks}"

        with subtest("the client mounts over mutual TLS and read/write works"):
            # reset-failed clears any start-limit from boot-time attempts made
            # before the server was up.
            nfsb.wait_until_succeeds(
                "systemctl reset-failed mnt-demo.mount 2>/dev/null; "
                "systemctl start mnt-demo.mount && mountpoint -q /mnt/demo"
            )
            assert "xprtsec=mtls" in nfsb.succeed("grep ' /mnt/demo ' /proc/mounts")
            got = nfsb.succeed("cat /mnt/demo/hello").strip()
            assert got == "fleet-nfs-ok", f"client read {got!r}"

        with subtest("ownership squashes to the deterministic nfs-demo user on both hosts"):
            uid = nfsb.succeed("id -u nfs-demo").strip()
            assert nfsa.succeed("id -u nfs-demo").strip() == uid, "nfs-demo uid differs across hosts"
            nfsb.succeed("echo from-client > /mnt/demo/cf")
            assert nfsa.succeed("stat -c '%U:%G' /srv/demo/cf").strip() == "nfs-demo:nfs-demo"
            assert nfsb.succeed("stat -c '%U:%G' /mnt/demo/cf").strip() == "nfs-demo:nfs-demo"
            assert nfsb.succeed("stat -c '%u' /mnt/demo/cf").strip() == uid

        with subtest("restarting tlshd (as renewal does) keeps the established mount working"):
            nfsa.succeed("systemctl restart tlshd.service")
            nfsb.succeed("systemctl restart tlshd.service")
            nfsb.succeed("echo after-restart > /mnt/demo/ar")
            assert nfsa.succeed("cat /srv/demo/ar").strip() == "after-restart"

        with subtest("an unlisted host with a valid certificate is kept out"):
            assert not probe(nfsc, "mtls"), "unlisted host read the share"

        with subtest("the nfs-wait bridge binds demo-consumer to the mount"):
            props = nfsb.succeed("systemctl show -p After -p BindsTo demo-consumer.service")
            assert "nfs-demo.target" in props, props
            nfsb.succeed("systemctl start demo-consumer.service")
            nfsb.succeed("systemctl is-active demo-consumer.service")
            nfsb.succeed("systemctl stop mnt-demo.mount")
            nfsb.wait_until_fails("systemctl is-active demo-consumer.service")
      '';
    };
  };
}
