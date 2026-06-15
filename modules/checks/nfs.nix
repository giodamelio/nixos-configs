# End-to-end fleet.nfs test on real den hosts: nfs-a (server) and nfs-b (client)
# both join the WireGuard mesh. fleet.secrets generates each host's WG keypair and
# credsync pushes the public keys to the peer; once delivered, wg-nfs.service
# brings up the tunnel and the NFS mount comes up over it. Also proves the
# fleet.services -> nfs-wait bridge (a service waits on the mount's target).
_: {
  perSystem = {config, ...}: {
    denTests.fleet-nfs = {
      fleet = _: {
        den.hosts.x86_64-linux.nfs-a = {
          ssh.hostKey = null;
          nfs = {
            enable = true;
            wgIp = "10.200.0.1";
          };
        };
        den.hosts.x86_64-linux.nfs-b = {
          ssh.hostKey = null;
          nfs = {
            enable = true;
            wgIp = "10.200.0.2";
          };
          # Exercises the nfs-wait bridge: this unit must wait for the mount.
          services.demo-consumer = {
            unit = "demo-consumer";
            mounts = ["demo"];
          };
        };

        # Fluent chain: server nfs-a:/srv/demo -> client nfs-b:/mnt/demo.
        fleet.nfs.mounts.demo.nfs-a."/srv/demo".nfs-b."/mnt/demo" = {};

        den.aspects.nfs-a.nixos = _: {
          system.stateVersion = "25.11";
          # Export source dir created at activation (before local-fs). all_squash
          # maps client writes to the nfs-demo anon uid/gid, so make it writable.
          system.activationScripts.demoExport = "install -d -m 0777 /srv/demo";
        };
        den.aspects.nfs-b.nixos = {pkgs, ...}: {
          system.stateVersion = "25.11";
          # Defined (not started): we assert the nfs-wait bridge wired its mount
          # ordering statically, independent of boot-time mount timing.
          systemd.services.demo-consumer.serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${pkgs.coreutils}/bin/true";
          };
        };
      };

      nodes = {
        nfsa = "nfs-a";
        nfsb = "nfs-b";
      };

      # Every node needs sshd (credsync push target), credsync, the peer's
      # <host>.gio.ninja resolvable, and accept-new host keys.
      node = _: {
        nodes,
        lib,
        ...
      }: {
        # credsync must be on the remote's PATH: push runs `credsync write` over SSH.
        environment.systemPackages = [config.packages.credsync];
        services.openssh = {
          enable = true;
          settings.PermitRootLogin = lib.mkForce "prohibit-password";
        };
        # Resolve both the push targets (<host>.gio.ninja) and the WG endpoints
        # (bare host names) to the peer VMs.
        networking.extraHosts = lib.mkAfter ''
          ${nodes.nfsa.networking.primaryIPAddress} nfs-a nfs-a.gio.ninja
          ${nodes.nfsb.networking.primaryIPAddress} nfs-b nfs-b.gio.ninja
        '';
        programs.ssh.extraConfig = ''
          Host *
            StrictHostKeyChecking accept-new
            UserKnownHostsFile /root/.ssh/known_hosts
        '';
      };

      testScript = ''
        start_all()
        for m in (nfsa, nfsb):
            m.wait_for_unit("multi-user.target")
            m.wait_for_unit("sshd.service")

        with subtest("each host provisions its WG keypair + a push identity"):
            nfsa.wait_until_succeeds("test -e /usr/lib/credstore.encrypted/wg-nfs-priv-nfs-a")
            nfsa.wait_until_succeeds("test -e /usr/lib/credstore.encrypted/wg-nfs-pub-nfs-a")
            nfsb.wait_until_succeeds("test -e /usr/lib/credstore.encrypted/wg-nfs-priv-nfs-b")
            nfsb.wait_until_succeeds("test -e /usr/lib/credstore.encrypted/wg-nfs-pub-nfs-b")

        with subtest("cross-authorize the credsync push identities"):
            for src, dst in ((nfsa, nfsb), (nfsb, nfsa)):
                pub = src.succeed("cat /etc/credsync-push-key.pub").strip()
                dst.succeed("install -d -m700 /root/.ssh")
                dst.succeed(f"printf '%s\\n' '{pub}' >> /root/.ssh/authorized_keys")

        with subtest("push each host's public key to its peer"):
            nfsa.succeed("systemctl start 'secret-push-wg-nfs-pub-nfs-a@nfs-b.service'")
            nfsb.succeed("systemctl start 'secret-push-wg-nfs-pub-nfs-b@nfs-a.service'")
            nfsa.wait_until_succeeds("test -e /usr/lib/credstore.encrypted/wg-nfs-pub-nfs-b")
            nfsb.wait_until_succeeds("test -e /usr/lib/credstore.encrypted/wg-nfs-pub-nfs-a")

        with subtest("the WireGuard tunnel comes up on both ends"):
            nfsa.wait_for_unit("wg-nfs.service")
            nfsb.wait_for_unit("wg-nfs.service")
            nfsb.wait_until_succeeds("ping -c1 -W5 10.200.0.1")
            nfsa.wait_until_succeeds("ping -c1 -W5 10.200.0.2")

        with subtest("NFS mounts over the tunnel and read/write works"):
            nfsa.wait_for_unit("nfs-server.service")
            nfsa.succeed("echo fleet-nfs-ok > /srv/demo/hello")
            # Both ends are now keyed; bring the mount up and read over the tunnel.
            # reset-failed clears any start-limit from earlier boot-time attempts.
            nfsb.wait_until_succeeds(
                "systemctl reset-failed mnt-demo.mount 2>/dev/null; "
                "systemctl start mnt-demo.mount && mountpoint -q /mnt/demo"
            )
            got = nfsb.succeed("cat /mnt/demo/hello").strip()
            assert got == "fleet-nfs-ok", f"client read {got!r}"

        with subtest("ownership squashes to the deterministic nfs-demo user on both hosts"):
            # The squash user exists on the CLIENT too (created on every mesh host),
            # so a server-side identity resolves to a name rather than a bare uid.
            uid = nfsb.succeed("id -u nfs-demo").strip()
            assert nfsa.succeed("id -u nfs-demo").strip() == uid, "nfs-demo uid differs across hosts"

            # A write from the client is all_squashed to nfs-demo on the server...
            nfsb.succeed("echo from-client > /mnt/demo/cf")
            assert nfsa.succeed("stat -c '%U:%G' /srv/demo/cf").strip() == "nfs-demo:nfs-demo"
            # ...and the same numeric owner resolves back to nfs-demo on the client.
            assert nfsb.succeed("stat -c '%U:%G' /mnt/demo/cf").strip() == "nfs-demo:nfs-demo"
            assert nfsb.succeed("stat -c '%u' /mnt/demo/cf").strip() == uid

            # A file owned on the server by that uid (a server-side identity) is
            # readable/resolvable on the client even though it originates there.
            nfsa.succeed("echo from-server > /srv/demo/sf && chown nfs-demo:nfs-demo /srv/demo/sf")
            assert nfsb.succeed("stat -c '%U:%G' /mnt/demo/sf").strip() == "nfs-demo:nfs-demo"

        with subtest("the nfs-wait bridge ordered demo-consumer after the mount target"):
            props = nfsb.succeed("systemctl show -p After -p Requires demo-consumer.service")
            assert "nfs-demo.target" in props, props
      '';
    };
  };
}
