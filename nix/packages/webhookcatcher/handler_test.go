package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func sign(secret string, body []byte) string {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write(body)
	return "sha256=" + hex.EncodeToString(mac.Sum(nil))
}

// GitHub publishes this exact (secret, body, signature) triple in its webhook
// docs; matching it proves we implement the same scheme.
func TestVerifyHMAC_GitHubVector(t *testing.T) {
	secret := "It's a Secret to Everybody"
	body := []byte("Hello, World!")
	const sig = "sha256=757107ea0eb2509fc211221cce984b8a37570b6d7586c22c46f4379c8b043e17"
	if !verifyHMAC(secret, sig, body) {
		t.Fatal("GitHub's documented signature should verify")
	}
}

func TestVerifyHMAC(t *testing.T) {
	secret := "topsecret"
	body := []byte(`{"hello":"world"}`)
	good := sign(secret, body)

	tests := []struct {
		name   string
		secret string
		header string
		body   []byte
		want   bool
	}{
		{"valid", secret, good, body, true},
		{"tampered body", secret, good, []byte(`{"hello":"mars"}`), false},
		{"wrong secret", "nope", good, body, false},
		{"missing prefix", secret, strings.TrimPrefix(good, "sha256="), body, false},
		{"bad hex", secret, "sha256=nothex", body, false},
		{"empty header", secret, "", body, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := verifyHMAC(tt.secret, tt.header, tt.body); got != tt.want {
				t.Errorf("verifyHMAC = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestVerify_HeaderSecret(t *testing.T) {
	v := ResolvedVerifier{
		Config: VerifyConfig{Type: VerifyHeaderSecret, Header: "X-Token"},
		Secret: "shh",
	}
	mk := func(val string) *http.Request {
		r := httptest.NewRequest(http.MethodPost, "/x", nil)
		if val != "" {
			r.Header.Set("X-Token", val)
		}
		return r
	}
	if !verify(v, mk("shh"), nil) {
		t.Error("matching token should pass")
	}
	if verify(v, mk("wrong"), nil) {
		t.Error("wrong token should fail")
	}
	if verify(v, mk(""), nil) {
		t.Error("missing token should fail")
	}
}

func TestVerify_Bearer(t *testing.T) {
	v := ResolvedVerifier{
		Config: VerifyConfig{Type: VerifyBearer, Header: "Authorization"},
		Secret: "tok123",
	}
	mk := func(val string) *http.Request {
		r := httptest.NewRequest(http.MethodPost, "/x", nil)
		if val != "" {
			r.Header.Set("Authorization", val)
		}
		return r
	}
	if !verify(v, mk("Bearer tok123"), nil) {
		t.Error("matching bearer token should pass")
	}
	if verify(v, mk("Bearer wrong"), nil) {
		t.Error("wrong bearer token should fail")
	}
	if verify(v, mk("tok123"), nil) {
		t.Error("missing Bearer prefix should fail")
	}
	if verify(v, mk(""), nil) {
		t.Error("missing header should fail")
	}
}

func TestServeHTTP(t *testing.T) {
	secret := "webhook-secret"
	var forwarded []byte
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		forwarded, _ = io.ReadAll(r.Body)
		w.WriteHeader(http.StatusAccepted)
		io.WriteString(w, "ok")
	}))
	defer upstream.Close()

	hooks := map[string]*ResolvedHook{
		"abc": {
			Config: HookConfig{
				ID:      "abc",
				Actions: ActionsConfig{Forward: &ForwardAction{URL: upstream.URL}},
			},
			Verifiers: []ResolvedVerifier{
				{Config: VerifyConfig{Type: VerifyHMAC, Header: "X-Hub-Signature-256"}, Secret: secret},
			},
		},
	}
	h := NewWebhookHandler(hooks)
	body := []byte(`{"event":"push"}`)

	t.Run("valid signature forwards", func(t *testing.T) {
		forwarded = nil
		req := httptest.NewRequest(http.MethodPost, "/abc", strings.NewReader(string(body)))
		req.Header.Set("X-Hub-Signature-256", sign(secret, body))
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		if rec.Code != http.StatusAccepted {
			t.Fatalf("status = %d, want %d", rec.Code, http.StatusAccepted)
		}
		if string(forwarded) != string(body) {
			t.Errorf("forwarded body = %q, want %q", forwarded, body)
		}
	})

	t.Run("invalid signature rejected", func(t *testing.T) {
		forwarded = nil
		req := httptest.NewRequest(http.MethodPost, "/abc", strings.NewReader(string(body)))
		req.Header.Set("X-Hub-Signature-256", sign("wrong-secret", body))
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("status = %d, want %d", rec.Code, http.StatusUnauthorized)
		}
		if forwarded != nil {
			t.Error("body should not have been forwarded on failed verification")
		}
	})

	t.Run("unknown hook id returns 404", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodPost, "/nope", nil)
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		if rec.Code != http.StatusNotFound {
			t.Fatalf("status = %d, want %d", rec.Code, http.StatusNotFound)
		}
	})
}

// Two verifiers on one hook: both must pass (AND).
func TestServeHTTP_MultipleVerifiers(t *testing.T) {
	secret := "s"
	hooks := map[string]*ResolvedHook{
		"h": {
			Config: HookConfig{ID: "h", Actions: ActionsConfig{Print: &PrintAction{}}},
			Verifiers: []ResolvedVerifier{
				{Config: VerifyConfig{Type: VerifyHMAC, Header: "X-Hub-Signature-256"}, Secret: secret},
				{Config: VerifyConfig{Type: VerifyHeaderSecret, Header: "X-Token"}, Secret: "tok"},
			},
		},
	}
	h := NewWebhookHandler(hooks)
	body := []byte("payload")

	// HMAC ok but token missing -> rejected.
	req := httptest.NewRequest(http.MethodPost, "/h", strings.NewReader(string(body)))
	req.Header.Set("X-Hub-Signature-256", sign(secret, body))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("second verifier should have failed: status = %d", rec.Code)
	}

	// Both present -> accepted.
	req = httptest.NewRequest(http.MethodPost, "/h", strings.NewReader(string(body)))
	req.Header.Set("X-Hub-Signature-256", sign(secret, body))
	req.Header.Set("X-Token", "tok")
	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("both verifiers should pass: status = %d", rec.Code)
	}
}
