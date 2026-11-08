# gio.mtls against a real step-ca built from strontium's own pieces (provisioner
# flags, templates, ca.json settings, CRL endpoint and operator tools): two
# hosts enroll through ca-enroll-host, talk mTLS to each other, renew, drift and
# get revoked.
{inputs, ...}: {
  perSystem = {
    pkgs,
    lib,
    ...
  }: let
    stepCa = import ./_step-ca.nix {inherit pkgs lib inputs;};
    inherit (stepCa) caDir step pki;
    caTools = stepCa.tools;

    echoServer = pkgs.writeShellApplication {
      name = "echo-server";
      runtimeInputs = [pkgs.openssl];
      text = ''
        c="$CREDENTIALS_DIRECTORY"
        exec openssl s_server -accept 8443 -www -quiet \
          -cert "$c/mtls-echo-cert" -cert_chain "$c/mtls-echo-cert" -key "$c/mtls-echo-key" \
          -CAfile "$c/mtls-ca" -Verify 2 -verify_return_error
      '';
    };
    echoClient = pkgs.writeShellApplication {
      name = "echo-client";
      runtimeInputs = [pkgs.curl];
      text = ''
        c="$CREDENTIALS_DIRECTORY"
        curl -sS --fail --cert "$c/mtls-probe-cert" --key "$c/mtls-probe-key" \
          --cacert "$c/mtls-ca" https://mtls-a.gio.ninja:8443/ -o /var/lib/echo-client/out
      '';
    };
  in {
    denTests.fleet-mtls = {
      fleet = _: {
        den.hosts.x86_64-linux = {
          ca.ssh.enable = false;
          mtls-a.ssh.enable = false;
          mtls-b.ssh.enable = false;
        };
        fleet.nfs.caRoot = "${pki}/root.crt";

        den.aspects.ca.nixos = stepCa.caModule;

        den.aspects.mtls-a.nixos = {lib, ...}: {
          system.stateVersion = "25.11";
          gio.mtls.certs.echo = {
            role = "test-server";
            serverHostnames = ["mtls-a.gio.ninja"];
            services = ["echo-server"];
            onRenew = "restart";
          };
          systemd.services.echo-server = {
            wantedBy = ["multi-user.target"];
            serviceConfig.ExecStart = lib.getExe echoServer;
          };
          networking.firewall.allowedTCPPorts = [8443];
          specialisation.drift.configuration.gio.mtls.certs.echo.role = lib.mkForce "other-role";
        };

        den.aspects.mtls-b.nixos = _: {
          system.stateVersion = "25.11";
          gio.mtls.certs.probe = {
            role = "test-client";
            services = ["echo-client.service"];
            onRenew = "restart";
          };
          systemd.services.echo-client.serviceConfig = {
            Type = "oneshot";
            StateDirectory = "echo-client";
            ExecStart = lib.getExe echoClient;
          };
        };
      };

      nodes = {
        ca = "ca";
        a = "mtls-a";
        b = "mtls-b";
      };

      node = vmName: {
        nodes,
        lib,
        ...
      }: {
        # Here, not in the aspect: only the test driver knows a's address.
        gio.mtls.certs = lib.optionalAttrs (vmName == "a") {
          echo.serverAddresses = [nodes.a.networking.primaryIPAddress];
        };
        networking.extraHosts = lib.mkAfter ''
          ${nodes.ca.networking.primaryIPAddress} ca.gio.ninja crl.gio.ninja
          ${nodes.a.networking.primaryIPAddress} mtls-a.gio.ninja
        '';
        environment.systemPackages = lib.optionals (vmName == "ca") (let
          tools = caTools {
            mtls-a = nodes.a.gio.mtls.certs;
            mtls-b = nodes.b.gio.mtls.certs;
          };
        in [tools.enroll tools.revoke]);
      };

      testScript = ''
        import json
        import shlex

        start_all()
        ca.wait_for_unit("step-ca.service")
        ca.wait_for_open_port(443)
        ca.wait_for_unit("nginx.service")
        a.wait_for_unit("multi-user.target")
        b.wait_for_unit("multi-user.target")

        def inspect(m, path):
            return json.loads(m.succeed(f"${step} certificate inspect --format json {path}"))

        a_ip = a.succeed("ip -4 -o addr show dev eth1 | awk '{print $4}' | cut -d/ -f1").strip()

        def identity(m, name):
            c = inspect(m, f"/var/lib/mtls/{name}/cert.pem")
            san = c["extensions"].get("subject_alt_name", {})
            return {
                "subject": c["subject"],
                "dns": san.get("dns_names", []),
                "ip": san.get("ip_addresses", []),
                "uri": san.get("uniform_resource_identifiers", []),
                "cdp": c["extensions"].get("crl_distribution_points"),
                "eku": c["extensions"].get("extended_key_usage"),
                "serial": c["serial_number"],
            }

        def mint(cn, *extra):
            return ca.succeed(
                f"step ca token {cn} --san spiffe://gio.ninja/mtls-b/x {' '.join(extra)} "
                "--provisioner app --provisioner-password-file ${caDir}/provisioners/app/password "
                "--ca-url https://ca.gio.ninja --root ${caDir}/root.crt"
            ).strip()

        def invocation(m, unit):
            return m.succeed(f"systemctl show -p InvocationID --value {unit}").strip()

        with subtest("the app provisioner and CA settings land in ca.json idempotently"):
            conf = json.loads(ca.succeed("cat ${caDir}/ca.json"))
            app = next(p for p in conf["authority"]["provisioners"] if p["name"] == "app")
            assert app["type"] == "JWK" and app["encryptedKey"], app
            assert app["claims"]["enableSSHCA"] is False, app["claims"]
            assert app["claims"]["maxTLSCertDuration"].startswith("168h"), app["claims"]
            assert not app["claims"].get("allowRenewalAfterExpiry"), app["claims"]
            assert "crlDistributionPoints" in app["options"]["x509"]["template"]
            nfs = next(p for p in conf["authority"]["provisioners"] if p["name"] == "nfs")
            assert '"organization": "nfs"' in nfs["options"]["x509"]["template"]
            assert conf["logger"]["format"] == "json", conf["logger"]
            assert conf["crl"] == {
                "enabled": True,
                "generateOnRevoke": True,
                "cacheDuration": "24h",
                "idpURL": "http://crl.gio.ninja/",
            }, conf["crl"]
            ca.succeed("cp ${caDir}/ca.json /tmp/before.json")
            ca.succeed("step-ca-provisioners")
            ca.succeed("cmp /tmp/before.json ${caDir}/ca.json")

        with subtest("unenrolled hosts keep the renewer and consumers dormant"):
            a.succeed("systemctl start mtls-renew.service")
            assert a.succeed("systemctl show -p ConditionResult --value mtls-renew.service").strip() == "no"
            a.fail("test -e /var/lib/mtls/echo/cert.pem")
            assert a.succeed("systemctl show -p ConditionResult --value echo-server.service").strip() == "no"
            a.fail("systemctl is-failed echo-server.service")

        with subtest("ca-enroll-host refuses hosts and roles nothing declares"):
            ca.fail("ca-enroll-host ca mtls")
            ca.fail("ca-enroll-host mtls-b mtls --role test-server")

        def enroll(m, host, name):
            out = ca.succeed(f"ca-enroll-host {host} mtls")
            print(out)
            paste = [l for l in out.splitlines() if l.startswith("sudo ")]
            assert len(paste) == 1, out
            assert out.index("CN=") < out.index(paste[0]), "summary must precede the paste block"
            m.succeed(f"bash -c {shlex.quote(paste[0])}")
            m.wait_for_file(f"/var/lib/mtls/{name}/cert.pem")
            m.wait_until_succeeds("test -z \"$(ls /var/lib/mtls/tokens)\"")
            return out

        with subtest("enrollment issues the declared identity"):
            out = enroll(a, "mtls-a", "echo")
            assert f"CN=echo.mtls-a role=test-server SANs=spiffe://gio.ninja/mtls-a/echo, mtls-a.gio.ninja, {a_ip}" in out, out
            a.wait_for_unit("echo-server.service")
            echo = identity(a, "echo")
            assert echo["subject"] == {
                "common_name": ["echo.mtls-a"],
                "organization": ["app"],
                "organizational_unit": ["test-server"],
            }, echo["subject"]
            assert echo["dns"] == ["mtls-a.gio.ninja"], echo
            assert echo["ip"] == [a_ip], echo
            assert echo["uri"] == ["spiffe://gio.ninja/mtls-a/echo"], echo
            assert echo["cdp"] == ["http://crl.gio.ninja/"], echo
            assert echo["eku"].get("server_auth") and echo["eku"].get("client_auth"), echo

            enroll(b, "mtls-b", "probe")
            probe = identity(b, "probe")
            assert probe["subject"]["organizational_unit"] == ["test-client"], probe
            assert probe["dns"] == [] and probe["ip"] == [], probe
            assert probe["cdp"] == ["http://crl.gio.ninja/"], probe

        with subtest("the two hosts authenticate each other with mTLS"):
            # Enrolling b restarted echo-client, which already called a.
            out = b.succeed("cat /var/lib/echo-client/out")
            assert "Subject: O=app, OU=test-client, CN=probe.mtls-b" in out, out
            b.succeed("systemctl restart echo-client.service")
            # Dialled by IP, the server cert must verify through its IP SAN.
            out = b.succeed(
                "curl -sS --fail --cacert ${pki}/root.crt --cert /var/lib/mtls/probe/cert.pem "
                f"--key /var/lib/mtls/probe/key.pem https://{a_ip}:8443/"
            )
            assert "CN=probe.mtls-b" in out, out
            b.fail(
                "curl -sS --fail --cacert ${pki}/root.crt https://mtls-a.gio.ninja:8443/"
            )

        with subtest("renewal keeps the identity and triggers onRenew"):
            before = invocation(a, "echo-server.service")
            a.succeed("systemctl start mtls-renew.service")
            renewed = identity(a, "echo")
            assert renewed["serial"] != echo["serial"], "renewal kept the old serial"
            assert {k: v for k, v in renewed.items() if k != "serial"} == {
                k: v for k, v in echo.items() if k != "serial"
            }, renewed
            assert invocation(a, "echo-server.service") != before, "echo-server was not restarted"
            a.succeed("systemctl is-active echo-server.service")
            a.succeed("stat -c '%a %U %G' /var/lib/mtls/echo/key.pem | grep -x '640 root root'")

        with subtest("the role comes only from the signed token"):
            token = mint("x.mtls-b")
            b.fail(
                f"${step} ca certificate --token {token} --set role=admin --ca-url https://ca.gio.ninja "
                "--root /etc/step/ca-root.crt x.mtls-b /tmp/x.pem /tmp/x.key"
            )
            b.fail("test -e /tmp/x.pem")
            token = mint("x.mtls-b", "--set role=test-client")
            b.succeed(
                f"${step} ca certificate --token {token} --set role=admin --ca-url https://ca.gio.ninja "
                "--root /etc/step/ca-root.crt x.mtls-b /tmp/x.pem /tmp/x.key"
            )
            ou = inspect(b, "/tmp/x.pem")["subject"]["organizational_unit"]
            assert ou == ["test-client"], ou

        with subtest("ca-revoke revokes the newest serial and the CRL lists it"):
            b.succeed("systemctl start mtls-renew.service")
            current = identity(b, "probe")["serial"]
            assert current != probe["serial"], "b did not renew"
            out = ca.succeed("ca-revoke probe.mtls-b")
            assert current in out, out
            b.succeed("curl -sS --fail http://crl.gio.ninja/ -o /tmp/crl.der")
            crl = json.loads(b.succeed("${step} crl inspect --insecure --format json /tmp/crl.der"))
            revoked = [r["serial_number"] for r in crl.get("revoked_certificates", [])]
            assert current in revoked, revoked
            assert probe["serial"] not in revoked, revoked
            b.fail("systemctl start mtls-renew.service")

        with subtest("a changed role fails the drift check instead of renewing"):
            serial = identity(a, "echo")["serial"]
            a.succeed("/run/current-system/specialisation/drift/bin/switch-to-configuration test")
            a.fail("systemctl start mtls-renew.service")
            journal = a.succeed("journalctl -u mtls-renew.service --no-pager")
            assert "echo: identity drift" in journal, journal
            assert "mtls-renew failed for: echo" in journal, journal
            assert identity(a, "echo")["serial"] == serial, "a drifted cert was renewed"
      '';
    };
  };
}
