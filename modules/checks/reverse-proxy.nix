# Boots one den host and drives the fleet.services reverse-proxy renderer end to
# end over plain HTTP (endpoint.tls = false) — so no Cloudflare token is needed.
# Exercises every VM-runnable option: host:port + unix-socket + h2c backends, the
# escape-hatch ladder (auto proxy, appended extraConfig, full custom routing via
# proxy = false), a custom listen port, a raw coexisting Caddy vhost, and that a
# DNS-only endpoint produces no vhost + no credential is loaded. (tls = true is the
# only option not exercised — it needs the live Cloudflare token.)
_: {
  perSystem.denTests.reverse-proxy = {
    fleet = _: {
      den.hosts.x86_64-linux.web = {
        ssh.hostKey = null;
        services = {
          # rung 1: one-liner host:port proxy.
          simple.endpoint = {
            tls = false;
            port = 80;
            backend = {
              host = "127.0.0.1";
              port = 8080;
            };
          };
          # unix-socket backend.
          sock.endpoint = {
            tls = false;
            port = 80;
            backend.socket = "/run/up.sock";
          };
          # h2c (HTTP/2 cleartext) backend.
          h2c.endpoint = {
            tls = false;
            port = 80;
            backend = {
              host = "127.0.0.1";
              port = 8081;
              protocol = "h2c";
            };
          };
          # rung 3: extraConfig appended on top of the auto reverse_proxy.
          hdr.endpoint = {
            tls = false;
            port = 80;
            backend = {
              host = "127.0.0.1";
              port = 8080;
            };
            extraConfig = "header X-Test injected";
          };
          # rung 4: take over routing entirely (no auto reverse_proxy).
          custom.endpoint = {
            tls = false;
            port = 80;
            proxy = false;
            extraConfig = ''respond "custom-handler" 200'';
          };
          # custom public listen port.
          altport.endpoint = {
            tls = false;
            port = 8888;
            backend = {
              host = "127.0.0.1";
              port = 8080;
            };
          };
          # DNS-only: no proxy, no extraConfig -> no vhost emitted.
          dnsonly.endpoint = {
            tls = false;
            proxy = false;
          };
        };
      };

      den.aspects.web.nixos = {pkgs, ...}: let
        # An HTTP/1.1 server bound to a unix socket (caddy connects over unix//).
        sockServer = pkgs.writeText "sockserver.py" ''
          import http.server, socketserver, os
          SOCK = "/run/up.sock"
          try:
              os.remove(SOCK)
          except FileNotFoundError:
              pass
          class H(http.server.BaseHTTPRequestHandler):
              def do_GET(self):
                  body = b"socket-ok"
                  self.send_response(200)
                  self.send_header("Content-Length", str(len(body)))
                  self.end_headers()
                  self.wfile.write(body)
              def log_message(self, *a):
                  pass
          class Srv(socketserver.UnixStreamServer):
              def get_request(self):
                  conn, _ = self.socket.accept()
                  return conn, ("unix", 0)
          srv = Srv(SOCK, H)
          os.chmod(SOCK, 0o666)
          srv.serve_forever()
        '';
        h2cRoot = pkgs.writeTextDir "ok" "h2c-ok";
      in {
        system.stateVersion = "25.11";

        # TCP upstream for the host:port proxies.
        systemd.services.upstream = {
          wantedBy = ["multi-user.target"];
          serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 -m http.server 8080 --bind 127.0.0.1 --directory ${pkgs.writeTextDir "index.html" "upstream-ok"}";
        };

        # Unix-socket upstream.
        systemd.services.upstream-sock = {
          wantedBy = ["multi-user.target"];
          serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 ${sockServer}";
        };

        # h2c (cleartext HTTP/2) upstream.
        systemd.services.upstream-h2c = {
          wantedBy = ["multi-user.target"];
          serviceConfig.ExecStart = "${pkgs.nghttp2}/bin/nghttpd --no-tls -d ${h2cRoot} 8081";
        };

        # rung 5: a fully bespoke raw Caddy vhost must coexist untouched.
        services.caddy.virtualHosts."http://raw.gio.ninja".extraConfig = ''respond "raw-ok" 200'';
      };
    };

    nodes.web = "web";
    node = _: {pkgs, ...}: {environment.systemPackages = [pkgs.curl];};

    testScript = ''
      web.start()
      web.wait_for_unit("upstream.service")
      web.wait_for_unit("upstream-sock.service")
      web.wait_for_unit("upstream-h2c.service")
      web.wait_for_unit("caddy.service")
      web.wait_for_open_port(8080)
      web.wait_for_open_port(8081)
      web.wait_until_succeeds("test -S /run/up.sock")
      web.wait_for_open_port(80)
      web.wait_for_open_port(8888)

      def get(host, port=80, path="/"):
          return web.succeed(f"curl -sS -H 'Host: {host}.gio.ninja' http://localhost:{port}{path}")

      with subtest("rung 1: auto reverse_proxy reaches the upstream"):
          assert "upstream-ok" in get("simple"), "simple proxy failed"

      with subtest("unix-socket backend"):
          assert "socket-ok" in get("sock"), "socket proxy failed"

      with subtest("h2c backend"):
          assert "h2c-ok" in get("h2c", path="/ok"), "h2c proxy failed"

      with subtest("rung 3: appended extraConfig adds a header on top of the proxy"):
          out = web.succeed("curl -sS -D - -o /dev/null -H 'Host: hdr.gio.ninja' http://localhost/")
          assert "X-Test: injected" in out, f"header missing: {out!r}"

      with subtest("rung 4: proxy = false custom handler responds"):
          assert "custom-handler" in get("custom"), "custom handler failed"

      with subtest("custom listen port is served"):
          assert "upstream-ok" in get("altport", 8888), "altport failed"

      with subtest("rung 5: raw Caddy vhost coexists"):
          assert "raw-ok" in get("raw"), "raw vhost failed"

      with subtest("DNS-only endpoint emits no Caddy site"):
          # Caddy returns an empty 200 for an unmatched Host, so inspect the
          # loaded config directly via the admin API instead of the response.
          cfg = web.succeed("curl -sS http://localhost:2019/config/")
          assert "simple.gio.ninja" in cfg, "sanity: a real vhost should be present"
          assert "dnsonly" not in cfg, "DNS-only endpoint must not produce a Caddy site"

      with subtest("all-HTTP: Caddy loaded no Cloudflare credential"):
          web.fail("systemctl show caddy.service -p LoadCredentialEncrypted | grep -q caddy-cloudflare")
    '';
  };
}
