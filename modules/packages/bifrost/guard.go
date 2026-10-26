package bifrost

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"

	"github.com/caddyserver/caddy/v2"
	"github.com/caddyserver/caddy/v2/caddyconfig"
	"github.com/caddyserver/caddy/v2/caddyconfig/caddyfile"
	"github.com/caddyserver/caddy/v2/caddyconfig/httpcaddyfile"
	"github.com/caddyserver/caddy/v2/modules/caddyhttp"
	"go.uber.org/zap"
)

func init() {
	caddy.RegisterModule(Guard{})
	httpcaddyfile.RegisterHandlerDirective("bifrost_guard", parseGuard)
	httpcaddyfile.RegisterDirectiveOrder("bifrost_guard", httpcaddyfile.Before, "basic_auth")
}

// Guard runs one checker and only passes requests that satisfy it.
type Guard struct {
	CheckerRaw json.RawMessage `json:"checker,omitempty" caddy:"namespace=bifrost.checkers inline_key=type"`

	checker     Checker
	checkerName string
	stats       *Stats
	logger      *zap.Logger
}

func (Guard) CaddyModule() caddy.ModuleInfo {
	return caddy.ModuleInfo{
		ID:  "http.handlers.bifrost_guard",
		New: func() caddy.Module { return new(Guard) },
	}
}

func (g *Guard) Provision(ctx caddy.Context) error {
	g.logger = ctx.Logger()
	if g.CheckerRaw == nil {
		return fmt.Errorf("bifrost_guard: a checker is required")
	}
	var probe struct {
		Type string `json:"type"`
	}
	if err := json.Unmarshal(g.CheckerRaw, &probe); err != nil {
		return fmt.Errorf("bifrost_guard: reading checker type: %w", err)
	}
	g.checkerName = probe.Type
	mod, err := ctx.LoadModule(g, "CheckerRaw")
	if err != nil {
		return fmt.Errorf("bifrost_guard: loading checker: %w", err)
	}
	g.checker = mod.(Checker)

	appIface, err := ctx.AppIfConfigured(appName)
	switch {
	case err == nil:
		g.stats = appIface.(*App).shared.stats
	case errors.Is(err, caddy.ErrNotConfigured):
	default:
		return fmt.Errorf("bifrost_guard: %w", err)
	}
	return nil
}

func (g *Guard) ServeHTTP(w http.ResponseWriter, r *http.Request, next caddyhttp.Handler) error {
	stripBifrostHeaders(r.Header)

	if ic, ok := g.checker.(Interceptor); ok && ic.Intercept(w, r) {
		return nil
	}

	id, fail := g.checker.Check(r)
	if fail != nil {
		logFailure(g.logger, r, g.checkerName, fail)
		if g.stats != nil {
			g.stats.recordFailure(r, g.checkerName, fail)
		}
		writeFailure(w, fail)
		return nil
	}

	if id != nil {
		setIdentity(r, id)
	}
	if g.stats != nil {
		g.stats.recordRequest(requestHost(r))
	}
	return next.ServeHTTP(w, r)
}

func setIdentity(r *http.Request, id *Identity) {
	ctx := r.Context()
	vars := map[string]string{
		"user":        id.Username,
		"sub":         id.Subject,
		"email":       id.Email,
		"name":        id.Name,
		"client_id":   id.ClientID,
		"client_name": id.ClientName,
		"grant_id":    id.GrantID,
		"scopes":      strings.Join(id.Scopes, " "),
	}
	// Underscores, not dots: the Caddyfile's {vars.*} shorthand only matches [\w-].
	for k, v := range vars {
		caddyhttp.SetVar(ctx, "bifrost_"+k, v)
	}
	if id.Assertion != "" {
		r.Header.Set(headerPrefix+"Assertion", id.Assertion)
	}
}

// UnmarshalCaddyfile parses:
//
//	bifrost_guard <checker> {
//		<checker options>
//	}
func (g *Guard) UnmarshalCaddyfile(d *caddyfile.Dispenser) error {
	d.Next()
	if !d.NextArg() {
		return d.ArgErr()
	}
	name := d.Val()
	unm, err := caddyfile.UnmarshalModule(d, "bifrost.checkers."+name)
	if err != nil {
		return err
	}
	g.CheckerRaw = caddyconfig.JSONModuleObject(unm, "type", name, nil)
	return nil
}

func parseGuard(h httpcaddyfile.Helper) (caddyhttp.MiddlewareHandler, error) {
	var g Guard
	err := g.UnmarshalCaddyfile(h.Dispenser)
	return &g, err
}

var (
	_ caddy.Provisioner           = (*Guard)(nil)
	_ caddyhttp.MiddlewareHandler = (*Guard)(nil)
	_ caddyfile.Unmarshaler       = (*Guard)(nil)
)
