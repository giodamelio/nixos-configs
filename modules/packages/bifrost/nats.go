package bifrost

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/caddyserver/caddy/v2"
	"github.com/caddyserver/caddy/v2/caddyconfig/caddyfile"
	"github.com/caddyserver/caddy/v2/caddyconfig/httpcaddyfile"
	"github.com/caddyserver/caddy/v2/modules/caddyhttp"
	"github.com/nats-io/nats.go"
	"github.com/nats-io/nats.go/jetstream"
	"go.uber.org/zap"
)

func init() {
	caddy.RegisterModule(NATSPublisher{})
	httpcaddyfile.RegisterHandlerDirective("bifrost_nats", parseNATSPublisher)
	httpcaddyfile.RegisterDirectiveOrder("bifrost_nats", httpcaddyfile.Before, "respond")
}

// NATSConfig is the connection the bifrost_nats handlers publish through.
type NATSConfig struct {
	URL       string `json:"url,omitempty"`
	CredsFile string `json:"creds_file,omitempty"`
	TokenFile string `json:"token_file,omitempty"`
}

type natsConn struct {
	nc *nats.Conn
	js jetstream.JetStream
}

func (c *natsConn) Destruct() error {
	return c.nc.Drain()
}

var natsPool = caddy.NewUsagePool()

func (cfg NATSConfig) poolKey() string {
	return strings.Join([]string{cfg.URL, cfg.CredsFile, cfg.TokenFile}, "\x00")
}

// connect keeps retrying in the background, so NATS being down never stops
// Caddy from starting; publishes fail with 503 until it is back.
func (cfg NATSConfig) connect(logger *zap.Logger) (*natsConn, error) {
	opts := []nats.Option{
		nats.Name("bifrost"),
		nats.RetryOnFailedConnect(true),
		nats.MaxReconnects(-1),
		nats.ReconnectWait(2 * time.Second),
		nats.DisconnectErrHandler(func(_ *nats.Conn, err error) {
			logger.Warn("NATS disconnected", zap.Error(err))
		}),
		nats.ReconnectHandler(func(nc *nats.Conn) {
			logger.Info("NATS reconnected", zap.String("url", nc.ConnectedUrl()))
		}),
	}
	if cfg.CredsFile != "" {
		opts = append(opts, nats.UserCredentials(cfg.CredsFile))
	}
	if cfg.TokenFile != "" {
		token, err := readSecretFile(cfg.TokenFile)
		if err != nil {
			return nil, fmt.Errorf("nats token: %w", err)
		}
		opts = append(opts, nats.Token(string(token)))
	}
	nc, err := nats.Connect(cfg.URL, opts...)
	if err != nil {
		return nil, fmt.Errorf("connecting to NATS: %w", err)
	}
	js, err := jetstream.New(nc)
	if err != nil {
		nc.Close()
		return nil, err
	}
	return &natsConn{nc: nc, js: js}, nil
}

// RequestMessage is what bifrost_nats publishes: the whole request as JSON.
type RequestMessage struct {
	Version      int                 `json:"version"`
	ReceivedAt   time.Time           `json:"received_at"`
	Method       string              `json:"method"`
	Host         string              `json:"host"`
	Path         string              `json:"path"`
	Query        map[string][]string `json:"query"`
	Headers      map[string][]string `json:"headers"`
	RemoteIP     string              `json:"remote_ip"`
	Body         string              `json:"body"`
	BodyEncoding string              `json:"body_encoding"`
	Identity     *MessageIdentity    `json:"identity"`
}

// MessageIdentity mirrors the assertion's claims when an oauth guard ran.
type MessageIdentity struct {
	Subject    string   `json:"sub"`
	Username   string   `json:"preferred_username"`
	Email      string   `json:"email"`
	Name       string   `json:"name"`
	ClientID   string   `json:"client_id"`
	ClientName string   `json:"client_name"`
	GrantID    string   `json:"grant_id"`
	Scopes     []string `json:"scopes"`
	Groups     []string `json:"groups"`
}

// NATSPublisher answers 202 once the request is on NATS, and 503 if it
// could not be published, so the sender retries instead of losing it.
type NATSPublisher struct {
	Subject   string `json:"subject,omitempty"`
	JetStream bool   `json:"jetstream,omitempty"`
	MaxBody   int64  `json:"max_body,omitempty"`

	conn   *natsConn
	stats  *Stats
	logger *zap.Logger
}

func (NATSPublisher) CaddyModule() caddy.ModuleInfo {
	return caddy.ModuleInfo{
		ID:  "http.handlers.bifrost_nats",
		New: func() caddy.Module { return new(NATSPublisher) },
	}
}

func (h *NATSPublisher) Provision(ctx caddy.Context) error {
	h.logger = ctx.Logger()
	app, err := ctx.AppIfConfigured(appName)
	if err != nil {
		return fmt.Errorf("bifrost_nats needs the global bifrost block: %w", err)
	}
	a := app.(*App)
	if a.natsConn == nil {
		return fmt.Errorf("bifrost_nats needs a nats block in the global bifrost block")
	}
	h.conn = a.natsConn
	h.stats = a.shared.stats
	return h.setup()
}

func (h *NATSPublisher) setup() error {
	if h.Subject == "" {
		return fmt.Errorf("bifrost_nats: subject is required")
	}
	if h.MaxBody == 0 {
		h.MaxBody = defaultMaxBody
	}
	return nil
}

func (h *NATSPublisher) ServeHTTP(w http.ResponseWriter, r *http.Request, _ caddyhttp.Handler) error {
	fail := func(status int, reason string) error {
		f := &Failure{Status: status, Reason: reason, Quiet: true}
		h.logger.Error("publishing request to NATS failed",
			zap.String("remote_ip", clientIP(r)),
			zap.String("host", requestHost(r)),
			zap.String("reason", reason))
		writeFailure(w, f)
		return nil
	}

	body, err := io.ReadAll(io.LimitReader(r.Body, h.MaxBody+1))
	if err != nil {
		return fail(http.StatusBadRequest, "reading body: "+err.Error())
	}
	if int64(len(body)) > h.MaxBody {
		return fail(http.StatusRequestEntityTooLarge, "body exceeds "+strconv.FormatInt(h.MaxBody, 10)+" bytes")
	}

	msg := buildMessage(r, body, time.Now().UTC())
	data, err := json.Marshal(msg)
	if err != nil {
		return fail(http.StatusInternalServerError, "encoding message: "+err.Error())
	}
	if max := h.conn.nc.MaxPayload(); max > 0 && int64(len(data)) > max {
		return fail(http.StatusRequestEntityTooLarge, fmt.Sprintf("message is %d bytes, NATS accepts %d", len(data), max))
	}

	repl, _ := r.Context().Value(caddy.ReplacerCtxKey).(*caddy.Replacer)
	subject := h.Subject
	if repl != nil {
		subject = repl.ReplaceAll(subject, "")
	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	if err := h.publish(ctx, subject, data); err != nil {
		return fail(http.StatusServiceUnavailable, err.Error())
	}

	if h.stats != nil {
		h.stats.recordRequest(requestHost(r))
	}
	writeJSON(w, http.StatusAccepted, map[string]string{"status": "accepted"})
	return nil
}

func (h *NATSPublisher) publish(ctx context.Context, subject string, data []byte) error {
	if !h.conn.nc.IsConnected() {
		return fmt.Errorf("not connected to NATS (%s)", h.conn.nc.Status())
	}
	if h.JetStream {
		if _, err := h.conn.js.Publish(ctx, subject, data); err != nil {
			return fmt.Errorf("JetStream publish to %s: %w", subject, err)
		}
		return nil
	}
	if err := h.conn.nc.Publish(subject, data); err != nil {
		return fmt.Errorf("publish to %s: %w", subject, err)
	}
	// A core publish only reaches a local buffer; the flush round trip is what
	// confirms the server has it.
	if err := h.conn.nc.FlushWithContext(ctx); err != nil {
		return fmt.Errorf("flushing to NATS: %w", err)
	}
	return nil
}

func buildMessage(r *http.Request, body []byte, now time.Time) RequestMessage {
	headers := make(map[string][]string, len(r.Header))
	for k, v := range r.Header {
		// Authorization may be a bearer route's shared secret; X-Bifrost-* is
		// carried in the identity field instead.
		if strings.EqualFold(k, "Authorization") || strings.HasPrefix(http.CanonicalHeaderKey(k), headerPrefix) {
			continue
		}
		headers[k] = v
	}
	msg := RequestMessage{
		Version:    1,
		ReceivedAt: now,
		Method:     r.Method,
		Host:       requestHost(r),
		Path:       originalPath(r),
		Query:      r.URL.Query(),
		Headers:    headers,
		RemoteIP:   clientIP(r),
	}
	if utf8.Valid(body) {
		msg.Body, msg.BodyEncoding = string(body), "utf-8"
	} else {
		msg.Body, msg.BodyEncoding = base64.StdEncoding.EncodeToString(body), "base64"
	}
	if sub, _ := caddyhttp.GetVar(r.Context(), "bifrost_sub").(string); sub != "" {
		get := func(k string) string {
			v, _ := caddyhttp.GetVar(r.Context(), "bifrost_"+k).(string)
			return v
		}
		msg.Identity = &MessageIdentity{
			Subject:    sub,
			Username:   get("user"),
			Email:      get("email"),
			Name:       get("name"),
			ClientID:   get("client_id"),
			ClientName: get("client_name"),
			GrantID:    get("grant_id"),
			Scopes:     strings.Fields(get("scopes")),
			Groups:     strings.Fields(get("groups")),
		}
	}
	return msg
}

// UnmarshalCaddyfile parses:
//
//	bifrost_nats {
//		subject <subject>
//		jetstream
//		max_body <bytes>
//	}
func (h *NATSPublisher) UnmarshalCaddyfile(d *caddyfile.Dispenser) error {
	d.Next()
	for d.NextBlock(0) {
		switch d.Val() {
		case "subject":
			if !d.AllArgs(&h.Subject) {
				return d.ArgErr()
			}
		case "jetstream":
			if d.NextArg() {
				return d.ArgErr()
			}
			h.JetStream = true
		case "max_body":
			if !d.NextArg() {
				return d.ArgErr()
			}
			n, err := strconv.ParseInt(d.Val(), 10, 64)
			if err != nil {
				return d.Errf("max_body: %v", err)
			}
			h.MaxBody = n
		default:
			return d.Errf("bifrost_nats: unknown option %q", d.Val())
		}
	}
	return nil
}

func parseNATSPublisher(h httpcaddyfile.Helper) (caddyhttp.MiddlewareHandler, error) {
	var p NATSPublisher
	err := p.UnmarshalCaddyfile(h.Dispenser)
	return &p, err
}

var (
	_ caddy.Provisioner           = (*NATSPublisher)(nil)
	_ caddyhttp.MiddlewareHandler = (*NATSPublisher)(nil)
	_ caddyfile.Unmarshaler       = (*NATSPublisher)(nil)
)
