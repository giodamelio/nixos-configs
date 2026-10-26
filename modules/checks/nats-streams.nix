# A two-node NATS cluster where n1 declares a JetStream stream: the oneshot
# waits for the cluster to have a majority, creates the stream, is a no-op when
# re-run, and applies a changed max_age. A bifrost route on n1 publishes into
# the stream through gio.bifrost.services.<name>.nats.
_: let
  secrets = {
    bifrost_token_key = "0123456789abcdef0123456789abcdef0123456789abcdef";
    bifrost_pocket_id_client_secret = "op-client-secret";
    hook_token = "hook-token";
  };
  domain = "external.test";
  port = 52793;
  day = 86400 * 1000000000;
in {
  perSystem.denTests.nats-streams = {
    fleet = {den, ...}: {
      den.hosts.x86_64-linux = {
        n1.ssh.hostKey = null;
        n2.ssh.hostKey = null;
      };

      den.aspects.n1 = {
        includes = [den.aspects.nats den.aspects.bifrost];
        nixos = {
          config,
          lib,
          ...
        }: let
          consumers = ["caddy-bifrost.service"];
        in {
          system.stateVersion = "25.11";
          networking.nftables.enable = true;

          gio.nats.streams.WEBHOOKS = {
            subjects = ["webhooks.>"];
            maxAge = "7d";
          };
          specialisation.shorter.configuration.gio.nats.streams.WEBHOOKS.maxAge = lib.mkForce "1d";

          fleet.credentials.manifestFile = builtins.toFile "manifest.toml" ''
            n1 = [${lib.concatMapStringsSep ", " (n: ''"${n}"'') (lib.attrNames secrets)}]
          '';

          gio.bifrost = {
            inherit domain port;
            tls = "tls internal";
            dynamicDns = false;
            lanProxy = false;
            login = {
              issuer = "http://op.test:8000";
              clientId = "bifrost";
            };
            nats.url = "nats://127.0.0.1:4222";
            credentials = ["hook_token"];
            services.hooks = {
              config = ''
                bifrost_guard bearer {
                  token_file ${config.gio.bifrost.credentialDir}/hook_token
                }
              '';
              nats = {
                subject = "webhooks.test";
                stream = "WEBHOOKS";
              };
            };
          };

          systemd.services.bifrost-test-credentials = {
            requiredBy = consumers;
            before = consumers;
            path = [config.systemd.package];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            script = ''
              install -d -m 0700 /etc/credstore.encrypted
              ${lib.concatStrings (lib.mapAttrsToList (name: value: ''
                  printf '%s' ${lib.escapeShellArg value} | systemd-creds encrypt --name=${name} - /etc/credstore.encrypted/${name}
                '')
                secrets)}
            '';
          };
        };
      };

      den.aspects.n2 = {
        includes = [den.aspects.nats];
        nixos = {
          system.stateVersion = "25.11";
          networking.nftables.enable = true;
        };
      };
    };

    nodes = {
      n1 = "n1";
      n2 = "n2";
    };

    # The aspect's cluster routes name the real hosts.
    node = _: {nodes, ...}: {
      networking.extraHosts = ''
        ${nodes.n1.networking.primaryIPAddress} carbon.gio.ninja hooks.${domain}
        ${nodes.n2.networking.primaryIPAddress} gallium.gio.ninja
      '';
    };

    testScript = ''
      import json

      def stream():
          return json.loads(n1.succeed("nats stream info WEBHOOKS --json"))

      n1.start()
      n1.wait_for_unit("nats.service")

      with subtest("the oneshot keeps retrying while the cluster has no majority"):
          n1.wait_until_succeeds("journalctl -u nats-create-streams | grep -q 'Scheduled restart job'", timeout=120)
          n1.fail("nats stream info WEBHOOKS")

      n2.start()

      with subtest("once both nodes are up the stream is created as declared"):
          n1.wait_for_unit("nats-create-streams.service", timeout=180)
          cfg = stream()["config"]
          assert cfg["subjects"] == ["webhooks.>"], cfg
          assert cfg["num_replicas"] == 2, cfg
          assert cfg["max_age"] == ${toString (7 * day)}, cfg
          assert cfg["storage"] == "file", cfg

      with subtest("re-running the oneshot changes nothing"):
          n1.succeed("systemctl restart nats-create-streams.service")
          n1.succeed("journalctl -u nats-create-streams --since -1min | grep -q 'No difference in configuration'")

      with subtest("a changed max_age is applied in place"):
          n1.succeed("/run/current-system/specialisation/shorter/bin/switch-to-configuration test")
          n1.wait_until_succeeds("nats stream info WEBHOOKS --json | grep -q '\"max_age\": ${toString day}'", timeout=60)

      with subtest("a bifrost route with nats.stream lands its request in the stream"):
          n1.wait_for_unit("caddy-bifrost.service")
          n1.wait_for_open_port(${toString port})
          code = n2.succeed(
              "curl -sk -o /dev/null -w '%{http_code}' -X POST -d '{\"hello\":1}' "
              "-H 'Authorization: Bearer ${secrets.hook_token}' "
              "--resolve hooks.${domain}:${toString port}:$(getent hosts carbon.gio.ninja | cut -d' ' -f1) "
              "https://hooks.${domain}:${toString port}/github"
          ).strip()
          assert code == "202", code
          assert stream()["state"]["messages"] == 1, stream()["state"]
          msg = json.loads(n1.succeed("nats stream get WEBHOOKS 1 --json"))
          import base64
          body = json.loads(base64.b64decode(msg["data"]))
          assert body["path"] == "/github" and body["body"] == '{"hello":1}', body
    '';
  };
}
