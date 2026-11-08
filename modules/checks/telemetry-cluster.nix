# Two telemetry members behind real step-ca certificates, Caddy and caddy-l4.
# Public certificates are the one stand-in: DNS-01 cannot run in a VM, so the
# front door and push site use Caddy's internal issuer under a fixed test root
# that every node trusts.
{inputs, ...}: {
  perSystem = {
    pkgs,
    lib,
    ...
  }: let
    stepCa = import ./_step-ca.nix {inherit pkgs lib inputs;};
    inherit (stepCa) caDir pki;

    # The driver numbers vlan addresses by sorted node name (ca, tela, telb).
    addressOf = {
      ca = "192.168.1.1";
      tel-a = "192.168.1.2";
      tel-b = "192.168.1.3";
    };
    members = ["tel-a" "tel-b"];

    testPki = pkgs.runCommand "telemetry-cluster-test-pki" {nativeBuildInputs = [pkgs.step-cli];} ''
      mkdir $out && cd $out
      export STEPPATH=$TMPDIR/step HOME=$TMPDIR
      step certificate create "public stand-in root" public-root.crt public-root.key \
        --profile root-ca --no-password --insecure
    '';

    secrets = {
      telemetry_pushover_app_token = "test-token";
      telemetry_pushover_user_token = "test-user";
      telemetry_watchdog_url = "http://127.0.0.1:9/watchdog";
    };
  in {
    denTests.telemetry-cluster = {
      fleet = {den, ...}: {
        den.hosts.x86_64-linux =
          {ca.ssh.enable = false;}
          // lib.genAttrs members (name: {
            ssh.enable = false;
            network.interfaces.eth1.address = addressOf.${name};
          });
        fleet.nfs.caRoot = "${pki}/root.crt";
        fleet.telemetry = {
          clusterNodes = members;
          pushAllowedRanges = map (m: "${addressOf.${m}}/32") members;
          crlUpdateInterval = "5s";
        };

        den.aspects.ca.nixos = stepCa.caModule;

        den.aspects.tel-test.nixos = {
          config,
          pkgs,
          ...
        }: let
          consumers = ["caddy.service" "alertmanager.service"];
        in {
          system.stateVersion = "25.11";
          networking.nftables.enable = true;
          virtualisation = {
            memorySize = 3072;
            cores = 2;
          };
          environment.systemPackages = [pkgs.step-cli pkgs.jq pkgs.openssl];

          services.gio.reverse-proxy.certIssuer = "internal";
          services.caddy.globalConfig = ''
            skip_install_trust
            pki {
              ca local {
                root {
                  cert ${testPki}/public-root.crt
                  key ${testPki}/public-root.key
                  format pem_file
                }
              }
            }
          '';

          # Stands in for an existing vhost on the same :443 server, to show
          # strict SNI-Host enforcement leaves it working.
          services.gio.reverse-proxy.virtualHosts.existing = {
            host = "127.0.0.1";
            port = 8099;
          };
          systemd.services.existing-upstream = {
            wantedBy = ["multi-user.target"];
            serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 -m http.server 8099 --bind 127.0.0.1 --directory ${pkgs.writeTextDir "index.html" "existing-ok"}";
          };

          fleet.credentials.manifestFile = builtins.toFile "manifest.toml" (lib.concatMapStrings (m: ''
              ${m} = [${lib.concatMapStringsSep ", " (n: ''"${n}"'') (lib.attrNames secrets)}]
            '')
            members);

          # Encrypted under their credstore names, as agevault does, so the name check is real.
          systemd.services.telemetry-test-credentials = {
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
                  printf '%s' "${value}" | systemd-creds encrypt --name=${name} - /etc/credstore.encrypted/${name}
                '')
                secrets)}
            '';
          };
        };

        den.aspects.tel-a.includes = [den.aspects.telemetry-cluster den.aspects.tel-test];
        den.aspects.tel-b.includes = [den.aspects.telemetry-cluster den.aspects.tel-test];
      };

      nodes = {
        ca = "ca";
        tela = "tel-a";
        telb = "tel-b";
      };

      node = vmName: {
        nodes,
        lib,
        pkgs,
        ...
      }: let
        frontDoor =
          {
            ca = addressOf.tel-a;
            tela = addressOf.tel-a;
            telb = addressOf.tel-b;
          }.${
            vmName
          };
      in {
        security.pki.certificateFiles = ["${testPki}/public-root.crt"];
        networking.extraHosts = lib.mkAfter ''
          ${addressOf.ca} ca.gio.ninja crl.gio.ninja
          ${addressOf.tel-a} tel-a.gio.ninja
          ${addressOf.tel-b} tel-b.gio.ninja
          ${frontDoor} telemetry.gio.ninja push.telemetry.gio.ninja existing.gio.ninja
        '';
        environment.systemPackages =
          [pkgs.curl pkgs.netcat]
          ++ lib.optionals (vmName == "ca") (let
            tools = stepCa.tools {
              tel-a = nodes.tela.gio.mtls.certs;
              tel-b = nodes.telb.gio.mtls.certs;
            };
          in [tools.enroll tools.revoke]);
      };

      testScript = ''
        import json
        import shlex

        a_ip, b_ip = "${addressOf.tel-a}", "${addressOf.tel-b}"
        members = ((tela, "tel-a", a_ip), (telb, "tel-b", b_ip))
        tunnel = ${builtins.toJSON (lib.genAttrs members (peer: {
          vmselect = 21000 + 100 * lib.lists.findFirstIndex (m: m == peer) 0 members + 3;
          alertmanager = 21000 + 100 * lib.lists.findFirstIndex (m: m == peer) 0 members + 6;
        }))}

        start_all()
        ca.wait_for_unit("step-ca.service")
        ca.wait_for_open_port(443)
        ca.wait_for_unit("nginx.service")

        def enroll(m, host):
            out = ca.succeed(f"ca-enroll-host {host} mtls")
            print(out)
            paste = [l for l in out.splitlines() if l.startswith("sudo ")]
            assert len(paste) == 4, out
            m.wait_for_unit("multi-user.target")
            m.fail("systemctl is-failed caddy.service alertmanager.service vmagent.service systemd-journal-upload.service")
            for line in paste:
                m.succeed(f"bash -c {shlex.quote(line)}")
            for name in ("telemetry-node", "alertmanager", "vmagent", "journal-upload"):
                m.wait_for_file(f"/var/lib/mtls/{name}/cert.pem")
            m.wait_until_succeeds("test -z \"$(ls /var/lib/mtls/tokens)\"")

        for m, host, _ in members:
            enroll(m, host)
        for m, _, ip in members:
            m.wait_for_unit("caddy.service")
            m.wait_for_open_port(443, ip)
            for port in (8400, 8401, 8480, 8481, 9428, 9429, 9093):
                m.wait_for_open_port(port, ip)
            m.wait_for_unit("vmagent.service")

        def mint(cn, role, path):
            app = cn.split(".")[0]
            token = ca.succeed(
                f"step ca token {cn} --san spiffe://gio.ninja/ca/{app} --set role={role} "
                "--provisioner app --provisioner-password-file ${caDir}/provisioners/app/password "
                "--ca-url https://ca.gio.ninja --root ${caDir}/root.crt"
            ).strip()
            ca.succeed(
                f"step ca certificate --token {token} --ca-url https://ca.gio.ninja "
                f"--root ${caDir}/root.crt {cn} {path}.crt {path}.key"
            )

        def copy(src, dst, path):
            for ext in ("crt", "key"):
                pem = src.succeed(f"cat {path}.{ext}")
                dst.succeed(f"install -D -m 0600 /dev/stdin {path}.{ext} <<'EOF'\n{pem}EOF")

        for cn, role in (
            ("writer.ca", "telemetry-writer"),
            ("reader.ca", "telemetry-reader"),
            ("other.ca", "other-role"),
            ("intruder.ca", "telemetry-cluster"),
        ):
            mint(cn, role, f"/tmp/{cn.split('.')[0]}")

        def front(m, path, cert=None, ip=a_ip, args=""):
            auth = f"--cert /tmp/{cert}.crt --key /tmp/{cert}.key" if cert else ""
            return m.succeed(
                f"curl -sS -o /tmp/body -w '%{{http_code}}' {auth} {args} "
                f"--resolve telemetry.gio.ninja:443:{ip} 'https://telemetry.gio.ninja{path}' || true"
            ).strip()

        def promql(m, query):
            return json.loads(m.succeed(
                f"curl -sf http://127.0.0.1:8481/select/0/prometheus/api/v1/query --data-urlencode {shlex.quote('query=' + query)}"
            ))["data"]["result"]

        with subtest("the subject placeholder is CN,OU,O and every request logs it"):
            assert front(ca, "/metrics/insert/0/prometheus/api/v1/write", "writer", args="-d garbage") == "400"
            line = tela.succeed("tail -n1 '/var/log/caddy/access-https:__telemetry.gio.ninja.log'")
            entry = json.loads(line)
            print("client_subject:", entry["client_subject"])
            assert entry["client_subject"] == "CN=writer.ca,OU=telemetry-writer,O=app", entry

        with subtest("vmagent writes through the front door and lands on both members"):
            # The driver names each VM's host after its node (tela), not its den host.
            for m, _, _ in members:
                m.wait_until_succeeds(
                    "curl -sf http://127.0.0.1:8481/select/0/prometheus/api/v1/query "
                    "--data-urlencode 'query=up{job=\"vmstorage\",host=\"tela\"}' | grep -q '\"1\"'",
                    timeout=180,
                )
                m.wait_until_succeeds(
                    "curl -sf http://127.0.0.1:8481/select/0/prometheus/api/v1/query "
                    "--data-urlencode 'query=up{job=\"alertmanager\",host=\"telb\"}' | grep -q '\"1\"'",
                    timeout=180,
                )

        with subtest("journal-upload writes through the front door and lands on both members"):
            for m, _, _ in members:
                m.wait_until_succeeds(
                    "curl -sf http://127.0.0.1:9428/select/logsql/query -d 'query=_HOSTNAME:telb | limit 1' | grep -q telb",
                    timeout=180,
                )

        with subtest("roles and paths are enforced at the front door"):
            assert front(ca, "/metrics/insert/0/prometheus/api/v1/write", "reader", args="-d garbage") == "403"
            assert front(ca, "/metrics/insert/0/prometheus/api/v1/write", "other", args="-d garbage") == "403"
            assert front(ca, "/metrics/insert/0/prometheus/api/v1/import/prometheus", "writer", args="-d 'x 1'") == "403"
            assert front(ca, "/metrics/select/0/prometheus/api/v1/query?query=up", "writer") == "403"
            assert front(ca, "/logs/insert/jsonline", "writer", args="-d '{}'") == "403"
            assert front(ca, "/nothing", "writer") == "403"
            assert front(ca, "/metrics/select/0/prometheus/api/v1/query?query=up", "reader") == "200"
            assert '"host":"tela"' in ca.succeed("cat /tmp/body")
            assert front(ca, "/logs/select/logsql/query?query=*%20|%20limit%201", "reader") == "200"
            assert front(ca, "/metrics/select/0/prometheus/api/v1/query?query=up", "reader", ip=b_ip) == "200"
            assert front(ca, "/metrics/select/0/prometheus/api/v1/query?query=up") == "000"

        with subtest("a reader cannot delete series or reach admin endpoints"):
            for path in (
                "/metrics/select/0/prometheus/api/v1/admin/tsdb/delete_series?match[]=up",
                "/metrics/delete/0/prometheus/api/v1/admin/tsdb/delete_series?match[]=up",
                "/metrics/select/0/prometheus/api/v1/query/../admin/tsdb/delete_series?match[]=up",
                "/metrics/select/0/graphite/tags/delSeries?path=up",
                "/metrics/internal/resetRollupResultCache",
                "/logs/select/../delete/run_task",
                "/logs/select/vmui/",
            ):
                code = front(ca, path, "reader", args="-X POST --path-as-is -g")
                assert code == "403", f"{path}: {code}"
            assert promql(tela, 'up{job="vmstorage"}'), "series were deleted"

        with subtest("a caddy-l4 listener only lets member CNs through"):
            copy(ca, telb, "/tmp/intruder")
            # The listener advertises h2 by default but only relays bytes to plain
            # HTTP/1.1, so curl must not negotiate h2.
            node_cert = "--cert /var/lib/mtls/telemetry-node/cert.pem --key /var/lib/mtls/telemetry-node/key.pem"
            assert telb.succeed(f"curl -sf --http1.1 --cacert /etc/step/ca-root.crt {node_cert} https://tel-a.gio.ninja:8481/health") == "OK"
            telb.fail("curl -sf --http1.1 --cacert /etc/step/ca-root.crt --cert /tmp/intruder.crt --key /tmp/intruder.key https://tel-a.gio.ninja:8481/health")
            telb.fail("curl -sf --http1.1 --cacert /etc/step/ca-root.crt https://tel-a.gio.ninja:8481/health")

        with subtest("internal ports accept members only"):
            telb.succeed(f"nc -z -w3 {a_ip} 8481")
            ca.fail(f"nc -z -w3 {a_ip} 8481")
            ca.fail(f"nc -z -w3 {a_ip} 9094")

        with subtest("tunnels reach the peer's services"):
            assert tela.succeed(f"curl -sf http://127.0.0.1:{tunnel['tel-b']['vmselect']}/health") == "OK"
            tela.succeed(f"curl -sf http://127.0.0.1:{tunnel['tel-b']['alertmanager']}/-/ready")
            telb.succeed(f"curl -sf http://127.0.0.1:{tunnel['tel-a']['alertmanager']}/-/ready")

        def push(m, path, data, args=""):
            return m.succeed(
                f"curl -sS -o /dev/null -w '%{{http_code}}' {args} --data-binary {shlex.quote(data)} "
                f"'https://push.telemetry.gio.ninja{path}' || true"
            ).strip()

        with subtest("the push site takes unauthenticated pushes from inside and refuses outside"):
            assert push(tela, "/prometheus", 'pushed_metric{job="t"} 42') == "204"
            assert push(tela, "/prometheus?extra_label=source=evil", "evil_metric 1") == "204"
            assert push(tela, "/influx", "pushed_influx,job=t value=7") == "204"
            assert push(tela, "/logs", '{"_msg":"pushed line","job":"t"}') == "200"
            assert push(tela, "/elsewhere", "x 1") == "404"
            assert push(ca, "/prometheus", "x 1") == "403"
            tela.succeed("head -c 2000000 /dev/zero > /tmp/big")
            assert push(tela, "/prometheus", "", args="--data-binary @/tmp/big") == "413"
            for m, _, _ in members:
                m.wait_until_succeeds(
                    "curl -sf http://127.0.0.1:8481/select/0/prometheus/api/v1/query "
                    "--data-urlencode 'query=pushed_metric{source=\"push\"}' | grep -q '\"42\"'",
                    timeout=60,
                )
                m.wait_until_succeeds(
                    "curl -sf http://127.0.0.1:8481/select/0/prometheus/api/v1/query "
                    "--data-urlencode 'query=pushed_influx_value{source=\"push\"}' | grep -q '\"7\"'",
                    timeout=60,
                )
                m.wait_until_succeeds(
                    "curl -sf http://127.0.0.1:9428/select/logsql/query -d 'query=source:push' | grep -q 'pushed line'",
                    timeout=60,
                )
            assert promql(tela, "evil_metric")[0]["metric"]["source"] == "push"

        with subtest("writes and queries survive losing one vmstorage"):
            tela.succeed("systemctl stop vmstorage.service")
            assert push(tela, "/prometheus", "after_stop 1") == "204"
            for m, _, _ in members:
                m.wait_until_succeeds(
                    "curl -sf http://127.0.0.1:8481/select/0/prometheus/api/v1/query "
                    "--data-urlencode 'query=after_stop' | grep -q '\"1\"'",
                    timeout=60,
                )
            assert front(ca, "/metrics/select/0/prometheus/api/v1/query?query=pushed_metric", "reader") == "200"
            assert "42" in ca.succeed("cat /tmp/body")
            tela.succeed("systemctl start vmstorage.service")

        with subtest("strict SNI-Host enforcement leaves other vhosts working"):
            assert tela.succeed("curl -sf https://existing.gio.ninja/") == "existing-ok"
            assert tela.succeed(
                "curl -s -o /dev/null -w '%{http_code}' -H 'Host: existing.gio.ninja' https://push.telemetry.gio.ninja/"
            ) == "421"

        write = "/metrics/insert/0/prometheus/api/v1/write"

        def front_refused(cert, ip=a_ip):
            ca.wait_until_succeeds(
                f"test \"$(curl -s -o /dev/null -w '%{{http_code}}' --cert /tmp/{cert}.crt --key /tmp/{cert}.key "
                f"--resolve telemetry.gio.ninja:443:{ip} -d garbage https://telemetry.gio.ninja{write})\" = 000",
                timeout=60,
            )

        def l4_health(cert_args):
            return f"curl -sf --http1.1 --cacert /etc/step/ca-root.crt {cert_args} https://tel-a.gio.ninja:8481/health"

        with subtest("a revoked certificate is refused at the front door and a caddy-l4 listener"):
            tela.succeed("curl -sf http://crl.gio.ninja/ -o /tmp/crl.der")
            crl = tela.succeed("openssl crl -inform der -in /tmp/crl.der -noout -text")
            assert "Issuing Distribution Point: critical" in crl, crl
            mint("writer2.ca", "telemetry-writer", "/tmp/writer2")
            # A second certificate under tel-b's node CN, so revoking it leaves tel-b's own one working.
            mint("telemetry-node.tel-b", "telemetry-cluster", "/tmp/spare-node")
            copy(ca, telb, "/tmp/spare-node")
            spare_cert = "--cert /tmp/spare-node.crt --key /tmp/spare-node.key"
            assert front(ca, write, "writer", args="-d garbage") == "400"
            assert front(ca, write, "writer2", args="-d garbage") == "400"
            assert telb.succeed(l4_health(spare_cert)) == "OK"
            for cn, path in (("writer.ca", "/tmp/writer"), ("telemetry-node.tel-b", "/tmp/spare-node")):
                serial = ca.succeed(f"step certificate inspect --format json {path}.crt | jq -r .serial_number").strip()
                out = ca.succeed(f"ca-revoke {cn}")
                assert serial in out, out
            front_refused("writer")
            telb.wait_until_fails(l4_health(spare_cert), timeout=60)
            assert front(ca, write, "writer2", args="-d garbage") == "400"
            assert telb.succeed(l4_health(node_cert)) == "OK"

        with subtest("a member that cannot fetch the CRL refuses every client"):
            telb.succeed("systemctl stop caddy.service")
            telb.succeed("find /var/lib/caddy/crl -mindepth 1 -delete")
            telb.succeed(
                "nft add table inet crl-block && "
                "nft add chain inet crl-block out '{ type filter hook output priority 0; }' && "
                "nft add rule inet crl-block out ip daddr ${addressOf.ca} tcp dport 80 reject"
            )
            telb.succeed("systemctl start caddy.service")
            telb.wait_for_open_port(443, b_ip)
            front_refused("writer2", ip=b_ip)
            telb.wait_until_succeeds("journalctl -u caddy | grep -q 'CRL defined in CDP was not loaded'", timeout=30)
            telb.succeed("nft delete table inet crl-block")
            ca.wait_until_succeeds(
                f"test \"$(curl -s -o /dev/null -w '%{{http_code}}' --cert /tmp/writer2.crt --key /tmp/writer2.key "
                f"--resolve telemetry.gio.ninja:443:{b_ip} -d garbage https://telemetry.gio.ninja{write})\" = 400",
                timeout=60,
            )
      '';
    };
  };
}
