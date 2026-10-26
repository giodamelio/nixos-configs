package bifrost

import (
	"errors"
	"fmt"
	"net/http"

	"github.com/caddyserver/caddy/v2"
	"github.com/caddyserver/caddy/v2/caddyconfig/httpcaddyfile"
	"github.com/caddyserver/caddy/v2/modules/caddyhttp"
	"go.uber.org/zap"
)

func init() {
	caddy.RegisterModule(Reject{})
	httpcaddyfile.RegisterHandlerDirective("bifrost_reject", func(h httpcaddyfile.Helper) (caddyhttp.MiddlewareHandler, error) {
		h.Next()
		if h.NextArg() {
			return nil, h.ArgErr()
		}
		return new(Reject), nil
	})
	httpcaddyfile.RegisterDirectiveOrder("bifrost_reject", httpcaddyfile.Before, "respond")
}

// Reject is the catch-all: unknown hosts and paths are 404s that count as
// failures, so scanners feed fail2ban.
type Reject struct {
	stats  *Stats
	logger *zap.Logger
}

func (Reject) CaddyModule() caddy.ModuleInfo {
	return caddy.ModuleInfo{
		ID:  "http.handlers.bifrost_reject",
		New: func() caddy.Module { return new(Reject) },
	}
}

func (h *Reject) Provision(ctx caddy.Context) error {
	h.logger = ctx.Logger()
	app, err := ctx.AppIfConfigured(appName)
	switch {
	case err == nil:
		h.stats = app.(*App).shared.stats
	case errors.Is(err, caddy.ErrNotConfigured):
	default:
		return fmt.Errorf("bifrost_reject: %w", err)
	}
	return nil
}

func (h *Reject) ServeHTTP(w http.ResponseWriter, r *http.Request, _ caddyhttp.Handler) error {
	f := &Failure{Status: http.StatusNotFound, Reason: "no route"}
	logFailure(h.logger, r, "reject", f)
	if h.stats != nil {
		h.stats.recordFailure(r, "reject", f)
	}
	writeFailure(w, f)
	return nil
}

var (
	_ caddy.Provisioner           = (*Reject)(nil)
	_ caddyhttp.MiddlewareHandler = (*Reject)(nil)
)
