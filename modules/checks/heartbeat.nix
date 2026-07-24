# Boots one host running the heartbeat collector against a mock Healthchecks
# receiver and proves the verdict pipeline end to end: a healthy host POSTs to the
# base ping URL with an OK snapshot; failing a unit flips the aggregator's verdict
# so it POSTs to <url>/fail with the reason (FAIL failed_units) in the body. The
# HC URL is delivered as a plaintext systemd credential (standing in for the
# agevault-encrypted blob), and the agevault manifest is stubbed so the
# fleet.credentials assertion is satisfied.
_: {
  perSystem.denTests.heartbeat = {
    fleet = {den, ...}: {
      den.hosts.x86_64-linux.srv.ssh.hostKey = null;
      den.aspects.srv = {
        includes = [den.aspects.heartbeat];
        nixos = {
          lib,
          pkgs,
          ...
        }: let
          mock = pkgs.writeText "hc-mock.py" ''
            import http.server, socketserver

            class H(http.server.BaseHTTPRequestHandler):
                def do_POST(self):
                    n = int(self.headers.get("Content-Length", "0"))
                    body = self.rfile.read(n).decode("utf-8", "replace")
                    with open("/tmp/hc.log", "a") as f:
                        f.write("POST %s\n%s\n===\n" % (self.path, body))
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(b"OK")

                def log_message(self, *a):
                    pass

            socketserver.TCPServer(("127.0.0.1", 8000), H).serve_forever()
          '';
        in {
          system.stateVersion = "25.11";

          # Stub the names-only agevault manifest so fleet.credentials.needs
          # (healthcheck_url, set by the heartbeat aspect) resolves.
          fleet.credentials.manifestFile = builtins.toFile "manifest.toml" ''
            srv = ["healthcheck_url"]
          '';

          # Trim to signals a VM satisfies deterministically; fast cadence.
          gio.heartbeat = {
            intervalSeconds = 2;
            pushSeconds = 4;
            checkInternet = false;
            checkSshCert = false;
            diskUsedPercent = 99;
          };

          # Deliver the mock ping URL as a plaintext credential in place of the
          # agevault-encrypted blob the real service loads.
          environment.etc."hc-url".text = "http://127.0.0.1:8000/ping";
          systemd.services.heartbeat.serviceConfig = {
            LoadCredentialEncrypted = lib.mkForce [];
            LoadCredential = ["healthcheck_url:/etc/hc-url"];
          };

          systemd.services.hc-mock = {
            wantedBy = ["multi-user.target"];
            before = ["heartbeat.service"];
            serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 ${mock}";
          };

          # A unit we fail on demand to drive failed_units > 0.
          systemd.services.boom.serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.coreutils}/bin/false";
          };
        };
      };
    };

    nodes.srv = "srv";

    testScript = ''
      start_all()
      srv.wait_for_unit("hc-mock.service")
      srv.wait_for_unit("heartbeat.service")

      with subtest("healthy host pings the base URL with an OK snapshot"):
          srv.wait_until_succeeds("grep -q '^POST /ping$' /tmp/hc.log")
          srv.wait_until_succeeds("grep -qE 'OK +failed_units' /tmp/hc.log")

      with subtest("cold start is silent — first ping is healthy, never a stale /fail"):
          srv.succeed("head -1 /tmp/hc.log | grep -q '^POST /ping$'")

      with subtest("a failed unit flips the verdict to /fail with the reason"):
          srv.execute("systemctl start boom.service")
          srv.wait_until_succeeds("grep -q '^POST /ping/fail$' /tmp/hc.log")
          srv.wait_until_succeeds("grep -qE 'FAIL +failed_units' /tmp/hc.log")
    '';
  };
}
