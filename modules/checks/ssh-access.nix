# Boots two real den hosts and proves an ssh.accessTo grant authenticates,
# exercising the actual ssh-access aspect end to end.
let
  pub = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINe32U66GslVJVWtAYFbfg5tdVc5SHVfOZOoXk8dsGF6 den-ssh-test";
  priv = ''
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
    QyNTUxOQAAACDXt9lOuhrJVSVVrQGBW34ObXVXOUh1XzmTqF5PHbBhegAAAJCPkiugj5Ir
    oAAAAAtzc2gtZWQyNTUxOQAAACDXt9lOuhrJVSVVrQGBW34ObXVXOUh1XzmTqF5PHbBheg
    AAAEC5IBukBfpIQgppR7u8gT7HVqt82iEcMcCzNSO/HKH4fde32U66GslVJVWtAYFbfg5t
    dVc5SHVfOZOoXk8dsGF6AAAADGRlbi1zc2gtdGVzdAE=
    -----END OPENSSH PRIVATE KEY-----
  '';
in
  _: {
    perSystem.denTests.ssh-access = {
      fleet = {den, ...}: {
        den.hosts.x86_64-linux.granter = {
          ssh.hostKey = null;
          users.alice = {
            classes = [];
            aspect.includes = [den.batteries.define-user];
            ssh.publicKey = pub;
            ssh.accessTo.grantee.bob = true;
          };
        };
        den.hosts.x86_64-linux.grantee = {
          ssh.hostKey = null;
          users.bob = {
            classes = [];
            aspect.includes = [den.batteries.define-user];
          };
        };

        den.aspects.granter.nixos = _: {
          system.stateVersion = "25.11";
          services.openssh.enable = true;
          environment.etc."ssh-test-id" = {
            text = priv;
            mode = "0600";
          };
        };
        den.aspects.grantee.nixos = _: {
          system.stateVersion = "25.11";
          services.openssh.enable = true;
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

        granter.succeed("install -d -m700 /root/.ssh")
        granter.succeed("install -m600 /etc/ssh-test-id /root/.ssh/id_ed25519")

        with subtest("ssh.accessTo grant authenticates the granted user on the grantee"):
            granter.succeed(
                "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "
                "-o IdentitiesOnly=yes -i /root/.ssh/id_ed25519 bob@grantee true"
            )
      '';
    };
  }
