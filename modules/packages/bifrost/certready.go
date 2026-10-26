package bifrost

import (
	"fmt"
	"net"
	"sync"
	"time"

	"github.com/caddyserver/caddy/v2"
	"github.com/caddyserver/caddy/v2/caddyconfig/caddyfile"
	"github.com/caddyserver/caddy/v2/modules/caddytls"
	"go.uber.org/zap"
)

func init() {
	caddy.RegisterModule(CertReady{})
}

const defaultCertReadyTimeout = 30 * time.Second

// CertReady holds a listener's first Accept until the TLS app has a
// certificate for Subject. Caddy loads even stored certificates in the
// background, so a freshly restarted instance on a systemd socket would
// otherwise fail the handshakes already queued on it.
type CertReady struct {
	Subject string         `json:"subject,omitempty"`
	Timeout caddy.Duration `json:"timeout,omitempty"`

	tls    *caddytls.TLS
	logger *zap.Logger
}

func (CertReady) CaddyModule() caddy.ModuleInfo {
	return caddy.ModuleInfo{
		ID:  "caddy.listeners.bifrost_cert_ready",
		New: func() caddy.Module { return new(CertReady) },
	}
}

func (c *CertReady) Provision(ctx caddy.Context) error {
	if c.Subject == "" {
		return fmt.Errorf("bifrost_cert_ready: a subject is required")
	}
	if c.Timeout == 0 {
		c.Timeout = caddy.Duration(defaultCertReadyTimeout)
	}
	app, err := ctx.App("tls")
	if err != nil {
		return fmt.Errorf("bifrost_cert_ready: %w", err)
	}
	c.tls = app.(*caddytls.TLS)
	c.logger = ctx.Logger()
	return nil
}

func (c *CertReady) WrapListener(ln net.Listener) net.Listener {
	return &certReadyListener{Listener: ln, cfg: c}
}

type certReadyListener struct {
	net.Listener
	cfg  *CertReady
	once sync.Once
}

func (l *certReadyListener) Accept() (net.Conn, error) {
	l.once.Do(l.wait)
	return l.Listener.Accept()
}

// wait gives up after the timeout, so a certificate that has to be issued
// first can't hold the listener shut indefinitely.
func (l *certReadyListener) wait() {
	start := time.Now()
	deadline := start.Add(time.Duration(l.cfg.Timeout))
	for !l.cfg.tls.HasCertificateForSubject(l.cfg.Subject) {
		if time.Now().After(deadline) {
			l.cfg.logger.Warn("accepting connections without a certificate", zap.String("subject", l.cfg.Subject), zap.Duration("waited", time.Since(start)))
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	if waited := time.Since(start); waited > 0 {
		l.cfg.logger.Debug("certificate ready", zap.String("subject", l.cfg.Subject), zap.Duration("waited", waited))
	}
}

// UnmarshalCaddyfile parses `bifrost_cert_ready <subject> [<timeout>]`.
func (c *CertReady) UnmarshalCaddyfile(d *caddyfile.Dispenser) error {
	d.Next()
	if !d.NextArg() {
		return d.ArgErr()
	}
	c.Subject = d.Val()
	if d.NextArg() {
		t, err := caddy.ParseDuration(d.Val())
		if err != nil {
			return d.Errf("bifrost_cert_ready: timeout: %v", err)
		}
		c.Timeout = caddy.Duration(t)
	}
	if d.NextArg() {
		return d.ArgErr()
	}
	return nil
}

var (
	_ caddy.Provisioner     = (*CertReady)(nil)
	_ caddy.ListenerWrapper = (*CertReady)(nil)
	_ caddyfile.Unmarshaler = (*CertReady)(nil)
)
