package bifrost

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeSecret(t *testing.T, value string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "secret")
	if err := os.WriteFile(p, []byte(value+"\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	return p
}

func sign(secret, body string) string {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(body))
	return "sha256=" + hex.EncodeToString(mac.Sum(nil))
}

func TestHMACChecker(t *testing.T) {
	c := &HMACChecker{Header: "X-Hub-Signature-256", Prefix: "sha256=", SecretFile: writeSecret(t, "s3cret")}
	if err := c.setup(); err != nil {
		t.Fatal(err)
	}
	body := `{"zen":"Keep it logically awesome."}`

	req := func(sig string) *http.Request {
		r := httptest.NewRequest(http.MethodPost, "/hooks/github", strings.NewReader(body))
		if sig != "" {
			r.Header.Set("X-Hub-Signature-256", sig)
		}
		return r
	}

	t.Run("valid signature passes and leaves the body readable", func(t *testing.T) {
		r := req(sign("s3cret", body))
		if _, f := c.Check(r); f != nil {
			t.Fatalf("unexpected failure: %+v", f)
		}
		got, _ := io.ReadAll(r.Body)
		if string(got) != body {
			t.Fatalf("body not restored: %q", got)
		}
	})

	for name, sig := range map[string]string{
		"missing header": "",
		"wrong secret":   sign("other", body),
		"missing prefix": strings.TrimPrefix(sign("s3cret", body), "sha256="),
		"not hex":        "sha256=zz",
	} {
		t.Run(name, func(t *testing.T) {
			_, f := c.Check(req(sig))
			if f == nil || f.Status != http.StatusUnauthorized || f.Quiet {
				t.Fatalf("expected a counted 401, got %+v", f)
			}
		})
	}

	t.Run("oversized body", func(t *testing.T) {
		small := &HMACChecker{Header: "X-Sig", SecretFile: c.SecretFile, MaxBody: 4}
		if err := small.setup(); err != nil {
			t.Fatal(err)
		}
		r := httptest.NewRequest(http.MethodPost, "/", strings.NewReader("12345"))
		mac := hmac.New(sha256.New, []byte("s3cret"))
		mac.Write([]byte("12345"))
		r.Header.Set("X-Sig", hex.EncodeToString(mac.Sum(nil)))
		if _, f := small.Check(r); f == nil || f.Status != http.StatusRequestEntityTooLarge {
			t.Fatalf("expected 413, got %+v", f)
		}
	})

	t.Run("dedupe rejects a repeated delivery", func(t *testing.T) {
		d := &HMACChecker{Header: "X-Hub-Signature-256", Prefix: "sha256=", SecretFile: c.SecretFile, DedupeHeader: "X-GitHub-Delivery"}
		if err := d.setup(); err != nil {
			t.Fatal(err)
		}
		first := req(sign("s3cret", body))
		first.Header.Set("X-GitHub-Delivery", "abc")
		if _, f := d.Check(first); f != nil {
			t.Fatalf("first delivery failed: %+v", f)
		}
		again := req(sign("s3cret", body))
		again.Header.Set("X-GitHub-Delivery", "abc")
		if _, f := d.Check(again); f == nil || f.Status != http.StatusConflict {
			t.Fatalf("expected 409, got %+v", f)
		}
	})
}

func TestBearerChecker(t *testing.T) {
	c := &BearerChecker{TokenFile: writeSecret(t, "tok3n")}
	if err := c.setup(); err != nil {
		t.Fatal(err)
	}
	for name, tc := range map[string]struct {
		header string
		ok     bool
	}{
		"valid":           {"Bearer tok3n", true},
		"scheme any case": {"bearer tok3n", true},
		"wrong token":     {"Bearer nope", false},
		"prefix of token": {"Bearer tok", false},
		"missing":         {"", false},
		"basic scheme":    {"Basic tok3n", false},
	} {
		t.Run(name, func(t *testing.T) {
			r := httptest.NewRequest(http.MethodPost, "/", nil)
			if tc.header != "" {
				r.Header.Set("Authorization", tc.header)
			}
			_, f := c.Check(r)
			if tc.ok != (f == nil) {
				t.Fatalf("ok=%v, failure=%+v", tc.ok, f)
			}
		})
	}

	t.Run("custom header holds the bare token", func(t *testing.T) {
		h := &BearerChecker{Header: "X-Token", TokenFile: c.TokenFile}
		if err := h.setup(); err != nil {
			t.Fatal(err)
		}
		r := httptest.NewRequest(http.MethodPost, "/", nil)
		r.Header.Set("X-Token", "tok3n")
		if _, f := h.Check(r); f != nil {
			t.Fatalf("unexpected failure: %+v", f)
		}
	})
}

func TestStripBifrostHeaders(t *testing.T) {
	h := http.Header{}
	h.Set("X-Bifrost-User", "forged")
	h.Set("x-bifrost-assertion", "forged")
	h.Set("X-Other", "kept")
	stripBifrostHeaders(h)
	if len(h) != 1 || h.Get("X-Other") != "kept" {
		t.Fatalf("unexpected headers left: %v", h)
	}
}

func TestCanonicalResource(t *testing.T) {
	rr := newResourceRegistry()
	if err := rr.register("https://notes.external.gio.ninja", nil, nil); err != nil {
		t.Fatal(err)
	}
	for in, want := range map[string]string{
		"https://notes.external.gio.ninja":      "https://notes.external.gio.ninja",
		"https://NOTES.external.gio.ninja/":     "https://notes.external.gio.ninja",
		"HTTPS://notes.external.gio.ninja/mcp":  "https://notes.external.gio.ninja",
		"https://notes.external.gio.ninja/a/b/": "https://notes.external.gio.ninja",
	} {
		got, err := rr.resolve(in)
		if err != nil || got != want {
			t.Errorf("resolve(%q) = %q, %v; want %q", in, got, err, want)
		}
	}
	for _, bad := range []string{
		"https://other.external.gio.ninja",
		"https://notes.external.gio.ninja.evil.test",
		"https://notes.external.gio.ninja?x=1",
		"notes.external.gio.ninja",
	} {
		if got, err := rr.resolve(bad); err == nil {
			t.Errorf("resolve(%q) = %q, want an error", bad, got)
		}
	}
}

func TestCacheTTL(t *testing.T) {
	for in, want := range map[string]string{
		"":                    "5m0s",
		"max-age=600":         "10m0s",
		"max-age=1":           "1m0s",
		"max-age=999999":      "24h0m0s",
		"no-store":            "1m0s",
		"public, max-age=120": "2m0s",
	} {
		if got := cacheTTL(in).String(); got != want {
			t.Errorf("cacheTTL(%q) = %s, want %s", in, got, want)
		}
	}
}
