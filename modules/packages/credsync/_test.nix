# Two-VM end-to-end test for credsync: a `source` node generates a credential
# and pushes it to a `target` node over SSH, exercising the idempotent
# fast-path, change propagation, restart-units, and the sudo (non-root login)
# path. Attached to the package as passthru.tests.vm (see credsync.nix).
{credsync}: {
  name = "credsync";

  nodes = {
    source = {
      environment.systemPackages = [credsync];
    };

    target = {pkgs, ...}: {
      environment.systemPackages = [credsync];

      services.openssh = {
        enable = true;
        settings.PermitRootLogin = "prohibit-password";
      };

      # Non-root push path: credsync prefixes the remote command with sudo -n.
      users.users.deploy = {
        isNormalUser = true;
        extraGroups = ["wheel"];
      };
      security.sudo.wheelNeedsPassword = false;

      # A dummy consumer of the credential, restarted via restart-units.
      systemd.services.consumer = {
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
        };
      };
    };
  };

  testScript = ''
    start_all()
    source.wait_for_unit("multi-user.target")
    target.wait_for_unit("multi-user.target")
    target.wait_for_unit("sshd.service")

    cred = "/usr/lib/credstore.encrypted/api-token"

    def consumer_started_at():
        return target.succeed(
            "systemctl show -p ActiveEnterTimestampMonotonic consumer.service"
        ).strip()

    def cred_stat():
        return target.succeed(f"stat -c '%Y %i' {cred}").strip()

    with subtest("ssh setup"):
        source.succeed("mkdir -p /root/.ssh")
        source.succeed('ssh-keygen -t ed25519 -N "" -f /root/.ssh/id_ed25519')
        pubkey = source.succeed("cat /root/.ssh/id_ed25519.pub").strip()
        target.succeed(f"mkdir -p /root/.ssh && echo '{pubkey}' >> /root/.ssh/authorized_keys")
        target.succeed(
            f"mkdir -p /home/deploy/.ssh && echo '{pubkey}' >> /home/deploy/.ssh/authorized_keys"
            " && chown -R deploy:users /home/deploy/.ssh && chmod 700 /home/deploy/.ssh"
        )
        # credsync forces BatchMode, which would refuse the unknown host key.
        source.succeed("printf 'Host *\\n  StrictHostKeyChecking accept-new\\n' > /root/.ssh/config")

    with subtest("create credential on source"):
        source.succeed("mkdir -p /usr/lib/credstore.encrypted")
        source.succeed(f"printf secret1 | systemd-creds encrypt --name=api-token - {cred}")

    with subtest("first push copies the secret"):
        out = source.succeed("credsync push api-token root@target")
        assert "updated" in out, f"expected 'updated', got: {out}"
        got = target.succeed(f"systemd-creds decrypt --name=api-token {cred} -")
        assert got == "secret1", f"target decrypted to {got!r}"

    with subtest("second push is a no-op"):
        before = cred_stat()
        out = source.succeed("credsync push api-token root@target")
        assert "unchanged" in out, f"expected 'unchanged', got: {out}"
        assert cred_stat() == before, "credential file was rewritten on unchanged push"

    with subtest("changed secret propagates and restarts consumers"):
        target.wait_for_unit("consumer.service")
        started = consumer_started_at()
        source.succeed(
            f"printf secret2 | systemd-creds encrypt --name=api-token - {cred}.new"
            f" && mv {cred}.new {cred}"
        )
        out = source.succeed("credsync push api-token root@target consumer.service")
        assert "updated" in out, f"expected 'updated', got: {out}"
        got = target.succeed(f"systemd-creds decrypt --name=api-token {cred} -")
        assert got == "secret2", f"target decrypted to {got!r}"
        assert consumer_started_at() != started, "consumer.service was not restarted"

    with subtest("unchanged push does not restart consumers"):
        started = consumer_started_at()
        out = source.succeed("credsync push api-token root@target consumer.service")
        assert "unchanged" in out, f"expected 'unchanged', got: {out}"
        assert consumer_started_at() == started, "consumer.service restarted on unchanged push"

    with subtest("non-root destination goes through sudo"):
        out = source.succeed("credsync push api-token deploy@target")
        assert "unchanged" in out, f"expected 'unchanged', got: {out}"
  '';
}
