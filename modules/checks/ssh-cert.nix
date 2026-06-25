# Boots two real den hosts and exercises the SSH *certificate* path end to end
# through the ssh-host-cert and ssh-access aspects (fleet.ssh.dataDir points
# them at throwaway fixtures under ./ssh-cert-data):
#
#   - host-cert trust: granter verifies grantee's CA-signed host cert with
#     StrictHostKeyChecking=yes (no TOFU, empty per-user known_hosts).
#   - user-cert auth: a client key with NO authorized_keys entry authenticates
#     purely via a user cert whose principal (bob@grantee) matches the
#     AuthorizedPrincipalsFile the aspect renders.
#   - negative controls: the same key without a cert is rejected, and a cert
#     with the wrong principal is rejected — so success can only come from the
#     cert + principal machinery, not the authorized_keys grant.
#
# The CA private keys here are throwaway, generated for this test only; the
# user CA signs client certs at runtime, the host cert is pre-signed.
let
  # Throwaway user CA private key — signs client certs inside the VM.
  userCaPriv = ''
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
    QyNTUxOQAAACDBIEtHZEZFBV2nq/Wgr0GCIHZ4PsAdEupvo7CdkQRfbwAAAJCwypXQsMqV
    0AAAAAtzc2gtZWQyNTUxOQAAACDBIEtHZEZFBV2nq/Wgr0GCIHZ4PsAdEupvo7CdkQRfbw
    AAAEAbkpIF2k4xOM1/5dedcLGMXYdey8qnmgnZTgxt0GH4KsEgS0dkRkUFXaer9aCvQYIg
    dng+wB0S6m+jsJ2RBF9vAAAAB3VzZXItY2EBAgMEBQY=
    -----END OPENSSH PRIVATE KEY-----
  '';

  # grantee's fixed ed25519 host key; its cert (committed under ssh-cert-data)
  # is signed over the matching public key, so sshd presents a verifiable cert.
  granteeHostPriv = ''
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
    QyNTUxOQAAACAPYYuq2TXRVuo0nlpcgmkB/AOcxLA5CHuPq9wsVVVbjQAAAJBofnviaH57
    4gAAAAtzc2gtZWQyNTUxOQAAACAPYYuq2TXRVuo0nlpcgmkB/AOcxLA5CHuPq9wsVVVbjQ
    AAAEA+MDjGxgMuHBX9TSd61svzcbcjZtCduOlh1PF0fIUnVA9hi6rZNdFW6jSeWlyCaQH8
    A5zEsDkIe4+r3CxVVVuNAAAADGdyYW50ZWUtaG9zdAE=
    -----END OPENSSH PRIVATE KEY-----
  '';
  granteeHostPub = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA9hi6rZNdFW6jSeWlyCaQH8A5zEsDkIe4+r3CxVVVuN grantee-host";

  # alice's granted key: its raw pubkey lands in bob's authorized_keys via the
  # grant. The cert test deliberately connects with a *different* key, so a pass
  # cannot come from this authorized_keys entry.
  alicePub = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPm2GKPwR4JMZe8gJGOc+I2JH+SLpckfCyb5tshtKnak alice-granter";

  # Wide, absolute validity so neither the pre-signed host cert nor the
  # runtime-signed client certs depend on the VM wall clock.
  validity = "20000101000000:21000101000000";
in
  _: {
    perSystem.denTests.ssh-cert = {
      fleet = {den, ...}: {
        fleet.ssh.dataDir = ./ssh-cert-data;

        den.hosts.x86_64-linux.granter = {
          ssh.hostKey = null; # client only, not enrolled
          users.alice = {
            classes = [];
            aspect.includes = [den.batteries.define-user];
            ssh.publicKey = alicePub;
            ssh.accessTo.grantee.bob = true;
          };
        };
        den.hosts.x86_64-linux.grantee = {
          ssh.hostKey = granteeHostPub;
          users.bob = {
            classes = [];
            aspect.includes = [den.batteries.define-user];
          };
        };

        den.aspects.granter.nixos = _: {
          system.stateVersion = "25.11";
          services.openssh.enable = true;
          # User CA private key, read at runtime to mint client certs.
          environment.etc."ssh-test/user-ca" = {
            text = userCaPriv;
            mode = "0600";
          };
        };

        den.aspects.grantee.nixos = {
          pkgs,
          lib,
          ...
        }: {
          system.stateVersion = "25.11";
          services.openssh.enable = true;
          # Use only the committed fixed host key so the pre-signed host cert
          # matches; placed in activation (before sshd) at 0600 — sshd refuses a
          # world-readable store symlink, so we copy out of the store.
          services.openssh.hostKeys = lib.mkForce [
            {
              type = "ed25519";
              path = "/etc/ssh/ssh_host_ed25519_key";
            }
          ];
          system.activationScripts.testHostKey.text = ''
            install -Dm600 ${pkgs.writeText "grantee_host" granteeHostPriv} /etc/ssh/ssh_host_ed25519_key
            install -Dm644 ${pkgs.writeText "grantee_host.pub" (granteeHostPub + "\n")} /etc/ssh/ssh_host_ed25519_key.pub
          '';
        };
      };

      nodes = {
        granter = "granter";
        grantee = "grantee";
      };

      testScript = ''
        start_all()
        granter.wait_for_unit("multi-user.target")
        grantee.wait_for_unit("multi-user.target")
        grantee.wait_for_unit("sshd.service")

        # Mint a client key + cert (principal bob@grantee) signed by the user CA.
        granter.succeed('ssh-keygen -q -t ed25519 -N "" -f /root/bobkey')
        granter.succeed(
            "ssh-keygen -s /etc/ssh-test/user-ca -I bob-test "
            "-n bob@grantee -V ${validity} /root/bobkey.pub"
        )

        ssh = (
            "ssh -o StrictHostKeyChecking=yes -o BatchMode=yes "
            "-o IdentitiesOnly=yes -o UserKnownHostsFile=/root/.ssh/known_hosts "
        )
        granter.succeed("install -d -m700 /root/.ssh")

        with subtest("CA-signed user cert authenticates and host cert verifies (no TOFU)"):
            # Empty per-user known_hosts: StrictHostKeyChecking=yes can only pass
            # via the host-CA entry the ssh-host-cert aspect put in /etc/ssh. The
            # client key is not in bob's authorized_keys, so auth is cert-only.
            granter.succeed(f"{ssh} -i /root/bobkey bob@grantee true")

        with subtest("same key WITHOUT a cert is rejected"):
            granter.succeed('ssh-keygen -q -t ed25519 -N "" -f /root/nocert')
            granter.fail(f"{ssh} -i /root/nocert bob@grantee true")

        with subtest("user cert with the wrong principal is rejected"):
            granter.succeed('ssh-keygen -q -t ed25519 -N "" -f /root/wrongkey')
            granter.succeed(
                "ssh-keygen -s /etc/ssh-test/user-ca -I wrong "
                "-n carol@grantee -V ${validity} /root/wrongkey.pub"
            )
            granter.fail(f"{ssh} -i /root/wrongkey bob@grantee true")
      '';
    };
  }
