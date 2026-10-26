# The bifrost aspect on a den host: credentials arrive through systemd-creds
# as agevault delivers them, the generated wildcard site serves an oauth and a
# bearer service, and fail2ban bans an address that keeps failing checks.
# The OAuth flow itself is covered by the package's own VM test.
_: let
  secrets = {
    bifrost_token_key = "0123456789abcdef0123456789abcdef0123456789abcdef";
    bifrost_pocket_id_client_secret = "op-client-secret";
    hook_token = "hook-token";
  };
  domain = "external.test";
  port = 52793;
in {
  perSystem.denTests.bifrost = {
    fleet = {den, ...}: {
      den.hosts.x86_64-linux = {
        srv.ssh.hostKey = null;
        atk.ssh.hostKey = null;
      };

      den.aspects.srv = {
        includes = [den.aspects.bifrost];
        nixos = {
          config,
          lib,
          ...
        }: let
          consumers = ["caddy-bifrost.service"];
        in {
          system.stateVersion = "25.11";
          networking.nftables.enable = true;

          fleet.credentials.manifestFile = builtins.toFile "manifest.toml" ''
            srv = [${lib.concatMapStringsSep ", " (n: ''"${n}"'') (lib.attrNames secrets)}]
          '';

          gio.bifrost = {
            inherit domain port;
            tls = "tls internal";
            dynamicDns = false;
            # The LAN proxy rides the internal Caddy's Cloudflare certificate.
            lanProxy = false;
            # Discovery is lazy, so nothing here is contacted in this test.
            login = {
              issuer = "http://op.test:8000";
              clientId = "bifrost";
            };
            credentials = ["hook_token"];
            fail2ban.maxRetry = 5;
            services = {
              hooks.config = ''
                bifrost_guard bearer {
                  token_file ${config.gio.bifrost.credentialDir}/hook_token
                }
                respond "hook-ok" 200
              '';
              notes = {
                oauth = {
                  scopes = ["notes:read"];
                  groups = [];
                };
                config = ''respond "notes-ok" 200'';
              };
            };
          };

          # A deploy that forces caddy-bifrost to restart, as a new binary does.
          specialisation.restarted.configuration.systemd.services.caddy-bifrost.environment.BIFROST_TEST_GENERATION = "2";

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

      den.aspects.atk.nixos = {pkgs, ...}: {
        system.stateVersion = "25.11";
        environment.systemPackages = [
          pkgs.curl
          (pkgs.writeShellScriptBin "curl3" ''exec ${pkgs.curlHTTP3}/bin/curl "$@"'')
        ];
      };
    };

    nodes = {
      srv = "srv";
      atk = "atk";
    };

    node = _: {nodes, ...}: {
      networking.extraHosts = ''
        ${nodes.srv.networking.primaryIPAddress} auth.${domain} hooks.${domain} notes.${domain} unknown.${domain}
      '';
    };

    testScript = ''
      import json

      CURL = "curl -sk --max-time 5"

      def url(host, path="/"):
          return f"https://{host}.${domain}:${toString port}{path}"

      def status(cmd):
          return int(atk.succeed(f"{CURL} -o /dev/null -w '%{{http_code}}' {cmd}"))

      start_all()
      srv.wait_for_unit("caddy-bifrost.service")
      srv.wait_for_unit("fail2ban.service")
      srv.wait_for_open_port(${toString port})
      atk.wait_until_succeeds(f"{CURL} -o /dev/null {url('unknown')}", timeout=60)

      with subtest("the service runs as its own user with state on /var/lib/bifrost"):
          assert srv.succeed("systemctl show -p User --value caddy-bifrost.service").strip() == "bifrost"
          srv.wait_until_succeeds("ls /var/lib/bifrost/caddy/bifrost/keys | grep -q .", timeout=30)

      with subtest("credentials reach the generated config"):
          assert status(f"-H 'Authorization: Bearer ${secrets.hook_token}' {url('hooks')}") == 200
          prm = json.loads(atk.succeed(f"{CURL} {url('notes', '/.well-known/oauth-protected-resource')}"))
          assert prm["resource"] == "https://notes.${domain}", prm
          assert status(url("notes")) == 401
          assert status(url("unknown")) == 404

      with subtest("HTTP/3 is served on the same port"):
          code = atk.succeed(
              f"curl3 --http3-only -sk --max-time 5 -o /dev/null -w '%{{http_code}}' "
              f"-H 'Authorization: Bearer ${secrets.hook_token}' {url('hooks')}"
          ).strip()
          assert code == "200", code

      with subtest("a deploy that restarts bifrost refuses no connections"):
          socket_since = srv.succeed("systemctl show -p ActiveEnterTimestampMonotonic --value caddy-bifrost.socket").strip()
          pid = srv.succeed("systemctl show -p MainPID --value caddy-bifrost.service").strip()
          atk.succeed(
              "nohup sh -c 'for i in $(seq 150); do "
              f"curl -sk --max-time 20 -o /dev/null -w \"%{{http_code}} %{{time_total}} %{{exitcode}} %{{errormsg}}\\n\" -H \"Authorization: Bearer ${secrets.hook_token}\" {url('hooks')}; "
              "sleep 0.1; done > /tmp/probe.log 2>&1; touch /tmp/probe.done' >/dev/null 2>&1 &"
          )
          atk.sleep(2)
          srv.succeed("/run/current-system/specialisation/restarted/bin/switch-to-configuration test")
          atk.wait_for_file("/tmp/probe.done", timeout=120)
          assert srv.succeed("systemctl show -p MainPID --value caddy-bifrost.service").strip() != pid, "bifrost did not restart"
          assert srv.succeed("systemctl show -p ActiveEnterTimestampMonotonic --value caddy-bifrost.socket").strip() == socket_since, "the socket was restarted"
          results = [line.split(maxsplit=3) for line in atk.succeed("cat /tmp/probe.log").splitlines()]
          failed = [r for r in results if r[0] != "200"]
          slowest = max(float(r[1]) for r in results)
          print(f"probe: {len(results)} requests, slowest {slowest:.2f}s, failed {failed}")
          assert len(results) == 150 and not failed, failed
          assert slowest < 15, slowest

      with subtest("repeated failures get the address banned at the firewall"):
          for _ in range(6):
              status(f"-H 'Authorization: Bearer wrong' {url('hooks')}")
          atk_ip = atk.succeed("ip -4 -o addr show eth1 | awk '{print $4}' | cut -d/ -f1").strip()
          srv.wait_until_succeeds(f"fail2ban-client status bifrost | grep -F {atk_ip}", timeout=60)
          atk.fail(f"{CURL} -o /dev/null {url('hooks')}")
          srv.succeed(f"{CURL} -o /dev/null --resolve hooks.${domain}:${toString port}:127.0.0.1 {url('hooks')}")
    '';
  };
}
