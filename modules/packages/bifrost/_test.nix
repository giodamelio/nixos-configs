# The real Caddy binary end to end over HTTPS: webhook checkers, the catch-all,
# and a full OAuth authorization (fake Pocket ID, consent, token, a guarded
# upstream, admin revocation). DNS is faked with /etc/hosts.
{bifrost}: {
  pkgs,
  lib,
  ...
}: let
  domain = "external.test";
  hosts = map (h: "${h}.${domain}") ["auth" "notes" "hooks" "deploy" "events" "stream" "unknown"];
  port = 52793;

  webhookSecret = "github-webhook-secret";
  deployToken = "deploy-token";

  python = pkgs.python3.withPackages (ps: [ps.pyjwt ps.cryptography]);

  fakeOP = pkgs.writeText "fake-op.py" ''
    import json, secrets, time, urllib.parse
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

    import jwt
    from cryptography.hazmat.primitives.asymmetric import rsa
    from jwt.algorithms import RSAAlgorithm

    ISS = "http://op.test:8000"
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    jwk = json.loads(RSAAlgorithm.to_jwk(key.public_key()))
    jwk.update(kid="op", alg="RS256", use="sig")
    codes = {}


    class Handler(BaseHTTPRequestHandler):
        def reply(self, status, body=None, headers=None):
            data = json.dumps(body).encode() if body is not None else b""
            self.send_response(status)
            for k, v in (headers or {}).items():
                self.send_header(k, v)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            u = urllib.parse.urlparse(self.path)
            q = urllib.parse.parse_qs(u.query)
            if u.path == "/.well-known/openid-configuration":
                self.reply(200, {
                    "issuer": ISS,
                    "authorization_endpoint": ISS + "/authorize",
                    "token_endpoint": ISS + "/token",
                    "jwks_uri": ISS + "/jwks",
                    "id_token_signing_alg_values_supported": ["RS256"],
                })
            elif u.path == "/jwks":
                self.reply(200, {"keys": [jwk]})
            elif u.path == "/authorize":
                if q.get("prompt") != ["login"]:
                    return self.reply(400, {"error": "bifrost did not force a fresh login"})
                code = secrets.token_hex(8)
                codes[code] = q["nonce"][0]
                loc = q["redirect_uri"][0] + "?" + urllib.parse.urlencode({"code": code, "state": q["state"][0]})
                self.reply(302, None, {"Location": loc})
            else:
                self.reply(404, {})

        def do_POST(self):
            form = urllib.parse.parse_qs(self.rfile.read(int(self.headers["Content-Length"])).decode())
            nonce = codes.pop(form["code"][0], None)
            if nonce is None:
                return self.reply(400, {"error": "invalid_grant"})
            now = int(time.time())
            idt = jwt.encode({
                "iss": ISS, "aud": "bifrost", "sub": "user-1", "iat": now, "exp": now + 3600,
                "nonce": nonce, "auth_time": now, "email": "gio@example.test", "name": "Gio",
                "preferred_username": "gio", "groups": ["bifrost"],
            }, key, algorithm="RS256", headers={"kid": "op"})
            self.reply(200, {"access_token": "op", "token_type": "Bearer", "expires_in": 3600, "id_token": idt})


    ThreadingHTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
  '';

  echo = pkgs.writeText "echo.py" ''
    import json
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


    class Handler(BaseHTTPRequestHandler):
        def handle_any(self):
            n = int(self.headers.get("Content-Length") or 0)
            body = self.rfile.read(n).decode() if n else ""
            data = json.dumps({"path": self.path, "headers": dict(self.headers), "body": body}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        do_GET = do_POST = handle_any


    ThreadingHTTPServer(("127.0.0.1", 9000), Handler).serve_forever()
  '';

  verify = pkgs.writeText "verify.py" ''
    import json, sys
    import jwt

    token, jwks_file, audience = sys.argv[1:]
    keys = {k["kid"]: jwt.PyJWK(k) for k in json.load(open(jwks_file))["keys"]}
    kid = jwt.get_unverified_header(token)["kid"]
    claims = jwt.decode(token, keys[kid].key, algorithms=["EdDSA"], audience=audience)
    print(json.dumps(claims))
  '';

  caddyfile = pkgs.writeText "Caddyfile" ''
    {
      admin off
      skip_install_trust
      http_port 52792
      https_port ${toString port}
      auto_https disable_redirects
      log {
        level INFO
      }
      bifrost {
        issuer https://auth.${domain}
        login {
          oidc_issuer http://op.test:8000
          client_id bifrost
          client_secret_file /etc/bifrost/op-client-secret
          allowed_groups bifrost
        }
        token_key_file /etc/bifrost/token-key
        nats {
          url nats://127.0.0.1:4222
        }
      }
    }

    *.${domain} {
      tls internal

      @auth host auth.${domain}
      handle @auth {
        route {
          rate_limit {
            zone auth {
              key {remote_host}
              events 60
              window 1m
            }
          }
          bifrost_authserver {
            admin_networks 192.168.0.0/16
          }
        }
      }

      @notes host notes.${domain}
      handle @notes {
        route {
          rate_limit {
            zone notes {
              key {remote_host}
              events 20
              window 1m
            }
          }
          bifrost_guard oauth {
            host notes.${domain}
            scopes notes:read notes:write
            require notes:read
          }
          rewrite * /mcp{uri}
          reverse_proxy 127.0.0.1:9000 {
            header_up X-Forwarded-User {vars.bifrost_user}
          }
        }
      }

      @hooks host hooks.${domain}
      handle @hooks {
        route {
          bifrost_guard hmac {
            header X-Hub-Signature-256
            prefix sha256=
            secret_file /etc/bifrost/webhook-secret
          }
          reverse_proxy 127.0.0.1:9000
        }
      }

      @deploy host deploy.${domain}
      handle @deploy {
        route {
          bifrost_guard bearer {
            token_file /etc/bifrost/deploy-token
          }
          reverse_proxy 127.0.0.1:9000
        }
      }

      @events host events.${domain}
      handle @events {
        route {
          bifrost_guard hmac {
            header X-Hub-Signature-256
            prefix sha256=
            secret_file /etc/bifrost/webhook-secret
          }
          bifrost_nats {
            subject bifrost.requests.github
          }
        }
      }

      @stream host stream.${domain}
      handle @stream {
        route {
          bifrost_guard bearer {
            token_file /etc/bifrost/deploy-token
          }
          bifrost_nats {
            subject bifrost.js.deploy
            jetstream
          }
        }
      }

      handle {
        bifrost_reject
      }
    }
  '';
in {
  name = "bifrost";

  nodes = {
    server = {
      networking.firewall.allowedTCPPorts = [port 8000];
      networking.hosts."127.0.0.1" = hosts ++ ["op.test"];
      environment.systemPackages = [pkgs.curl pkgs.natscli python];

      services.nats = {
        enable = true;
        jetstream = true;
      };

      environment.etc = {
        "bifrost/token-key".text = "0123456789abcdef0123456789abcdef0123456789abcdef";
        "bifrost/op-client-secret".text = "op-client-secret";
        "bifrost/webhook-secret".text = webhookSecret;
        "bifrost/deploy-token".text = deployToken;
      };

      systemd.services = {
        fake-op = {
          wantedBy = ["multi-user.target"];
          serviceConfig.ExecStart = "${python}/bin/python3 ${fakeOP}";
        };
        echo = {
          wantedBy = ["multi-user.target"];
          serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 ${echo}";
        };
        bifrost = {
          wantedBy = ["multi-user.target"];
          after = ["fake-op.service" "nats.service"];
          environment = {
            XDG_DATA_HOME = "/var/lib/bifrost";
            XDG_CONFIG_HOME = "/var/lib/bifrost";
          };
          serviceConfig = {
            ExecStart = "${lib.getExe bifrost} run --config ${caddyfile} --adapter caddyfile";
            DynamicUser = true;
            StateDirectory = "bifrost";
          };
        };
      };
    };

    client = {nodes, ...}: {
      networking.hosts.${nodes.server.networking.primaryIPAddress} = hosts ++ ["op.test"];
      environment.systemPackages = [pkgs.curl];
    };
  };

  testScript = ''
    import base64, hashlib, hmac, json, re, urllib.parse

    BASE = "https://{}.${domain}:${toString port}"
    CURL = "curl -sk --max-time 10"
    REDIRECT = "http://127.0.0.1:9999/cb"

    def url(host, path=""):
        return BASE.format(host) + path

    def status(cmd):
        return int(client.succeed(f"{CURL} -o /dev/null -w '%{{http_code}}' {cmd}"))

    start_all()
    server.wait_for_unit("fake-op.service")
    server.wait_for_unit("echo.service")
    server.wait_for_unit("bifrost.service")
    server.wait_for_open_port(${toString port})
    server.wait_for_open_port(8000)
    client.wait_until_succeeds(f"{CURL} -o /dev/null {url('unknown')}", timeout=60)

    with subtest("unknown hosts hit the catch-all"):
        assert status(url("unknown", "/wp-login.php")) == 404

    with subtest("hmac: a valid signature reaches the upstream with the body intact"):
        body = '{"zen":"hello"}'
        sig = "sha256=" + hmac.new(b"${webhookSecret}", body.encode(), hashlib.sha256).hexdigest()
        out = json.loads(client.succeed(f"{CURL} -H 'X-Hub-Signature-256: {sig}' -H 'Content-Type: application/json' --data '{body}' {url('hooks', '/github')}"))
        assert out["body"] == body, out
        assert status(f"-H 'X-Hub-Signature-256: sha256=00' --data '{body}' {url('hooks', '/github')}") == 401
        assert status(f"--data '{body}' {url('hooks', '/github')}") == 401

    with subtest("bearer: only the right token passes"):
        assert status(f"-X POST -H 'Authorization: Bearer ${deployToken}' {url('deploy', '/reconcile')}") == 200
        assert status(f"-X POST -H 'Authorization: Bearer nope' {url('deploy', '/reconcile')}") == 401

    with subtest("bifrost_nats publishes a verified webhook as JSON"):
        server.wait_for_unit("nats.service")
        server.succeed("systemd-run --unit=natsub -- ${pkgs.runtimeShell} -c '${pkgs.natscli}/bin/nats sub --count=1 --raw bifrost.requests.github > /tmp/msg.json'")
        body = '{"action":"opened"}'
        sig = "sha256=" + hmac.new(b"${webhookSecret}", body.encode(), hashlib.sha256).hexdigest()
        # Core NATS has no backlog, so post until the subscriber has come up.
        for _ in range(30):
            assert status(f"-H 'X-Hub-Signature-256: {sig}' -H 'X-GitHub-Event: issues' --data '{body}' {url('events', '/hook?id=7')}") == 202
            if server.execute("test -s /tmp/msg.json")[0] == 0:
                break
            server.sleep(1)
        assert server.execute("test -s /tmp/msg.json")[0] == 0, server.execute("systemctl status natsub; journalctl -u natsub")[1]
        msg = json.loads(server.succeed("cat /tmp/msg.json"))
        assert msg["body"] == body and msg["body_encoding"] == "utf-8", msg
        assert msg["path"] == "/hook" and msg["query"] == {"id": ["7"]}, msg
        assert msg["headers"]["X-Github-Event"] == ["issues"], msg
        assert msg["remote_ip"] == "192.168.1.1", msg
        assert status(f"-H 'X-Hub-Signature-256: sha256=00' --data '{body}' {url('events', '/hook')}") == 401

    with subtest("bifrost_nats with jetstream lands in the stream, or 503s without one"):
        assert status(f"-X POST -H 'Authorization: Bearer ${deployToken}' {url('stream', '/yesman')}") == 503
        server.succeed("nats stream add BIFROST --subjects 'bifrost.js.>' --defaults")
        assert status(f"-X POST -H 'Authorization: Bearer ${deployToken}' {url('stream', '/yesman')}") == 202
        info = json.loads(server.succeed("nats stream info BIFROST --json"))
        assert info["state"]["messages"] == 1, info["state"]
        stored = json.loads(server.succeed("nats stream get BIFROST 1 --json"))
        dumped = json.loads(base64.b64decode(stored["data"]))
        assert "Authorization" not in dumped["headers"], dumped

    with subtest("discovery documents"):
        prm = json.loads(client.succeed(f"{CURL} {url('notes', '/.well-known/oauth-protected-resource/mcp')}"))
        assert prm["resource"] == "https://notes.${domain}", prm
        assert prm["authorization_servers"] == ["https://auth.${domain}"], prm
        md = json.loads(client.succeed(f"{CURL} {url('auth', '/.well-known/oauth-authorization-server')}"))
        assert md["code_challenge_methods_supported"] == ["S256"], md
        headers = client.succeed(f"{CURL} -D - -o /dev/null {url('notes', '/mcp')}")
        assert "401" in headers.splitlines()[0], headers
        assert 'resource_metadata="https://notes.${domain}/.well-known/oauth-protected-resource"' in headers, headers

    # The issuer is https://auth.${domain} with no port, so the test rewrites
    # the redirect it gets back onto the forwarded port, as the gateway would.
    def follow(location):
        return location.replace("https://auth.${domain}/", url("auth", "/"))

    def grab(pattern, text):
        m = re.search(pattern, text)
        assert m is not None, f"{pattern} not found in:\n{text}"
        return m.group(1)

    def location(headers):
        return grab(r"(?im)^location: (\S+)", headers)

    def field(name, page):
        return grab(f'name="{name}" value="([^"]+)"', page)

    # Pocket ID's half of the round trip: the fake OP approves instantly and
    # sends the browser back to bifrost's callback.
    def through_login(start_headers, jar):
        hdrs = client.succeed(f"{CURL} -D - -o /dev/null '{location(start_headers)}'")
        return client.succeed(f"{CURL} -c {jar} -b {jar} '{follow(location(hdrs))}'")

    def authorize(client_id, verifier, challenge, jar):
        q = urllib.parse.urlencode({
            "response_type": "code", "client_id": client_id, "redirect_uri": REDIRECT,
            "scope": "notes:read", "state": "state-123456", "code_challenge": challenge,
            "code_challenge_method": "S256", "resource": "https://notes.${domain}/mcp",
        })
        hdrs = client.succeed(f"{CURL} -c {jar} -b {jar} -D - -o /dev/null '{url('auth', '/authorize?' + q)}'")
        page = through_login(hdrs, jar)
        assert "127.0.0.1:9999" in page and "Test Client" in page, page
        hdrs = client.succeed(
            f"{CURL} -c {jar} -b {jar} -D - -o /dev/null -d flow={field('flow', page)} "
            f"-d csrf={field('csrf', page)} -d action=approve {url('auth', '/consent')}"
        )
        final = urllib.parse.urlparse(location(hdrs))
        code = urllib.parse.parse_qs(final.query)["code"][0]
        return json.loads(client.succeed(
            f"{CURL} -d grant_type=authorization_code -d code={code} -d redirect_uri={REDIRECT} "
            f"-d client_id={client_id} -d code_verifier={verifier} -d resource=https://notes.${domain} {url('auth', '/token')}"
        ))

    def pkce():
        verifier = "v" * 64
        challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip("=")
        return verifier, challenge

    reg = json.loads(client.succeed(
        f"{CURL} -H 'Content-Type: application/json' "
        f"-d '{{\"redirect_uris\":[\"{REDIRECT}\"],\"client_name\":\"Test Client\",\"token_endpoint_auth_method\":\"none\"}}' "
        f"{url('auth', '/register')}"
    ))
    client_id = reg["client_id"]
    verifier, challenge = pkce()

    with subtest("a full authorization reaches the upstream with a signed identity"):
        tk = authorize(client_id, verifier, challenge, "/tmp/jar")
        out = json.loads(client.succeed(
            f"{CURL} -H 'Authorization: Bearer {tk['access_token']}' -H 'X-Bifrost-User: forged' {url('notes', '/tools')}"
        ))
        h = {k.lower(): v for k, v in out["headers"].items()}
        assert out["path"] == "/mcp/tools", out
        assert "authorization" not in h, h
        assert h.get("x-forwarded-user") == "gio", h
        assert "x-bifrost-user" not in h, h
        server.succeed(f"curl -sk {url('auth', '/.well-known/jwks.json')} > /tmp/jwks.json")
        claims = json.loads(server.succeed(f"python3 ${verify} {h['x-bifrost-assertion']} /tmp/jwks.json https://notes.${domain}"))
        assert claims["sub"] == "user-1" and claims["client_name"] == "Test Client", claims

    with subtest("tokens survive a restart"):
        server.succeed("systemctl restart bifrost.service")
        server.wait_for_open_port(${toString port})
        client.wait_until_succeeds(f"{CURL} -f -H 'Authorization: Bearer {tk['access_token']}' {url('notes', '/tools')}", timeout=30)

    with subtest("the admin page revokes the grant on the next request"):
        hdrs = client.succeed(f"{CURL} -c /tmp/admin -b /tmp/admin -D - -o /dev/null {url('auth', '/admin')}")
        through_login(hdrs, "/tmp/admin")
        page = client.succeed(f"{CURL} -b /tmp/admin {url('auth', '/admin')}")
        assert "Test Client" in page and "notes.${domain}" in page, page
        client.succeed(
            f"{CURL} -b /tmp/admin -o /dev/null -d csrf={field('csrf', page)} "
            f"-d grant={field('grant', page)} {url('auth', '/admin/revoke')}"
        )
        assert status(f"-H 'Authorization: Bearer {tk['access_token']}' {url('notes', '/tools')}") == 401

    with subtest("rate limiting answers 429 past the zone limit"):
        codes = [status(url("notes", "/tools")) for _ in range(25)]
        assert 429 in codes, codes

    with subtest("failures are logged in the shape fail2ban matches"):
        logs = server.succeed("journalctl -u bifrost.service --no-pager")
        assert '"msg":"bifrost check failed","remote_ip":"' in logs, logs[-2000:]
  '';
}
