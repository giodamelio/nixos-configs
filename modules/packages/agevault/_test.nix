# End-to-end test for agevault: a `source` node drives a secrets repo (age at
# rest, a software identity standing in for the YubiKey) and delivers a secret
# into a `target` node's credstore over ssh, exercising edit/cat/generate-nix/
# push/rekey/rm and the sudo (non-root login) path. Attached to the package as
# passthru.tests.vm (see agevault.nix).
{agevault}: {
  name = "agevault";

  nodes = {
    source = {pkgs, ...}: {
      environment.systemPackages = [agevault pkgs.age];
    };

    target = _: {
      environment.systemPackages = [agevault];

      services.openssh = {
        enable = true;
        settings.PermitRootLogin = "prohibit-password";
      };

      # Non-root push path: agevault prefixes the remote command with sudo -n.
      users.users.deploy = {
        isNormalUser = true;
        extraGroups = ["wheel"];
      };
      security.sudo.wheelNeedsPassword = false;
    };
  };

  testScript = ''
    start_all()
    source.wait_for_unit("multi-user.target")
    target.wait_for_unit("multi-user.target")
    target.wait_for_unit("sshd.service")

    # agevault runs inside a secrets repo; AGEVAULT_ROOT points at it.
    env = "AGEVAULT_ROOT=/root/secrets AGEVAULT_IDENTITY=/root/key.txt"
    cred = "/usr/lib/credstore.encrypted/my-secret"

    def av(cmd):
        return source.succeed(f"cd /root/secrets && {env} agevault {cmd}")

    with subtest("ssh setup"):
        source.succeed("mkdir -p /root/.ssh")
        source.succeed('ssh-keygen -t ed25519 -N "" -f /root/.ssh/id_ed25519')
        pubkey = source.succeed("cat /root/.ssh/id_ed25519.pub").strip()
        target.succeed(f"mkdir -p /root/.ssh && echo '{pubkey}' >> /root/.ssh/authorized_keys")
        target.succeed(
            f"mkdir -p /home/deploy/.ssh && echo '{pubkey}' >> /home/deploy/.ssh/authorized_keys"
            " && chown -R deploy:users /home/deploy/.ssh && chmod 700 /home/deploy/.ssh"
        )
        # agevault forces BatchMode, which would refuse the unknown host key.
        source.succeed("printf 'Host *\\n  StrictHostKeyChecking accept-new\\n' > /root/.ssh/config")

    with subtest("init secrets repo"):
        source.succeed("mkdir -p /root/secrets/hosts")
        # Software age identity stands in for the YubiKey recipient.
        source.succeed("age-keygen -o /root/key.txt 2>/dev/null")
        source.succeed("age-keygen -y /root/key.txt > /root/secrets/recipients.txt")
        source.succeed(
            "printf '%s\\n' "
            "'manifest_path = \"/root/secrets.toml\"' "
            "'[destinations]' "
            "'target = \"root@target\"' "
            "'deploytgt = \"deploy@target\"' "
            "> /root/secrets/config.toml"
        )
        # A fake $EDITOR that just writes a fixed value.
        source.succeed(
            "printf '#!/bin/sh\\nprintf super-secret-1 > \"$1\"\\n' > /root/fill.sh"
            " && chmod +x /root/fill.sh"
        )

    with subtest("edit creates a secret and refreshes the manifest"):
        source.succeed(
            f"cd /root/secrets && EDITOR=/root/fill.sh {env} agevault edit target my-secret"
        )
        source.succeed("test -f /root/secrets/hosts/target/my-secret.age")
        manifest = source.succeed("cat /root/secrets.toml")
        assert 'target = ["my-secret"]' in manifest, f"manifest: {manifest!r}"

    with subtest("cat decrypts back to the plaintext"):
        got = av("cat target my-secret")
        assert got == "super-secret-1", f"cat returned {got!r}"

    with subtest("first push reports 'updated' and caches the receiver"):
        out = av("push target my-secret")
        assert "updated" in out, f"expected 'updated', got: {out}"
        got = target.succeed(f"systemd-creds decrypt --name=my-secret {cred} -")
        assert got == "super-secret-1", f"target decrypted to {got!r}"
        # Blob is 0400 and the dir 0700, owned by root.
        target.succeed(f"test $(stat -c '%a' {cred}) = 400")
        target.succeed("test $(stat -c '%a' /usr/lib/credstore.encrypted) = 700")
        # The receiver was copied into the root-only cache dir (miss -> copy -> retry).
        target.succeed("test $(stat -c '%a' /run/agevault) = 700")
        target.succeed("ls /run/agevault/receive-*.sh")

    with subtest("re-push of the same value reports 'unchanged' and does not rewrite"):
        before = target.succeed(f"stat -c '%Y %i' {cred}").strip()
        out = av("push target my-secret")
        assert "unchanged" in out, f"expected 'unchanged', got: {out}"
        assert (
            target.succeed(f"stat -c '%Y %i' {cred}").strip() == before
        ), "blob was rewritten on an unchanged push"

    with subtest("rekey re-encrypts to the current recipients"):
        before = source.succeed("cat /root/secrets/hosts/target/my-secret.age")
        av("rekey")
        after = source.succeed("cat /root/secrets/hosts/target/my-secret.age")
        assert before != after, "rekey did not rewrite the ciphertext"
        # ...and it still decrypts to the same value.
        got = av("cat target my-secret")
        assert got == "super-secret-1", f"post-rekey cat returned {got!r}"

    with subtest("push-all after rekey is 'unchanged' (compares plaintext, not ciphertext)"):
        # rekey rewrote the .age ciphertext but the plaintext is identical, so
        # the target must NOT see a change.
        out = av("push")
        assert "unchanged" in out, f"expected 'unchanged' after rekey, got: {out}"
        got = target.succeed(f"systemd-creds decrypt --name=my-secret {cred} -")
        assert got == "super-secret-1", f"target decrypted to {got!r}"

    with subtest("non-root destination goes through sudo -n and can write"):
        source.succeed("mkdir -p /root/secrets/hosts/deploytgt")
        source.succeed(f"printf via-sudo-value | {env} agevault write deploytgt my-secret -")
        out = av("push deploytgt my-secret")
        assert "updated" in out, f"expected 'updated' via sudo, got: {out}"
        got = target.succeed(f"systemd-creds decrypt --name=my-secret {cred} -")
        assert got == "via-sudo-value", f"sudo push decrypted to {got!r}"

    with subtest("rm deletes the secret and refreshes the manifest"):
        av("rm deploytgt my-secret")
        source.fail("test -f /root/secrets/hosts/deploytgt/my-secret.age")
        manifest = source.succeed("cat /root/secrets.toml")
        assert "deploytgt = []" in manifest, f"manifest after rm: {manifest!r}"
  '';
}
