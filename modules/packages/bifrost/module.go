// Package bifrost is a Caddy plugin that guards every request entering the
// LAN from the internet: webhook signatures, static bearer tokens, and OAuth
// tokens it issues itself as an authorization server.
package bifrost

import (
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"strings"

	"github.com/caddyserver/caddy/v2/modules/caddyhttp"
	"go.uber.org/zap"
)

// FailureMessage is the log message fail2ban matches on; keep it stable.
const FailureMessage = "bifrost check failed"

const headerPrefix = "X-Bifrost-"

// Identity is who a passing check authenticated. Checkers without a user
// (hmac, bearer) return nil.
type Identity struct {
	Subject    string
	Username   string
	Email      string
	Name       string
	ClientID   string
	ClientName string
	GrantID    string
	Scopes     []string
	Groups     []string
	Assertion  string
}

// Failure is a rejected request. Quiet failures are part of normal protocol
// flow (an MCP client's first, unauthenticated request) and don't feed fail2ban.
type Failure struct {
	Status int
	Reason string
	Header http.Header
	Quiet  bool
}

// Checker decides whether a request may pass.
type Checker interface {
	Check(r *http.Request) (*Identity, *Failure)
}

// Interceptor lets a checker answer some requests itself, such as OAuth
// discovery documents, before any check runs.
type Interceptor interface {
	Intercept(w http.ResponseWriter, r *http.Request) bool
}

func readSecretFile(path string) ([]byte, error) {
	if path == "" {
		return nil, fmt.Errorf("no secret file configured")
	}
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("reading secret file: %w", err)
	}
	b = []byte(strings.TrimSpace(string(b)))
	if len(b) == 0 {
		return nil, fmt.Errorf("secret file %s is empty", path)
	}
	return b, nil
}

func clientIP(r *http.Request) string {
	if ip, ok := caddyhttp.GetVar(r.Context(), caddyhttp.ClientIPVarKey).(string); ok && ip != "" {
		return ip
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

func requestHost(r *http.Request) string {
	host := r.Host
	if h, _, err := net.SplitHostPort(host); err == nil {
		host = h
	}
	return strings.ToLower(host)
}

// originalPath is the path before any rewrite in the route, so discovery
// documents answer at the subdomain root even behind `rewrite * /mcp{uri}`.
func originalPath(r *http.Request) string {
	if orig, ok := r.Context().Value(caddyhttp.OriginalRequestCtxKey).(http.Request); ok && orig.URL != nil {
		return orig.URL.Path
	}
	return r.URL.Path
}

func stripBifrostHeaders(h http.Header) {
	for name := range h {
		if strings.HasPrefix(http.CanonicalHeaderKey(name), headerPrefix) {
			delete(h, name)
		}
	}
}

func logFailure(logger *zap.Logger, r *http.Request, checker string, f *Failure) {
	fields := []zap.Field{
		zap.String("remote_ip", clientIP(r)),
		zap.String("host", requestHost(r)),
		zap.String("method", r.Method),
		zap.String("path", r.URL.Path),
		zap.String("checker", checker),
		zap.String("reason", f.Reason),
		zap.Int("status", f.Status),
	}
	if f.Quiet {
		logger.Debug("bifrost check declined", fields...)
		return
	}
	logger.Warn(FailureMessage, fields...)
}

func writeFailure(w http.ResponseWriter, f *Failure) {
	for k, v := range f.Header {
		w.Header()[k] = v
	}
	writeJSON(w, f.Status, map[string]string{"error": http.StatusText(f.Status)})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = jsonEncode(w, v)
}

func jsonEncode(w io.Writer, v any) error {
	return json.NewEncoder(w).Encode(v)
}
