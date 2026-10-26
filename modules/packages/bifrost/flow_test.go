package bifrost

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"regexp"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/caddyserver/certmagic"
	jose "github.com/go-jose/go-jose/v4"
	"github.com/go-jose/go-jose/v4/jwt"
	"go.uber.org/zap"
)

// fakeOP stands in for Pocket ID: discovery, JWKS, and a token endpoint that
// hands out ID tokens for codes the test mints directly.
type fakeOP struct {
	*httptest.Server
	key    *rsa.PrivateKey
	signer jose.Signer

	mu    sync.Mutex
	codes map[string]opCode
}

type opCode struct {
	nonce    string
	authTime time.Time
}

func newFakeOP(t *testing.T) *fakeOP {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	signer, err := jose.NewSigner(jose.SigningKey{Algorithm: jose.RS256, Key: jose.JSONWebKey{Key: key, KeyID: "op"}}, nil)
	if err != nil {
		t.Fatal(err)
	}
	op := &fakeOP{key: key, signer: signer, codes: map[string]opCode{}}
	mux := http.NewServeMux()
	mux.HandleFunc("/.well-known/openid-configuration", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, 200, map[string]any{
			"issuer":                                op.URL,
			"authorization_endpoint":                op.URL + "/authorize",
			"token_endpoint":                        op.URL + "/token",
			"jwks_uri":                              op.URL + "/jwks",
			"id_token_signing_alg_values_supported": []string{"RS256"},
		})
	})
	mux.HandleFunc("/jwks", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, 200, jose.JSONWebKeySet{Keys: []jose.JSONWebKey{{Key: &key.PublicKey, KeyID: "op", Algorithm: "RS256", Use: "sig"}}})
	})
	mux.HandleFunc("/token", func(w http.ResponseWriter, r *http.Request) {
		_ = r.ParseForm()
		op.mu.Lock()
		c, ok := op.codes[r.PostForm.Get("code")]
		op.mu.Unlock()
		if !ok {
			writeJSON(w, 400, map[string]string{"error": "invalid_grant"})
			return
		}
		now := time.Now()
		raw, err := jwt.Signed(op.signer).Claims(map[string]any{
			"iss":                op.URL,
			"aud":                "bifrost",
			"sub":                "user-1",
			"iat":                now.Unix(),
			"exp":                now.Add(time.Hour).Unix(),
			"nonce":              c.nonce,
			"auth_time":          c.authTime.Unix(),
			"email":              "gio@example.test",
			"name":               "Gio",
			"preferred_username": "gio",
			"groups":             []string{"bifrost"},
		}).Serialize()
		if err != nil {
			writeJSON(w, 500, map[string]string{"error": err.Error()})
			return
		}
		writeJSON(w, 200, map[string]any{"access_token": "op-token", "token_type": "Bearer", "expires_in": 3600, "id_token": raw})
	})
	op.Server = httptest.NewServer(mux)
	t.Cleanup(op.Close)
	return op
}

func (op *fakeOP) mint(nonce string, authTime time.Time) string {
	code := randomHex(8)
	op.mu.Lock()
	op.codes[code] = opCode{nonce: nonce, authTime: authTime}
	op.mu.Unlock()
	return code
}

type harness struct {
	t       *testing.T
	op      *fakeOP
	storage certmagic.Storage
	keyFile string
	secret  string
	app     *App
	server  *AuthServer
	notes   *OAuthChecker
	other   *OAuthChecker
}

func newHarness(t *testing.T, storage certmagic.Storage, op *fakeOP, keyFile, secret string) *harness {
	t.Helper()
	h := &harness{t: t, op: op, storage: storage, keyFile: keyFile, secret: secret}
	h.app = &App{
		Issuer: "https://auth.test",
		Login: LoginConfig{
			OIDCIssuer:       op.URL,
			ClientID:         "bifrost",
			ClientSecretFile: secret,
			AllowedGroups:    []string{"bifrost"},
		},
		TokenKeyFile: keyFile,
	}
	if err := h.app.setup(context.Background(), storage, zap.NewNop()); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = h.app.Cleanup() })
	h.notes = &OAuthChecker{Host: "notes.test", Scopes: []string{"notes:read", "notes:write"}, Require: []string{"notes:read"}}
	h.other = &OAuthChecker{Host: "other.test", Scopes: []string{"other"}}
	for _, c := range []*OAuthChecker{h.notes, h.other} {
		if err := c.setup(h.app); err != nil {
			t.Fatal(err)
		}
	}
	h.server = &AuthServer{AdminNetworks: []string{"10.0.0.0/8"}, app: h.app, logger: zap.NewNop()}
	if err := h.server.setup(); err != nil {
		t.Fatal(err)
	}
	return h
}

func (h *harness) do(r *http.Request) *httptest.ResponseRecorder {
	if r.RemoteAddr == "" || strings.HasPrefix(r.RemoteAddr, "192.0.2.") {
		r.RemoteAddr = "203.0.113.7:4242"
	}
	rr := httptest.NewRecorder()
	if err := h.server.ServeHTTP(rr, r, nil); err != nil {
		h.t.Fatal(err)
	}
	return rr
}

func cookieNamed(rr *httptest.ResponseRecorder, name string) *http.Cookie {
	for _, c := range rr.Result().Cookies() {
		if c.Name == name {
			return c
		}
	}
	return nil
}

var csrfField = regexp.MustCompile(`name="csrf" value="([^"]+)"`)

type tokens struct {
	Access  string `json:"access_token"`
	Refresh string `json:"refresh_token"`
	Error   string `json:"error"`
}

const redirectURI = "http://127.0.0.1:9999/cb"

func pkcePair() (verifier, challenge string) {
	verifier = randomHex(32)
	sum := sha256.Sum256([]byte(verifier))
	return verifier, base64.RawURLEncoding.EncodeToString(sum[:])
}

func (h *harness) register() string {
	body := `{"redirect_uris":["` + redirectURI + `"],"client_name":"Test Client","token_endpoint_auth_method":"none"}`
	r := httptest.NewRequest(http.MethodPost, "/register", strings.NewReader(body))
	r.Header.Set("Content-Type", "application/json")
	rr := h.do(r)
	if rr.Code != http.StatusCreated {
		h.t.Fatalf("register: %d %s", rr.Code, rr.Body)
	}
	var resp map[string]any
	_ = json.Unmarshal(rr.Body.Bytes(), &resp)
	return resp["client_id"].(string)
}

// authorize runs /authorize through Pocket ID and consent, returning the code.
func (h *harness) authorize(t *testing.T, clientID, challenge, resource string, authTime time.Time) (code string, final *url.URL) {
	t.Helper()
	q := url.Values{
		"response_type":         {"code"},
		"client_id":             {clientID},
		"redirect_uri":          {redirectURI},
		"scope":                 {"notes:read"},
		"state":                 {"state-123456"},
		"code_challenge":        {challenge},
		"code_challenge_method": {"S256"},
		"resource":              {resource},
	}
	rr := h.do(httptest.NewRequest(http.MethodGet, "/authorize?"+q.Encode(), nil))
	if rr.Code != http.StatusFound && rr.Code != http.StatusSeeOther {
		t.Fatalf("authorize: %d %s", rr.Code, rr.Body)
	}
	loc, _ := url.Parse(rr.Header().Get("Location"))
	if !strings.HasPrefix(loc.String(), h.op.URL+"/authorize") {
		return "", loc
	}
	if loc.Query().Get("prompt") != "login" {
		t.Fatalf("login redirect lacks prompt=login: %s", loc)
	}
	flowC := cookieNamed(rr, flowCookie)

	opCode := h.op.mint(loc.Query().Get("nonce"), authTime)
	cb := httptest.NewRequest(http.MethodGet, "/callback?"+url.Values{"state": {loc.Query().Get("state")}, "code": {opCode}}.Encode(), nil)
	cb.AddCookie(flowC)
	rr = h.do(cb)
	if rr.Code == http.StatusSeeOther || rr.Code == http.StatusFound {
		final, _ = url.Parse(rr.Header().Get("Location"))
		return "", final
	}
	if rr.Code != http.StatusOK || !strings.Contains(rr.Body.String(), "127.0.0.1:9999") {
		t.Fatalf("consent page: %d %s", rr.Code, rr.Body)
	}
	if !strings.Contains(rr.Body.String(), "loopback") {
		t.Fatalf("consent page lacks the loopback warning")
	}
	csrf := csrfField.FindStringSubmatch(rr.Body.String())[1]

	form := url.Values{"flow": {loc.Query().Get("state")}, "csrf": {csrf}, "action": {"approve"}}
	consent := httptest.NewRequest(http.MethodPost, "/consent", strings.NewReader(form.Encode()))
	consent.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	consent.AddCookie(flowC)
	rr = h.do(consent)
	if rr.Code != http.StatusSeeOther && rr.Code != http.StatusFound {
		t.Fatalf("consent: %d %s", rr.Code, rr.Body)
	}
	final, _ = url.Parse(rr.Header().Get("Location"))
	if final.Query().Get("state") != "state-123456" {
		t.Fatalf("state not echoed: %s", final)
	}
	return final.Query().Get("code"), final
}

func (h *harness) token(form url.Values) (tokens, int) {
	r := httptest.NewRequest(http.MethodPost, "/token", strings.NewReader(form.Encode()))
	r.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	rr := h.do(r)
	var tk tokens
	_ = json.Unmarshal(rr.Body.Bytes(), &tk)
	return tk, rr.Code
}

func (h *harness) call(c *OAuthChecker, access string) (*Identity, *Failure, *http.Request) {
	r := httptest.NewRequest(http.MethodPost, "https://"+c.Host+"/mcp", nil)
	r.Header.Set("Authorization", "Bearer "+access)
	id, f := c.Check(r)
	return id, f, r
}

func newTestEnv(t *testing.T) (certmagic.Storage, *fakeOP, string, string) {
	t.Helper()
	return &certmagic.FileStorage{Path: t.TempDir()}, newFakeOP(t),
		writeSecret(t, strings.Repeat("k", 48)), writeSecret(t, "op-client-secret")
}

func TestAllScopesEncodesAsArrayWhenEmpty(t *testing.T) {
	rr := newResourceRegistry()
	if err := rr.register("https://time.test", nil); err != nil {
		t.Fatal(err)
	}
	b, err := json.Marshal(rr.allScopes())
	if err != nil {
		t.Fatal(err)
	}
	if string(b) != "[]" {
		t.Fatalf("allScopes encodes as %s, want []", b)
	}
}

func TestOAuthFlow(t *testing.T) {
	storage, op, keyFile, secret := newTestEnv(t)
	h := newHarness(t, storage, op, keyFile, secret)

	t.Run("metadata", func(t *testing.T) {
		rr := h.do(httptest.NewRequest(http.MethodGet, "/.well-known/oauth-authorization-server", nil))
		var md map[string]any
		_ = json.Unmarshal(rr.Body.Bytes(), &md)
		if md["issuer"] != "https://auth.test" || md["client_id_metadata_document_supported"] != true {
			t.Fatalf("metadata: %s", rr.Body)
		}
		if got := md["code_challenge_methods_supported"].([]any); len(got) != 1 || got[0] != "S256" {
			t.Fatalf("PKCE methods: %v", got)
		}
	})

	t.Run("protected resource metadata answers at the root and path variants", func(t *testing.T) {
		for _, p := range []string{"/.well-known/oauth-protected-resource", "/.well-known/oauth-protected-resource/mcp"} {
			rr := httptest.NewRecorder()
			if !h.notes.Intercept(rr, httptest.NewRequest(http.MethodGet, "https://notes.test"+p, nil)) {
				t.Fatalf("%s not intercepted", p)
			}
			var md map[string]any
			_ = json.Unmarshal(rr.Body.Bytes(), &md)
			if md["resource"] != "https://notes.test" {
				t.Fatalf("%s: %s", p, rr.Body)
			}
		}
	})

	t.Run("an unauthenticated call gets a quiet challenge", func(t *testing.T) {
		r := httptest.NewRequest(http.MethodPost, "https://notes.test/mcp", nil)
		_, f := h.notes.Check(r)
		if f == nil || f.Status != 401 || !f.Quiet {
			t.Fatalf("expected quiet 401, got %+v", f)
		}
		if !strings.Contains(f.Header.Get("WWW-Authenticate"), `resource_metadata="https://notes.test/.well-known/oauth-protected-resource"`) {
			t.Fatalf("challenge: %s", f.Header.Get("WWW-Authenticate"))
		}
	})

	clientID := h.register()
	verifier, challenge := pkcePair()

	t.Run("an unknown resource is refused", func(t *testing.T) {
		_, final := h.authorize(t, clientID, challenge, "https://nope.test", time.Now())
		if final.Query().Get("error") != "invalid_target" {
			t.Fatalf("expected invalid_target, got %s", final)
		}
	})

	t.Run("a stale login is refused", func(t *testing.T) {
		_, final := h.authorize(t, clientID, challenge, "https://notes.test/mcp", time.Now().Add(-time.Hour))
		if final.Query().Get("error") != "access_denied" {
			t.Fatalf("expected access_denied, got %s", final)
		}
	})

	code, _ := h.authorize(t, clientID, challenge, "https://notes.test/mcp", time.Now())
	tk, status := h.token(url.Values{
		"grant_type":    {"authorization_code"},
		"code":          {code},
		"redirect_uri":  {redirectURI},
		"client_id":     {clientID},
		"code_verifier": {verifier},
		"resource":      {"https://notes.test/mcp"},
	})
	if status != 200 || tk.Access == "" || tk.Refresh == "" {
		t.Fatalf("token exchange: %d %+v", status, tk)
	}

	t.Run("the token passes its own resource with a verifiable assertion", func(t *testing.T) {
		id, f, r := h.call(h.notes, tk.Access)
		if f != nil {
			t.Fatalf("check failed: %+v", f)
		}
		if r.Header.Get("Authorization") != "" {
			t.Fatal("Authorization was passed through")
		}
		if id.Username != "gio" || id.Email != "gio@example.test" || id.ClientName != "Test Client" {
			t.Fatalf("identity: %+v", id)
		}
		claims, err := h.app.shared.keys.verify(id.Assertion, time.Now())
		if err != nil {
			t.Fatal(err)
		}
		if claims["aud"] != "https://notes.test" || claims["sub"] != "user-1" || claims["grant_id"] != id.GrantID {
			t.Fatalf("claims: %v", claims)
		}
	})

	t.Run("the token is refused by another resource", func(t *testing.T) {
		if _, f, _ := h.call(h.other, tk.Access); f == nil || f.Status != 401 || f.Quiet {
			t.Fatalf("expected a counted 401, got %+v", f)
		}
	})

	t.Run("JWKS publishes the current and next key", func(t *testing.T) {
		rr := h.do(httptest.NewRequest(http.MethodGet, "/.well-known/jwks.json", nil))
		var set struct{ Keys []jwk }
		_ = json.Unmarshal(rr.Body.Bytes(), &set)
		if len(set.Keys) != 2 || set.Keys[0].Kty != "OKP" {
			t.Fatalf("jwks: %s", rr.Body)
		}
	})

	refreshed, status := h.token(url.Values{
		"grant_type": {"refresh_token"}, "refresh_token": {tk.Refresh},
		"client_id": {clientID}, "resource": {"https://notes.test"},
	})
	if status != 200 || refreshed.Access == "" || refreshed.Refresh == tk.Refresh {
		t.Fatalf("refresh: %d %+v", status, refreshed)
	}

	t.Run("refresh rotates both tokens", func(t *testing.T) {
		if _, f, _ := h.call(h.notes, tk.Access); f == nil {
			t.Fatal("old access token still works")
		}
		if _, f, _ := h.call(h.notes, refreshed.Access); f != nil {
			t.Fatalf("new access token failed: %+v", f)
		}
	})

	t.Run("reusing a rotated refresh token revokes the grant", func(t *testing.T) {
		if _, status := h.token(url.Values{
			"grant_type": {"refresh_token"}, "refresh_token": {tk.Refresh}, "client_id": {clientID},
		}); status == 200 {
			t.Fatal("reused refresh token was accepted")
		}
		if _, f, _ := h.call(h.notes, refreshed.Access); f == nil {
			t.Fatal("access token survived refresh token reuse")
		}
		if _, status := h.token(url.Values{
			"grant_type": {"refresh_token"}, "refresh_token": {refreshed.Refresh}, "client_id": {clientID},
		}); status == 200 {
			t.Fatal("refresh token survived reuse detection")
		}
	})

	t.Run("redeeming a code twice revokes its tokens", func(t *testing.T) {
		v2, c2 := pkcePair()
		code2, _ := h.authorize(t, clientID, c2, "https://notes.test", time.Now())
		redeem := url.Values{
			"grant_type": {"authorization_code"}, "code": {code2}, "redirect_uri": {redirectURI},
			"client_id": {clientID}, "code_verifier": {v2},
		}
		first, status := h.token(redeem)
		if status != 200 {
			t.Fatalf("first redemption: %d", status)
		}
		if _, status := h.token(redeem); status == 200 {
			t.Fatal("second redemption succeeded")
		}
		if _, f, _ := h.call(h.notes, first.Access); f == nil {
			t.Fatal("tokens from a replayed code still work")
		}
	})
}

func TestAdminAndPersistence(t *testing.T) {
	storage, op, keyFile, secret := newTestEnv(t)
	h := newHarness(t, storage, op, keyFile, secret)
	clientID := h.register()
	verifier, challenge := pkcePair()
	code, _ := h.authorize(t, clientID, challenge, "https://notes.test", time.Now())
	tk, status := h.token(url.Values{
		"grant_type": {"authorization_code"}, "code": {code}, "redirect_uri": {redirectURI},
		"client_id": {clientID}, "code_verifier": {verifier}, "resource": {"https://notes.test"},
	})
	if status != 200 {
		t.Fatalf("token: %d", status)
	}
	jwksBefore := h.do(httptest.NewRequest(http.MethodGet, "/.well-known/jwks.json", nil)).Body.String()

	t.Run("state survives a restart", func(t *testing.T) {
		if err := h.app.Cleanup(); err != nil {
			t.Fatal(err)
		}
		h = newHarness(t, storage, op, keyFile, secret)
		if _, f, _ := h.call(h.notes, tk.Access); f != nil {
			t.Fatalf("token lost across restart: %+v", f)
		}
		if got := h.do(httptest.NewRequest(http.MethodGet, "/.well-known/jwks.json", nil)).Body.String(); got != jwksBefore {
			t.Fatalf("signing keys changed across restart:\n%s\n%s", jwksBefore, got)
		}
	})

	t.Run("admin refuses addresses outside admin networks", func(t *testing.T) {
		r := httptest.NewRequest(http.MethodGet, "/admin", nil)
		r.RemoteAddr = "192.0.2.1:1234"
		if rr := h.do(r); rr.Code != http.StatusNotFound {
			t.Fatalf("expected 404, got %d", rr.Code)
		}
	})

	var adminC *http.Cookie
	t.Run("admin requires a Pocket ID login", func(t *testing.T) {
		r := httptest.NewRequest(http.MethodGet, "/admin", nil)
		r.RemoteAddr = "10.30.0.5:1234"
		rr := h.do(r)
		loc, _ := url.Parse(rr.Header().Get("Location"))
		if rr.Code != http.StatusFound || !strings.HasPrefix(loc.String(), op.URL) {
			t.Fatalf("expected a login redirect, got %d %s", rr.Code, loc)
		}
		cb := httptest.NewRequest(http.MethodGet, "/callback?"+url.Values{
			"state": {loc.Query().Get("state")}, "code": {op.mint(loc.Query().Get("nonce"), time.Now())},
		}.Encode(), nil)
		cb.RemoteAddr = "10.30.0.5:1234"
		cb.AddCookie(cookieNamed(rr, flowCookie))
		rr = h.do(cb)
		adminC = cookieNamed(rr, adminCookie)
		if rr.Code != http.StatusSeeOther || adminC == nil {
			t.Fatalf("admin login: %d %s", rr.Code, rr.Body)
		}
	})

	t.Run("admin revokes a grant immediately", func(t *testing.T) {
		r := httptest.NewRequest(http.MethodGet, "/admin", nil)
		r.RemoteAddr = "10.30.0.5:1234"
		r.AddCookie(adminC)
		rr := h.do(r)
		if rr.Code != 200 || !strings.Contains(rr.Body.String(), "Test Client") || !strings.Contains(rr.Body.String(), "127.0.0.1:9999") {
			t.Fatalf("admin page: %d %s", rr.Code, rr.Body)
		}
		csrf := csrfField.FindStringSubmatch(rr.Body.String())[1]
		grants := h.app.shared.store.listGrants()
		if len(grants) != 1 || grants[0].Requests == 0 {
			t.Fatalf("grants: %+v", grants)
		}

		bad := httptest.NewRequest(http.MethodPost, "/admin/revoke", strings.NewReader(url.Values{"csrf": {"nope"}, "grant": {grants[0].ID}}.Encode()))
		bad.Header.Set("Content-Type", "application/x-www-form-urlencoded")
		bad.RemoteAddr = "10.30.0.5:1234"
		bad.AddCookie(adminC)
		if rr := h.do(bad); rr.Code != http.StatusForbidden {
			t.Fatalf("bad CSRF accepted: %d", rr.Code)
		}

		post := httptest.NewRequest(http.MethodPost, "/admin/revoke", strings.NewReader(url.Values{"csrf": {csrf}, "grant": {grants[0].ID}}.Encode()))
		post.Header.Set("Content-Type", "application/x-www-form-urlencoded")
		post.RemoteAddr = "10.30.0.5:1234"
		post.AddCookie(adminC)
		if rr := h.do(post); rr.Code != http.StatusSeeOther {
			t.Fatalf("revoke: %d %s", rr.Code, rr.Body)
		}
		if _, f, _ := h.call(h.notes, tk.Access); f == nil {
			t.Fatal("revoked token still works")
		}
		if _, status := h.token(url.Values{"grant_type": {"refresh_token"}, "refresh_token": {tk.Refresh}, "client_id": {clientID}}); status == 200 {
			t.Fatal("revoked refresh token still works")
		}
	})
}

func TestLocalhostRedirectAnyPort(t *testing.T) {
	storage, op, keyFile, secret := newTestEnv(t)
	h := newHarness(t, storage, op, keyFile, secret)

	r := httptest.NewRequest(http.MethodPost, "/register", strings.NewReader(`{"redirect_uris":["http://localhost/callback"],"client_name":"Port Client","token_endpoint_auth_method":"none"}`))
	r.Header.Set("Content-Type", "application/json")
	rr := h.do(r)
	if rr.Code != http.StatusCreated {
		t.Fatalf("register: %d %s", rr.Code, rr.Body)
	}
	var reg map[string]any
	_ = json.Unmarshal(rr.Body.Bytes(), &reg)
	clientID := reg["client_id"].(string)

	_, challenge := pkcePair()
	authorize := func(redirect string) *httptest.ResponseRecorder {
		q := url.Values{
			"response_type": {"code"}, "client_id": {clientID}, "redirect_uri": {redirect},
			"state": {"state-123456"}, "code_challenge": {challenge}, "code_challenge_method": {"S256"},
			"resource": {"https://notes.test"},
		}
		return h.do(httptest.NewRequest(http.MethodGet, "/authorize?"+q.Encode(), nil))
	}

	rr = authorize("http://localhost:62222/callback")
	if loc := rr.Header().Get("Location"); rr.Code != http.StatusFound || !strings.HasPrefix(loc, h.op.URL+"/authorize") {
		t.Fatalf("a localhost redirect on another port was refused: %d %s %s", rr.Code, loc, rr.Body)
	}

	for _, bad := range []string{"http://localhost:62222/elsewhere", "http://127.0.0.2:62222/callback", "https://localhost:62222/callback"} {
		rr = authorize(bad)
		if strings.HasPrefix(rr.Header().Get("Location"), h.op.URL) {
			t.Fatalf("%s was accepted", bad)
		}
	}
}

func TestMetadataDocumentClient(t *testing.T) {
	storage, op, keyFile, secret := newTestEnv(t)
	h := newHarness(t, storage, op, keyFile, secret)

	var docURL string
	docSrv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/client.json" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Cache-Control", "max-age=600")
		writeJSON(w, 200, map[string]any{
			"client_id":                  docURL,
			"client_name":                "Doc Client",
			"redirect_uris":              []string{redirectURI},
			"token_endpoint_auth_method": "none",
		})
	}))
	defer docSrv.Close()
	docURL = docSrv.URL + "/client.json"

	t.Run("the default fetcher refuses loopback addresses", func(t *testing.T) {
		if _, err := h.app.shared.docs.get(context.Background(), docURL); err == nil || !strings.Contains(err.Error(), "non-public") {
			t.Fatalf("expected an SSRF refusal, got %v", err)
		}
	})

	// The test server is on loopback, so swap in a client that trusts it.
	h.app.shared.docs.client = docSrv.Client()

	verifier, challenge := pkcePair()
	code, _ := h.authorize(t, docURL, challenge, "https://notes.test", time.Now())
	tk, status := h.token(url.Values{
		"grant_type": {"authorization_code"}, "code": {code}, "redirect_uri": {redirectURI},
		"client_id": {docURL}, "code_verifier": {verifier}, "resource": {"https://notes.test"},
	})
	if status != 200 {
		t.Fatalf("token: %d %+v", status, tk)
	}
	id, f, _ := h.call(h.notes, tk.Access)
	if f != nil || id.ClientName != "Doc Client" || id.ClientID != docURL {
		t.Fatalf("identity %+v failure %+v", id, f)
	}

	t.Run("a document whose client_id doesn't match its URL is refused", func(t *testing.T) {
		h.app.shared.docs.docs = map[string]cachedDoc{}
		if _, err := h.app.shared.docs.get(context.Background(), docSrv.URL+"/client.json?x"); err == nil {
			t.Fatal("mismatched client_id accepted")
		}
	})
}

func TestKeyRotation(t *testing.T) {
	store := newStore(&certmagic.FileStorage{Path: t.TempDir()})
	kr := newKeyRing(store)
	ctx := context.Background()
	start := time.Now()
	if err := kr.maintain(ctx, start, time.Hour, 2*time.Minute); err != nil {
		t.Fatal(err)
	}
	signedOld, err := kr.sign(map[string]any{"exp": start.Add(2 * time.Minute).Unix()})
	if err != nil {
		t.Fatal(err)
	}
	nextKID := kr.byState(keyNext).KID

	rotated := start.Add(time.Hour)
	if err := kr.maintain(ctx, rotated, time.Hour, 2*time.Minute); err != nil {
		t.Fatal(err)
	}
	if kr.byState(keyCurrent).KID != nextKID {
		t.Fatal("the pre-published next key was not promoted")
	}
	if len(kr.jwks()["keys"]) != 3 {
		t.Fatalf("expected retired, current and next keys published, got %d", len(kr.jwks()["keys"]))
	}
	if _, err := kr.verify(signedOld, start.Add(time.Minute)); err != nil {
		t.Fatalf("an assertion from the retired key stopped verifying: %v", err)
	}

	if err := kr.maintain(ctx, rotated.Add(5*time.Minute), time.Hour, 2*time.Minute); err != nil {
		t.Fatal(err)
	}
	if len(kr.jwks()["keys"]) != 2 {
		t.Fatalf("retired key still published after its assertions expired")
	}
}
