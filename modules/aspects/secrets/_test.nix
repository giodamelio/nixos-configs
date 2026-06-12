# Two-VM end-to-end test for the fleet.secrets aspect. alpha originates two
# secrets (generated locally) and pushes them to beta via the generated
# secret-push units over the dedicated credsync identity; beta's path -> target
# wiring starts the consumers only once each blob lands, exercising a credential
# rename and an env-wrapper. Runtime transport itself is covered separately by
# the credsync VM test; this proves the units the aspect emits are wired right.
{
  pkgs,
  lib,
  credsync,
}: let
  expand = import ./_expand.nix {inherit lib;};

  # Local default-fillers so the registry is complete for _expand without
  # pulling in the schema submodule (keeps schema.nix untouched). They apply the
  # same defaults the schema would, so the registry literal carries none.
  gen = script: {
    enable = true;
    inherit script;
    path = _: [];
    after = [];
    needs = [];
  };
  # site key -> the use-site; `unit` defaults to the key (as the schema does).
  site = unit: cfg: {
    enable = true;
    unit = cfg.unit or unit;
    type = cfg.type or "credential";
    credential = {
      name = cfg.credName or null;
      source = null;
      encrypted = true;
    };
    env-wrapper.variable = cfg.variable or null;
    restartOnChange = false;
    upholds = false;
  };
  secret = a: {
    enable = true;
    inherit (a) origin;
    generator = a.generator or null;
    copyTo = a.copyTo or [];
    use =
      lib.mapAttrs (_host: services: {
        enable = true;
        services = lib.mapAttrs site services;
      })
      a.use;
  };

  registry = {
    # Generated on alpha, consumed on beta under a renamed credential id.
    demo = secret {
      origin = "alpha";
      generator = gen "printf s3cr3t-value";
      use.beta.consumer.credName = "renamed-cred";
    };
    # Generated on alpha, consumed on beta via the ExecStart env-wrapper.
    envsecret = secret {
      origin = "alpha";
      generator = gen "printf env-value";
      use.beta.envconsumer = {
        type = "env-wrapper";
        variable = "ENVSECRET";
      };
    };
  };

  # pushKeys empty: beta authorizes alpha at runtime (the forced-command lock is
  # already covered by the credsync VM test). alpha still pushes with its
  # generated credsync identity.
  secretsModule = hostName:
    expand {
      inherit registry hostName credsync;
      pushKeys = {};
    };
in {
  name = "fleet-secrets";

  nodes = {
    alpha = {nodes, ...}: {
      imports = [(secretsModule "alpha")];
      environment.systemPackages = [credsync];
      # The push targets <dest>.gio.ninja; resolve it to beta and accept its key.
      networking.extraHosts = "${nodes.beta.networking.primaryIPAddress} beta.gio.ninja\n";
      programs.ssh.extraConfig = ''
        Host *
          StrictHostKeyChecking accept-new
          UserKnownHostsFile /root/.ssh/known_hosts
      '';
    };

    beta = {...}: {
      imports = [(secretsModule "beta")];
      environment.systemPackages = [credsync];
      services.openssh = {
        enable = true;
        settings.PermitRootLogin = "prohibit-password";
      };

      # Consumers referenced by the use-sites. Neither is wantedBy a target of
      # its own — only the secret's target pulls them in once the blob arrives.
      systemd.services.consumer.serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "consumer" ''
          cat "$CREDENTIALS_DIRECTORY/renamed-cred" > /run/consumer-proof
        '';
      };
      systemd.services.envconsumer.serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "envconsumer" ''
          printf '%s' "$ENVSECRET" > /run/envconsumer-proof
        '';
      };
    };
  };

  testScript = ''
    start_all()
    alpha.wait_for_unit("multi-user.target")
    beta.wait_for_unit("multi-user.target")
    beta.wait_for_unit("sshd.service")

    with subtest("alpha provisions secrets and a push identity at boot"):
        alpha.wait_until_succeeds("test -e /usr/lib/credstore.encrypted/demo")
        alpha.wait_until_succeeds("test -e /usr/lib/credstore.encrypted/envsecret")
        alpha.wait_until_succeeds("test -e /usr/lib/credstore.encrypted/credsync-push-key")

    with subtest("beta consumers stay down until their secret arrives"):
        beta.fail("test -e /run/consumer-proof")
        beta.fail("test -e /run/envconsumer-proof")

    with subtest("authorize alpha's push identity on beta"):
        pub = alpha.succeed("cat /etc/credsync-push-key.pub").strip()
        alpha.succeed("install -d -m700 /root/.ssh")
        beta.succeed("install -d -m700 /root/.ssh")
        beta.succeed(f"printf '%s\\n' '{pub}' >> /root/.ssh/authorized_keys")

    with subtest("push delivers secrets; targets start the consumers"):
        alpha.succeed("systemctl start secret-push-demo@beta.service")
        alpha.succeed("systemctl start secret-push-envsecret@beta.service")
        beta.wait_for_unit("secret-demo.target")
        beta.wait_for_unit("secret-envsecret.target")

    with subtest("renamed credential is loaded into the consumer"):
        beta.wait_until_succeeds("test -e /run/consumer-proof")
        got = beta.succeed("cat /run/consumer-proof").strip()
        assert got == "s3cr3t-value", f"consumer saw {got!r}"

    with subtest("env-wrapper exports the value into the service"):
        beta.wait_until_succeeds("test -e /run/envconsumer-proof")
        got = beta.succeed("cat /run/envconsumer-proof").strip()
        assert got == "env-value", f"envconsumer saw {got!r}"
  '';
}
