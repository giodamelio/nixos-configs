{ssh-ca}: {
  name = "ssh-ca";

  nodes.machine = {
    environment.systemPackages = [ssh-ca];
    # No TPM in the test VM; systemd-creds needs an explicit key choice.
    environment.variables.SSH_CA_CREDS_ARGS = "--with-key=auto";
  };

  testScript = ''
    import json

    machine.wait_for_unit("multi-user.target")

    with subtest("init creates the CA"):
        out = machine.succeed("ssh-ca init")
        assert "host-ca.pub" in out, f"expected pubkey announcement, got: {out}"
        machine.succeed("test -f /var/lib/ssh-step-ca/config/ca.json")
        machine.succeed("test -f /usr/lib/credstore.encrypted/ssh-ca-password")
        host_ca = machine.succeed("cat /var/lib/ssh-ca/host-ca.pub").strip()
        user_ca = machine.succeed("cat /var/lib/ssh-ca/user-ca.pub").strip()
        assert host_ca and user_ca and host_ca != user_ca

    with subtest("second init is a no-op"):
        out = machine.succeed("ssh-ca init")
        assert "already initialized" in out, f"expected no-op, got: {out}"

    with subtest("prepare targets"):
        machine.succeed('ssh-keygen -q -t ed25519 -N "" -f /root/hostkey')
        machine.succeed('ssh-keygen -q -t ed25519 -N "" -f /root/clientkey')
        host_pub = machine.succeed("cat /root/hostkey.pub").strip()
        client_pub = machine.succeed("cat /root/clientkey.pub").strip()
        targets = {
            "hosts": {
                "testhost": {
                    "pubkey": host_pub,
                    "principals": ["testhost", "testhost.gio.ninja"],
                },
            },
            "clients": {
                "phone": {
                    "pubkey": client_pub,
                    "principals": ["giodamelio@testhost"],
                },
            },
        }
        machine.succeed(f"echo {json.dumps(json.dumps(targets))} > /root/targets.json")
        # Outside a unit there is no $CREDENTIALS_DIRECTORY; decrypt the
        # credstore blob the way LoadCredentialEncrypted would.
        machine.succeed(
            "systemd-creds decrypt --name=ssh-ca-password"
            " /usr/lib/credstore.encrypted/ssh-ca-password /root/pw"
        )

    sign = "SSH_CA_PASSWORD_FILE=/root/pw ssh-ca sign /root/targets.json"

    with subtest("sign mints host and client certs"):
        out = machine.succeed(sign)
        assert "signed" in out, f"expected signed certs, got: {out}"
        host_cert = machine.succeed("ssh-keygen -Lf /var/lib/ssh-ca/certs/testhost-cert.pub")
        assert "host certificate" in host_cert, host_cert
        assert "testhost.gio.ninja" in host_cert, host_cert
        client_cert = machine.succeed("ssh-keygen -Lf /var/lib/ssh-ca/certs/clients/phone-cert.pub")
        assert "user certificate" in client_cert, client_cert
        assert "giodamelio@testhost" in client_cert, client_cert

    def serial(path):
        return machine.succeed(f"ssh-keygen -Lf {path} | grep Serial").strip()

    with subtest("re-run is a no-op"):
        before = serial("/var/lib/ssh-ca/certs/testhost-cert.pub")
        out = machine.succeed(sign)
        assert "signed" not in out, f"expected all-ok, got: {out}"
        assert serial("/var/lib/ssh-ca/certs/testhost-cert.pub") == before

    with subtest("changed principals trigger a re-sign"):
        before = serial("/var/lib/ssh-ca/certs/testhost-cert.pub")
        machine.succeed("sed -i s/testhost.gio.ninja/other.gio.ninja/ /root/targets.json")
        out = machine.succeed(sign)
        assert "signed" in out, f"expected re-sign, got: {out}"
        assert serial("/var/lib/ssh-ca/certs/testhost-cert.pub") != before
        cert = machine.succeed("ssh-keygen -Lf /var/lib/ssh-ca/certs/testhost-cert.pub")
        assert "other.gio.ninja" in cert, cert

    with subtest("host cert verifies against the published host CA"):
        ca_fp = machine.succeed("ssh-keygen -lf /var/lib/ssh-ca/host-ca.pub").split()[1]
        cert = machine.succeed("ssh-keygen -Lf /var/lib/ssh-ca/certs/testhost-cert.pub")
        assert ca_fp in cert, f"cert not signed by published host CA: {ca_fp}"

    with subtest("sync copies artifacts into the repo"):
        # Fake repo checkout; the units don't exist in this VM, so sync just
        # copies what the earlier subtests generated.
        machine.succeed("mkdir -p /root/repo && touch /root/repo/flake.nix")
        out = machine.succeed("ssh-ca sync --repo /root/repo")
        assert "updated" in out, f"expected copies, got: {out}"
        data = "/root/repo/modules/aspects/ssh/data"
        machine.succeed(f"test -f {data}/host-ca.pub")
        machine.succeed(f"test -f {data}/user-ca.pub")
        machine.succeed(f"test -f {data}/certs/testhost-cert.pub")
        machine.succeed(f"test -f {data}/certs/clients/phone-cert.pub")

    with subtest("second sync is a no-op"):
        out = machine.succeed("ssh-ca sync --repo /root/repo")
        assert "repo already in sync" in out, f"expected no-op, got: {out}"

    with subtest("sync refuses a non-repo path"):
        machine.fail("ssh-ca sync --repo /root/not-a-repo")
  '';
}
