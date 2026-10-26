package bifrost

import (
	"crypto/sha256"
	"crypto/subtle"
	"fmt"
	"net/http"
	"strings"

	"github.com/caddyserver/caddy/v2"
	"github.com/caddyserver/caddy/v2/caddyconfig/caddyfile"
)

func init() {
	caddy.RegisterModule(BearerChecker{})
}

// BearerChecker compares a static token. With the default Authorization
// header it expects the "Bearer " scheme; any other header holds the bare token.
type BearerChecker struct {
	Header    string `json:"header,omitempty"`
	TokenFile string `json:"token_file,omitempty"`

	digest [sha256.Size]byte
}

func (BearerChecker) CaddyModule() caddy.ModuleInfo {
	return caddy.ModuleInfo{
		ID:  "bifrost.checkers.bearer",
		New: func() caddy.Module { return new(BearerChecker) },
	}
}

func (c *BearerChecker) Provision(caddy.Context) error {
	return c.setup()
}

func (c *BearerChecker) setup() error {
	if c.Header == "" {
		c.Header = "Authorization"
	}
	token, err := readSecretFile(c.TokenFile)
	if err != nil {
		return fmt.Errorf("bearer: %w", err)
	}
	c.digest = sha256.Sum256(token)
	return nil
}

func (c *BearerChecker) Check(r *http.Request) (*Identity, *Failure) {
	given := r.Header.Get(c.Header)
	if strings.EqualFold(c.Header, "Authorization") {
		scheme, token, ok := strings.Cut(given, " ")
		if !ok || !strings.EqualFold(scheme, "Bearer") {
			return nil, &Failure{Status: http.StatusUnauthorized, Reason: "missing bearer token"}
		}
		given = token
	}
	if given == "" {
		return nil, &Failure{Status: http.StatusUnauthorized, Reason: "missing token"}
	}
	// Hashing first makes the comparison constant-time regardless of length.
	digest := sha256.Sum256([]byte(strings.TrimSpace(given)))
	if subtle.ConstantTimeCompare(digest[:], c.digest[:]) != 1 {
		return nil, &Failure{Status: http.StatusUnauthorized, Reason: "token mismatch"}
	}
	return nil, nil
}

// UnmarshalCaddyfile parses the block after `bifrost_guard bearer`.
func (c *BearerChecker) UnmarshalCaddyfile(d *caddyfile.Dispenser) error {
	d.Next()
	for d.NextBlock(0) {
		var dst *string
		switch d.Val() {
		case "header":
			dst = &c.Header
		case "token_file":
			dst = &c.TokenFile
		default:
			return d.Errf("bearer: unknown option %q", d.Val())
		}
		if !d.AllArgs(dst) {
			return d.ArgErr()
		}
	}
	return nil
}

var (
	_ caddy.Provisioner     = (*BearerChecker)(nil)
	_ Checker               = (*BearerChecker)(nil)
	_ caddyfile.Unmarshaler = (*BearerChecker)(nil)
)
