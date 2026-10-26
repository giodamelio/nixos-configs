package bifrost

import (
	"crypto/subtle"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"slices"
	"strings"
	"time"

	"github.com/caddyserver/caddy/v2"
	"github.com/caddyserver/caddy/v2/caddyconfig/caddyfile"
	"github.com/caddyserver/caddy/v2/caddyconfig/httpcaddyfile"
	"github.com/caddyserver/caddy/v2/modules/caddyhttp"
	"github.com/ory/fosite"
	"go.uber.org/zap"
)

func init() {
	caddy.RegisterModule(AuthServer{})
	httpcaddyfile.RegisterHandlerDirective("bifrost_authserver", parseAuthServer)
	httpcaddyfile.RegisterDirectiveOrder("bifrost_authserver", httpcaddyfile.Before, "respond")
}

const flowCookie = "bifrost_flow"

var errInvalidTarget = &fosite.RFC6749Error{
	ErrorField:       "invalid_target",
	DescriptionField: "The requested resource is invalid, unknown, or malformed.",
	CodeField:        http.StatusBadRequest,
}

// AuthServer serves the OAuth endpoints and the admin page on the auth host.
type AuthServer struct {
	// AdminNetworks are the only source ranges /admin answers to.
	AdminNetworks []string `json:"admin_networks,omitempty"`

	app      *App
	networks []*net.IPNet
	logger   *zap.Logger
}

func (AuthServer) CaddyModule() caddy.ModuleInfo {
	return caddy.ModuleInfo{
		ID:  "http.handlers.bifrost_authserver",
		New: func() caddy.Module { return new(AuthServer) },
	}
}

func (h *AuthServer) Provision(ctx caddy.Context) error {
	h.logger = ctx.Logger()
	app, err := ctx.AppIfConfigured(appName)
	if err != nil {
		return fmt.Errorf("bifrost_authserver needs the global bifrost block: %w", err)
	}
	h.app = app.(*App)
	return h.setup()
}

func (h *AuthServer) setup() error {
	h.networks = nil
	for _, cidr := range h.AdminNetworks {
		_, n, err := net.ParseCIDR(cidr)
		if err != nil {
			return fmt.Errorf("bifrost_authserver: admin network %q: %w", cidr, err)
		}
		h.networks = append(h.networks, n)
	}
	return nil
}

func (h *AuthServer) ServeHTTP(w http.ResponseWriter, r *http.Request, _ caddyhttp.Handler) error {
	p := r.URL.Path
	switch {
	case p == "/.well-known/oauth-authorization-server":
		h.cors(w, r, h.app.handleMetadata)
	case p == "/.well-known/jwks.json":
		h.cors(w, r, h.app.handleJWKS)
	case p == "/authorize":
		h.app.handleAuthorize(w, r)
	case p == "/callback":
		h.app.handleCallback(w, r)
	case p == "/consent":
		h.app.handleConsent(w, r)
	case p == "/token":
		h.cors(w, r, h.app.handleToken)
	case p == "/register":
		h.cors(w, r, h.app.handleRegister)
	case p == "/revoke":
		h.cors(w, r, h.app.handleRevoke)
	case p == "/admin" || strings.HasPrefix(p, "/admin/"):
		if !h.adminAllowed(r) {
			h.reject(w, r, "admin from outside admin networks")
			return nil
		}
		h.app.handleAdmin(w, r)
	default:
		h.reject(w, r, "no route")
	}
	return nil
}

func (h *AuthServer) reject(w http.ResponseWriter, r *http.Request, reason string) {
	f := &Failure{Status: http.StatusNotFound, Reason: reason}
	logFailure(h.logger, r, "authserver", f)
	h.app.shared.stats.recordFailure(r, "authserver", f)
	writeFailure(w, f)
}

func (h *AuthServer) adminAllowed(r *http.Request) bool {
	ip := net.ParseIP(clientIP(r))
	if ip == nil {
		return false
	}
	for _, n := range h.networks {
		if n.Contains(ip) {
			return true
		}
	}
	return false
}

// cors opens the machine-facing endpoints to browser-based MCP clients. None
// of them use cookies, so a wildcard origin grants nothing extra.
func (h *AuthServer) cors(w http.ResponseWriter, r *http.Request, next http.HandlerFunc) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	if r.Method == http.MethodOptions {
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type, MCP-Protocol-Version")
		w.Header().Set("Access-Control-Max-Age", "86400")
		w.WriteHeader(http.StatusNoContent)
		return
	}
	next(w, r)
}

func (a *App) handleMetadata(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"issuer":                                     a.Issuer,
		"authorization_endpoint":                     a.Issuer + "/authorize",
		"token_endpoint":                             a.Issuer + "/token",
		"registration_endpoint":                      a.Issuer + "/register",
		"revocation_endpoint":                        a.Issuer + "/revoke",
		"jwks_uri":                                   a.Issuer + "/.well-known/jwks.json",
		"response_types_supported":                   []string{"code"},
		"response_modes_supported":                   []string{"query"},
		"grant_types_supported":                      []string{"authorization_code", "refresh_token"},
		"code_challenge_methods_supported":           []string{"S256"},
		"token_endpoint_auth_methods_supported":      []string{authMethodNone, authMethodBasic, authMethodPost},
		"revocation_endpoint_auth_methods_supported": []string{authMethodNone, authMethodBasic, authMethodPost},
		"scopes_supported":                           a.resources.allScopes(),
		"client_id_metadata_document_supported":      true,
	})
}

func (a *App) handleJWKS(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "public, max-age=300")
	_ = jsonEncode(w, a.shared.keys.jwks())
}

// resolveResources applies RFC 8707: every `resource` must be served here,
// and becomes fosite's audience. Clients can't set `audience` directly.
func (a *App) resolveResources(form url.Values) ([]string, error) {
	form.Del("audience")
	raw := form["resource"]
	if len(raw) == 0 {
		return nil, fmt.Errorf("the resource parameter is required")
	}
	var out []string
	for _, r := range raw {
		uri, err := a.resources.resolve(r)
		if err != nil {
			return nil, err
		}
		if !slices.Contains(out, uri) {
			out = append(out, uri)
		}
	}
	form["audience"] = out
	return out, nil
}

func (a *App) handleAuthorize(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if err := r.ParseForm(); err != nil {
		http.Error(w, "malformed request", http.StatusBadRequest)
		return
	}
	resources, resErr := a.resolveResources(r.Form)

	ar, err := a.provider.NewAuthorizeRequest(withRequestedRedirect(ctx, r.Form.Get("redirect_uri")), r)
	if err != nil {
		a.provider.WriteAuthorizeError(ctx, w, ar, err)
		return
	}
	if resErr != nil {
		a.provider.WriteAuthorizeError(ctx, w, ar, errInvalidTarget.WithHint(resErr.Error()))
		return
	}
	for _, scope := range ar.GetRequestedScopes() {
		if !a.scopeOffered(scope, resources) {
			a.provider.WriteAuthorizeError(ctx, w, ar, fosite.ErrInvalidScope.WithHintf("Scope %q is not offered by the requested resource.", scope))
			return
		}
	}

	f := a.shared.flows.start(flowAuthorize)
	f.ar = ar
	f.resources = resources
	a.redirectToLogin(w, r, f)
}

func (a *App) scopeOffered(scope string, resources []string) bool {
	for _, res := range resources {
		scopes, _ := a.resources.scopes(res)
		if slices.Contains(scopes, scope) {
			return true
		}
	}
	return false
}

func (a *App) redirectToLogin(w http.ResponseWriter, r *http.Request, f *flow) {
	target, err := a.login.authURL(r.Context(), f)
	if err != nil {
		a.shared.flows.finish(f.id)
		a.logger.Error("starting the Pocket ID login", errField(err))
		renderError(w, http.StatusBadGateway, "The login provider is unavailable", err.Error())
		return
	}
	// Binds the round trip to this browser, so a login started elsewhere
	// can't be completed here.
	http.SetCookie(w, &http.Cookie{
		Name:     flowCookie,
		Value:    f.id,
		Path:     "/",
		MaxAge:   int(flowLifetime.Seconds()),
		HttpOnly: true,
		Secure:   true,
		SameSite: http.SameSiteLaxMode,
	})
	http.Redirect(w, r, target, http.StatusFound)
}

// flowFor returns the flow named by id, only if this browser started it.
func (a *App) flowFor(r *http.Request, id string) (*flow, bool) {
	c, err := r.Cookie(flowCookie)
	if err != nil || subtle.ConstantTimeCompare([]byte(c.Value), []byte(id)) != 1 {
		return nil, false
	}
	return a.shared.flows.get(id)
}

func (a *App) handleCallback(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	f, ok := a.flowFor(r, q.Get("state"))
	if !ok {
		renderError(w, http.StatusBadRequest, "This login link is no longer valid", "Start again from the application that sent you here.")
		return
	}
	if e := q.Get("error"); e != "" {
		a.shared.flows.finish(f.id)
		desc := q.Get("error_description")
		if f.kind == flowAuthorize {
			a.provider.WriteAuthorizeError(r.Context(), w, f.ar, fosite.ErrAccessDenied.WithHintf("Login failed: %s %s", e, desc))
			return
		}
		renderError(w, http.StatusUnauthorized, "Login failed", e+" "+desc)
		return
	}
	u, err := a.login.exchange(r.Context(), f, q.Get("code"), time.Now())
	if err != nil {
		a.shared.flows.finish(f.id)
		a.logger.Warn("login rejected", errField(err), zap.String("remote_ip", clientIP(r)))
		if f.kind == flowAuthorize {
			a.provider.WriteAuthorizeError(r.Context(), w, f.ar, fosite.ErrAccessDenied.WithHint(err.Error()))
			return
		}
		renderError(w, http.StatusUnauthorized, "Login rejected", err.Error())
		return
	}
	f.user = u

	if f.kind == flowAdmin {
		a.shared.flows.finish(f.id)
		a.setAdminSession(w, u)
		http.Redirect(w, r, "/admin", http.StatusSeeOther)
		return
	}
	for _, res := range f.resources {
		if !inAllowedGroup(a.resources.groups(res), u.Groups) {
			a.shared.flows.finish(f.id)
			a.logger.Warn("grant refused: not in an allowed group",
				zap.String("user", u.Username), zap.String("resource", res), zap.String("remote_ip", clientIP(r)))
			a.provider.WriteAuthorizeError(r.Context(), w, f.ar, fosite.ErrAccessDenied.WithHintf("%s is not in a group allowed to use %s.", u.Username, res))
			return
		}
	}
	a.renderConsent(w, f)
}

func (a *App) handleConsent(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if err := r.ParseForm(); err != nil {
		http.Error(w, "malformed request", http.StatusBadRequest)
		return
	}
	f, ok := a.flowFor(r, r.PostForm.Get("flow"))
	if !ok || f.kind != flowAuthorize || f.user == nil ||
		subtle.ConstantTimeCompare([]byte(r.PostForm.Get("csrf")), []byte(f.csrf)) != 1 {
		renderError(w, http.StatusBadRequest, "This approval is no longer valid", "Start again from the application that sent you here.")
		return
	}
	a.shared.flows.finish(f.id)
	ctx := r.Context()

	if r.PostForm.Get("action") != "approve" {
		a.provider.WriteAuthorizeError(ctx, w, f.ar, fosite.ErrAccessDenied.WithHint("You declined the request."))
		return
	}

	for _, s := range f.ar.GetRequestedScopes() {
		f.ar.GrantScope(s)
	}
	for _, aud := range f.ar.GetRequestedAudience() {
		f.ar.GrantAudience(aud)
	}
	client := f.ar.GetClient()
	sess := &Session{
		Subject:    f.user.Subject,
		Username:   f.user.Username,
		Email:      f.user.Email,
		Name:       f.user.Name,
		ClientName: clientName(client),
		Groups:     f.user.Groups,
	}
	resp, err := a.provider.NewAuthorizeResponse(ctx, f.ar, sess)
	if err != nil {
		a.provider.WriteAuthorizeError(ctx, w, f.ar, err)
		return
	}
	grant := &Grant{
		ID:           f.ar.GetID(),
		Subject:      f.user.Subject,
		Username:     f.user.Username,
		Email:        f.user.Email,
		ClientID:     client.GetID(),
		ClientName:   clientName(client),
		RedirectHost: redirectHost(f.ar),
		Audience:     f.ar.GetGrantedAudience(),
		Scopes:       f.ar.GetGrantedScopes(),
		Groups:       f.user.Groups,
		CreatedAt:    time.Now().UTC(),
	}
	if err := a.shared.store.createGrant(ctx, grant); err != nil {
		a.logger.Error("saving grant", errField(err))
		a.provider.WriteAuthorizeError(ctx, w, f.ar, fosite.ErrServerError.WithWrap(err))
		return
	}
	a.logger.Info("grant approved",
		zap.String("grant_id", grant.ID),
		zap.String("user", grant.Username),
		zap.String("client_id", grant.ClientID),
		zap.String("redirect_host", grant.RedirectHost),
		zap.Strings("audience", grant.Audience))
	a.provider.WriteAuthorizeResponse(ctx, w, f.ar, resp)
}

func clientName(c fosite.Client) string {
	if n, ok := c.(namedClient); ok && n.ClientName() != "" {
		return n.ClientName()
	}
	return c.GetID()
}

func redirectHost(ar fosite.AuthorizeRequester) string {
	if u := ar.GetRedirectURI(); u != nil {
		return u.Host
	}
	return ""
}

func (a *App) handleToken(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if r.Method == http.MethodPost {
		if err := r.ParseForm(); err == nil && len(r.PostForm["resource"]) > 0 {
			if _, err := a.resolveResources(r.PostForm); err != nil {
				a.provider.WriteAccessError(ctx, w, nil, errInvalidTarget.WithHint(err.Error()))
				return
			}
		} else {
			r.PostForm.Del("audience")
		}
	}
	ar, err := a.provider.NewAccessRequest(ctx, r, &Session{})
	if err != nil {
		a.logger.Debug("token request refused", errField(err))
		a.provider.WriteAccessError(ctx, w, ar, err)
		return
	}
	resp, err := a.provider.NewAccessResponse(ctx, ar)
	if err != nil {
		a.provider.WriteAccessError(ctx, w, ar, err)
		return
	}
	a.provider.WriteAccessResponse(ctx, w, ar, resp)
}

func (a *App) handleRevoke(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	err := a.provider.NewRevocationRequest(ctx, r)
	a.provider.WriteRevocationResponse(ctx, w, err)
}

// UnmarshalCaddyfile parses:
//
//	bifrost_authserver {
//		admin_networks <cidr...>
//	}
func (h *AuthServer) UnmarshalCaddyfile(d *caddyfile.Dispenser) error {
	d.Next()
	for d.NextBlock(0) {
		switch d.Val() {
		case "admin_networks":
			args := d.RemainingArgs()
			if len(args) == 0 {
				return d.ArgErr()
			}
			h.AdminNetworks = append(h.AdminNetworks, args...)
		default:
			return d.Errf("bifrost_authserver: unknown option %q", d.Val())
		}
	}
	return nil
}

func parseAuthServer(h httpcaddyfile.Helper) (caddyhttp.MiddlewareHandler, error) {
	var s AuthServer
	err := s.UnmarshalCaddyfile(h.Dispenser)
	return &s, err
}

var (
	_ caddy.Provisioner           = (*AuthServer)(nil)
	_ caddyhttp.MiddlewareHandler = (*AuthServer)(nil)
	_ caddyfile.Unmarshaler       = (*AuthServer)(nil)
)
