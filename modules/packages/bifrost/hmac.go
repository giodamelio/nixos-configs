package bifrost

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha1"
	"crypto/sha256"
	"crypto/sha512"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"hash"
	"io"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/caddyserver/caddy/v2"
	"github.com/caddyserver/caddy/v2/caddyconfig/caddyfile"
)

func init() {
	caddy.RegisterModule(HMACChecker{})
}

// GitHub caps webhook payloads at 25 MB.
const defaultMaxBody = 25 << 20

// HMACChecker verifies a signature over the raw request body.
type HMACChecker struct {
	Header     string `json:"header,omitempty"`
	Prefix     string `json:"prefix,omitempty"`
	Algorithm  string `json:"algorithm,omitempty"`
	Encoding   string `json:"encoding,omitempty"`
	SecretFile string `json:"secret_file,omitempty"`
	MaxBody    int64  `json:"max_body,omitempty"`

	// DedupeHeader rejects a repeated delivery ID within DedupeWindow. Off by
	// default: GitHub's manual redeliveries reuse the original delivery ID.
	DedupeHeader string         `json:"dedupe_header,omitempty"`
	DedupeWindow caddy.Duration `json:"dedupe_window,omitempty"`

	secret  []byte
	newHash func() hash.Hash
	decode  func(string) ([]byte, error)
	seen    *seenSet
}

func (HMACChecker) CaddyModule() caddy.ModuleInfo {
	return caddy.ModuleInfo{
		ID:  "bifrost.checkers.hmac",
		New: func() caddy.Module { return new(HMACChecker) },
	}
}

func (c *HMACChecker) Provision(caddy.Context) error {
	return c.setup()
}

func (c *HMACChecker) setup() error {
	if c.Header == "" {
		return fmt.Errorf("hmac: header is required")
	}
	switch strings.ToLower(c.Algorithm) {
	case "", "sha256":
		c.newHash = sha256.New
	case "sha1":
		c.newHash = sha1.New
	case "sha512":
		c.newHash = sha512.New
	default:
		return fmt.Errorf("hmac: unsupported algorithm %q", c.Algorithm)
	}
	switch strings.ToLower(c.Encoding) {
	case "", "hex":
		c.decode = hex.DecodeString
	case "base64":
		c.decode = base64.StdEncoding.DecodeString
	default:
		return fmt.Errorf("hmac: unsupported encoding %q", c.Encoding)
	}
	if c.MaxBody == 0 {
		c.MaxBody = defaultMaxBody
	}
	secret, err := readSecretFile(c.SecretFile)
	if err != nil {
		return fmt.Errorf("hmac: %w", err)
	}
	c.secret = secret
	if c.DedupeHeader != "" {
		window := time.Duration(c.DedupeWindow)
		if window == 0 {
			window = time.Hour
		}
		c.seen = newSeenSet(window)
	}
	return nil
}

func (c *HMACChecker) Check(r *http.Request) (*Identity, *Failure) {
	given := r.Header.Get(c.Header)
	if given == "" {
		return nil, &Failure{Status: http.StatusUnauthorized, Reason: "missing signature header"}
	}
	if c.Prefix != "" {
		if !strings.HasPrefix(given, c.Prefix) {
			return nil, &Failure{Status: http.StatusUnauthorized, Reason: "signature header lacks prefix"}
		}
		given = strings.TrimPrefix(given, c.Prefix)
	}
	sig, err := c.decode(strings.TrimSpace(given))
	if err != nil {
		return nil, &Failure{Status: http.StatusUnauthorized, Reason: "signature is not valid " + c.encodingName()}
	}

	body, err := io.ReadAll(io.LimitReader(r.Body, c.MaxBody+1))
	if err != nil {
		return nil, &Failure{Status: http.StatusBadRequest, Reason: "reading body: " + err.Error()}
	}
	if int64(len(body)) > c.MaxBody {
		return nil, &Failure{Status: http.StatusRequestEntityTooLarge, Reason: "body exceeds " + strconv.FormatInt(c.MaxBody, 10) + " bytes"}
	}
	r.Body = io.NopCloser(bytes.NewReader(body))
	r.ContentLength = int64(len(body))

	mac := hmac.New(c.newHash, c.secret)
	mac.Write(body)
	if !hmac.Equal(sig, mac.Sum(nil)) {
		return nil, &Failure{Status: http.StatusUnauthorized, Reason: "signature mismatch"}
	}

	if c.seen != nil {
		id := r.Header.Get(c.DedupeHeader)
		if id == "" {
			return nil, &Failure{Status: http.StatusBadRequest, Reason: "missing " + c.DedupeHeader}
		}
		if !c.seen.add(id) {
			return nil, &Failure{Status: http.StatusConflict, Reason: "repeated delivery " + id}
		}
	}
	return nil, nil
}

func (c *HMACChecker) encodingName() string {
	if c.Encoding == "" {
		return "hex"
	}
	return c.Encoding
}

// UnmarshalCaddyfile parses the block after `bifrost_guard hmac`.
func (c *HMACChecker) UnmarshalCaddyfile(d *caddyfile.Dispenser) error {
	d.Next()
	for d.NextBlock(0) {
		key := d.Val()
		if key == "max_body" || key == "dedupe_window" {
			if !d.NextArg() {
				return d.ArgErr()
			}
			switch key {
			case "max_body":
				n, err := strconv.ParseInt(d.Val(), 10, 64)
				if err != nil {
					return d.Errf("max_body: %v", err)
				}
				c.MaxBody = n
			case "dedupe_window":
				dur, err := caddy.ParseDuration(d.Val())
				if err != nil {
					return d.Errf("dedupe_window: %v", err)
				}
				c.DedupeWindow = caddy.Duration(dur)
			}
			continue
		}
		var dst *string
		switch key {
		case "header":
			dst = &c.Header
		case "prefix":
			dst = &c.Prefix
		case "algorithm":
			dst = &c.Algorithm
		case "encoding":
			dst = &c.Encoding
		case "secret_file":
			dst = &c.SecretFile
		case "dedupe_header":
			dst = &c.DedupeHeader
		default:
			return d.Errf("hmac: unknown option %q", key)
		}
		if !d.AllArgs(dst) {
			return d.ArgErr()
		}
	}
	return nil
}

type seenSet struct {
	mu     sync.Mutex
	window time.Duration
	ids    map[string]time.Time
}

func newSeenSet(window time.Duration) *seenSet {
	return &seenSet{window: window, ids: make(map[string]time.Time)}
}

func (s *seenSet) add(id string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	now := time.Now()
	for k, t := range s.ids {
		if now.Sub(t) > s.window {
			delete(s.ids, k)
		}
	}
	if _, ok := s.ids[id]; ok {
		return false
	}
	s.ids[id] = now
	return true
}

var (
	_ caddy.Provisioner     = (*HMACChecker)(nil)
	_ Checker               = (*HMACChecker)(nil)
	_ caddyfile.Unmarshaler = (*HMACChecker)(nil)
)
