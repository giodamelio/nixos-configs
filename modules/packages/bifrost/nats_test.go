package bifrost

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/caddyserver/caddy/v2"
	"github.com/caddyserver/caddy/v2/modules/caddyhttp"
	natsserver "github.com/nats-io/nats-server/v2/server"
	"github.com/nats-io/nats.go"
	"github.com/nats-io/nats.go/jetstream"
	"go.uber.org/zap"
)

func startNATS(t *testing.T) *natsserver.Server {
	t.Helper()
	srv, err := natsserver.NewServer(&natsserver.Options{
		Host:      "127.0.0.1",
		Port:      -1,
		JetStream: true,
		StoreDir:  t.TempDir(),
		NoLog:     true,
		NoSigs:    true,
	})
	if err != nil {
		t.Fatal(err)
	}
	go srv.Start()
	if !srv.ReadyForConnections(10 * time.Second) {
		t.Fatal("NATS server did not start")
	}
	t.Cleanup(srv.Shutdown)
	return srv
}

// caddyRequest gives a request the context pieces Caddy's server would.
func caddyRequest(method, target, body string, vars map[string]any) *http.Request {
	r := httptest.NewRequest(method, target, strings.NewReader(body))
	if vars == nil {
		vars = map[string]any{}
	}
	ctx := context.WithValue(r.Context(), caddyhttp.VarsCtxKey, vars)
	ctx = context.WithValue(ctx, caddy.ReplacerCtxKey, caddy.NewReplacer())
	return r.WithContext(ctx)
}

func TestNATSPublisher(t *testing.T) {
	srv := startNATS(t)
	conn, err := NATSConfig{URL: srv.ClientURL()}.connect(zap.NewNop())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = conn.Destruct() })

	sub, err := conn.nc.SubscribeSync("bifrost.requests.>")
	if err != nil {
		t.Fatal(err)
	}
	if err := conn.nc.Flush(); err != nil {
		t.Fatal(err)
	}

	pub := &NATSPublisher{Subject: "bifrost.requests.github", conn: conn, logger: zap.NewNop()}
	if err := pub.setup(); err != nil {
		t.Fatal(err)
	}
	serve := func(r *http.Request) *httptest.ResponseRecorder {
		rr := httptest.NewRecorder()
		if err := pub.ServeHTTP(rr, r, nil); err != nil {
			t.Fatal(err)
		}
		return rr
	}
	next := func() RequestMessage {
		m, err := sub.NextMsg(2 * time.Second)
		if err != nil {
			t.Fatal(err)
		}
		var msg RequestMessage
		if err := json.Unmarshal(m.Data, &msg); err != nil {
			t.Fatal(err)
		}
		return msg
	}

	t.Run("a text body is published whole, without secrets", func(t *testing.T) {
		r := caddyRequest(http.MethodPost, "https://hooks.test/push?x=1", `{"ref":"main"}`, nil)
		r.Header.Set("X-GitHub-Event", "push")
		r.Header.Set("Authorization", "Bearer shared-secret")
		r.Header.Set("X-Bifrost-Assertion", "jwt")
		if rr := serve(r); rr.Code != http.StatusAccepted {
			t.Fatalf("status %d: %s", rr.Code, rr.Body)
		}
		msg := next()
		if msg.Version != 1 || msg.Method != "POST" || msg.Host != "hooks.test" || msg.Path != "/push" {
			t.Fatalf("message: %+v", msg)
		}
		if msg.Body != `{"ref":"main"}` || msg.BodyEncoding != "utf-8" || msg.Query["x"][0] != "1" {
			t.Fatalf("body/query: %+v", msg)
		}
		if msg.Headers["X-Github-Event"][0] != "push" {
			t.Fatalf("headers: %v", msg.Headers)
		}
		if _, ok := msg.Headers["Authorization"]; ok {
			t.Fatal("Authorization was published")
		}
		if _, ok := msg.Headers["X-Bifrost-Assertion"]; ok {
			t.Fatal("X-Bifrost-Assertion was published")
		}
		if msg.Identity != nil {
			t.Fatalf("unexpected identity: %+v", msg.Identity)
		}
	})

	t.Run("a binary body is base64", func(t *testing.T) {
		raw := string([]byte{0xff, 0xfe, 0x00, 0x01})
		if rr := serve(caddyRequest(http.MethodPost, "https://hooks.test/", raw, nil)); rr.Code != http.StatusAccepted {
			t.Fatalf("status %d", rr.Code)
		}
		msg := next()
		got, _ := base64.StdEncoding.DecodeString(msg.Body)
		if msg.BodyEncoding != "base64" || string(got) != raw {
			t.Fatalf("binary body: %+v", msg)
		}
	})

	t.Run("an oauth identity is carried", func(t *testing.T) {
		vars := map[string]any{
			"bifrost_sub": "user-1", "bifrost_user": "gio", "bifrost_client_id": "c1",
			"bifrost_grant_id": "g1", "bifrost_scopes": "notes:read notes:write", "bifrost_groups": "bifrost family",
		}
		serve(caddyRequest(http.MethodPost, "https://notes.test/", "", vars))
		msg := next()
		if msg.Identity == nil || msg.Identity.Username != "gio" || len(msg.Identity.Scopes) != 2 || len(msg.Identity.Groups) != 2 {
			t.Fatalf("identity: %+v", msg.Identity)
		}
	})

	t.Run("the subject expands placeholders", func(t *testing.T) {
		p := &NATSPublisher{Subject: "bifrost.requests.{http.request.method}", conn: conn, logger: zap.NewNop()}
		_ = p.setup()
		r := caddyRequest(http.MethodPut, "https://hooks.test/", "x", nil)
		repl := r.Context().Value(caddy.ReplacerCtxKey).(*caddy.Replacer)
		caddyhttp.PrepareRequest(r, repl, httptest.NewRecorder(), nil)
		rr := httptest.NewRecorder()
		_ = p.ServeHTTP(rr, r, nil)
		m, err := sub.NextMsg(2 * time.Second)
		if err != nil || m.Subject != "bifrost.requests.PUT" {
			t.Fatalf("subject %q, err %v", m.Subject, err)
		}
	})

	t.Run("a body over max_body is refused", func(t *testing.T) {
		small := &NATSPublisher{Subject: "bifrost.requests.x", MaxBody: 3, conn: conn, logger: zap.NewNop()}
		rr := httptest.NewRecorder()
		_ = small.ServeHTTP(rr, caddyRequest(http.MethodPost, "https://hooks.test/", "1234", nil), nil)
		if rr.Code != http.StatusRequestEntityTooLarge {
			t.Fatalf("status %d", rr.Code)
		}
	})

	t.Run("JetStream publishes wait for the stream's ack", func(t *testing.T) {
		js := &NATSPublisher{Subject: "bifrost.js.github", JetStream: true, conn: conn, logger: zap.NewNop()}
		_ = js.setup()
		rr := httptest.NewRecorder()
		_ = js.ServeHTTP(rr, caddyRequest(http.MethodPost, "https://hooks.test/", "x", nil), nil)
		if rr.Code != http.StatusServiceUnavailable {
			t.Fatalf("publishing with no stream should be a 503, got %d", rr.Code)
		}

		ctx := context.Background()
		stream, err := conn.js.CreateStream(ctx, jetstream.StreamConfig{Name: "BIFROST", Subjects: []string{"bifrost.js.>"}})
		if err != nil {
			t.Fatal(err)
		}
		rr = httptest.NewRecorder()
		_ = js.ServeHTTP(rr, caddyRequest(http.MethodPost, "https://hooks.test/", "x", nil), nil)
		if rr.Code != http.StatusAccepted {
			t.Fatalf("status %d: %s", rr.Code, rr.Body)
		}
		info, err := stream.Info(ctx)
		if err != nil || info.State.Msgs != 1 {
			t.Fatalf("stream holds %d messages, err %v", info.State.Msgs, err)
		}
	})

	t.Run("NATS being down is a 503, never a silent drop", func(t *testing.T) {
		srv.Shutdown()
		deadline := time.Now().Add(5 * time.Second)
		for conn.nc.Status() == nats.CONNECTED && time.Now().Before(deadline) {
			time.Sleep(50 * time.Millisecond)
		}
		rr := serve(caddyRequest(http.MethodPost, "https://hooks.test/", "x", nil))
		if rr.Code != http.StatusServiceUnavailable {
			t.Fatalf("status %d", rr.Code)
		}
	})
}

func TestNATSAppConfig(t *testing.T) {
	srv := startNATS(t)
	storage, op, keyFile, secret := newTestEnv(t)
	app := &App{
		Issuer:       "https://auth.test",
		Login:        LoginConfig{OIDCIssuer: op.URL, ClientID: "bifrost", ClientSecretFile: secret},
		TokenKeyFile: keyFile,
		NATS:         &NATSConfig{URL: srv.ClientURL()},
	}
	if err := app.setup(context.Background(), storage, zap.NewNop()); err != nil {
		t.Fatal(err)
	}
	if app.natsConn == nil {
		t.Fatal("no NATS connection")
	}
	deadline := time.Now().Add(5 * time.Second)
	for !app.natsConn.nc.IsConnected() && time.Now().Before(deadline) {
		time.Sleep(50 * time.Millisecond)
	}
	if !app.natsConn.nc.IsConnected() {
		t.Fatal("app never connected to NATS")
	}
	if err := app.Cleanup(); err != nil {
		t.Fatal(err)
	}
}
