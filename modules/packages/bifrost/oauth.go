package bifrost

import (
	"fmt"
	"net/http"
	"slices"
	"strings"
	"time"

	"github.com/caddyserver/caddy/v2"
	"github.com/caddyserver/caddy/v2/caddyconfig/caddyfile"
	"github.com/ory/fosite"
)

func init() {
	caddy.RegisterModule(OAuthChecker{})
}

const protectedResourcePath = "/.well-known/oauth-protected-resource"

// OAuthChecker accepts bifrost access tokens issued for this subdomain. It
// registers the subdomain as a protected resource and serves its RFC 9728
// metadata, so it is all an MCP server needs in front of it.
type OAuthChecker struct {
	Host    string   `json:"host,omitempty"`
	Scopes  []string `json:"scopes,omitempty"`
	Require []string `json:"require,omitempty"`
	// Groups admits members of any listed Pocket ID group. A guard must set
	// Groups or AnyGroup, so a new service is never open by accident.
	Groups   []string `json:"groups,omitempty"`
	AnyGroup bool     `json:"any_group,omitempty"`

	app      *App
	resource string
}

func (OAuthChecker) CaddyModule() caddy.ModuleInfo {
	return caddy.ModuleInfo{
		ID:  "bifrost.checkers.oauth",
		New: func() caddy.Module { return new(OAuthChecker) },
	}
}

func (c *OAuthChecker) Provision(ctx caddy.Context) error {
	app, err := ctx.AppIfConfigured(appName)
	if err != nil {
		return fmt.Errorf("oauth checker needs the global bifrost block: %w", err)
	}
	return c.setup(app.(*App))
}

func (c *OAuthChecker) setup(app *App) error {
	if c.Host == "" {
		return fmt.Errorf("oauth: host is required")
	}
	if len(c.Groups) == 0 && !c.AnyGroup {
		return fmt.Errorf("oauth %s: set groups, or any_group to admit every account that can log in", c.Host)
	}
	if len(c.Groups) > 0 && c.AnyGroup {
		return fmt.Errorf("oauth %s: groups and any_group are exclusive", c.Host)
	}
	for _, s := range c.Require {
		if !slices.Contains(c.Scopes, s) {
			return fmt.Errorf("oauth: required scope %q is not in scopes", s)
		}
	}
	c.app = app
	c.resource = resourceForHost(c.Host)
	return app.registerResource(c.resource, c.Scopes, c.Groups)
}

func (c *OAuthChecker) metadataURL() string {
	return c.resource + protectedResourcePath
}

func (c *OAuthChecker) Intercept(w http.ResponseWriter, r *http.Request) bool {
	p := originalPath(r)
	if p != protectedResourcePath && !strings.HasPrefix(p, protectedResourcePath+"/") {
		return false
	}
	w.Header().Set("Access-Control-Allow-Origin", "*")
	if r.Method == http.MethodOptions {
		w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "MCP-Protocol-Version")
		w.WriteHeader(http.StatusNoContent)
		return true
	}
	scopes := c.Scopes
	if scopes == nil {
		scopes = []string{}
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"resource":                 c.resource,
		"authorization_servers":    []string{c.app.Issuer},
		"scopes_supported":         scopes,
		"bearer_methods_supported": []string{"header"},
		"resource_name":            c.Host,
	})
	return true
}

func (c *OAuthChecker) challenge(errCode, desc string, scopes []string) http.Header {
	parts := []string{fmt.Sprintf("resource_metadata=%q", c.metadataURL())}
	if len(scopes) > 0 {
		parts = append(parts, fmt.Sprintf("scope=%q", strings.Join(scopes, " ")))
	}
	if errCode != "" {
		parts = append(parts, fmt.Sprintf("error=%q", errCode))
	}
	if desc != "" {
		parts = append(parts, fmt.Sprintf("error_description=%q", desc))
	}
	h := http.Header{}
	h.Set("WWW-Authenticate", "Bearer "+strings.Join(parts, ", "))
	return h
}

func (c *OAuthChecker) Check(r *http.Request) (*Identity, *Failure) {
	scheme, token, ok := strings.Cut(r.Header.Get("Authorization"), " ")
	if !ok || !strings.EqualFold(scheme, "Bearer") || token == "" {
		return nil, &Failure{
			Status: http.StatusUnauthorized,
			Reason: "no access token",
			Header: c.challenge("", "", c.Scopes),
			Quiet:  true,
		}
	}
	invalid := func(reason string) *Failure {
		return &Failure{
			Status: http.StatusUnauthorized,
			Reason: reason,
			Header: c.challenge("invalid_token", reason, c.Scopes),
		}
	}

	tu, ar, err := c.app.provider.IntrospectToken(r.Context(), strings.TrimSpace(token), fosite.AccessToken, &Session{})
	if err != nil {
		return nil, invalid("access token is invalid, expired or revoked")
	}
	if tu != fosite.AccessToken {
		return nil, invalid("not an access token")
	}
	if !slices.Contains(ar.GetGrantedAudience(), c.resource) {
		return nil, invalid("access token was issued for a different resource")
	}
	granted := ar.GetGrantedScopes()
	for _, s := range c.Require {
		if !granted.Has(s) {
			return nil, &Failure{
				Status: http.StatusForbidden,
				Reason: "missing scope " + s,
				Header: c.challenge("insufficient_scope", "missing scope "+s, c.Require),
			}
		}
	}
	sess, ok := ar.GetSession().(*Session)
	if !ok {
		return nil, invalid("unexpected session")
	}
	// Checked per request too, so adding groups to a service locks out grants
	// that were approved before.
	if !inAllowedGroup(c.Groups, sess.Groups) {
		return nil, &Failure{Status: http.StatusForbidden, Reason: sess.Username + " is not in a group allowed to use " + c.Host}
	}

	assertion, err := c.app.assertion(sess, ar, c.resource, time.Now())
	if err != nil {
		c.app.logger.Error("signing assertion", errField(err))
		return nil, &Failure{Status: http.StatusInternalServerError, Reason: "signing assertion: " + err.Error(), Quiet: true}
	}
	r.Header.Del("Authorization")
	c.app.shared.store.recordUse(ar.GetID(), clientIP(r))

	return &Identity{
		Subject:    sess.Subject,
		Username:   sess.Username,
		Email:      sess.Email,
		Name:       sess.Name,
		ClientID:   ar.GetClient().GetID(),
		ClientName: sess.ClientName,
		GrantID:    ar.GetID(),
		Scopes:     granted,
		Groups:     sess.Groups,
		Assertion:  assertion,
	}, nil
}

func (a *App) assertion(sess *Session, ar fosite.Requester, resource string, now time.Time) (string, error) {
	return a.shared.keys.sign(map[string]any{
		"iss":                a.Issuer,
		"aud":                resource,
		"sub":                sess.Subject,
		"preferred_username": sess.Username,
		"email":              sess.Email,
		"name":               sess.Name,
		"client_id":          ar.GetClient().GetID(),
		"client_name":        sess.ClientName,
		"scope":              strings.Join(ar.GetGrantedScopes(), " "),
		"groups":             append([]string{}, sess.Groups...),
		"grant_id":           ar.GetID(),
		"iat":                now.Unix(),
		"exp":                now.Add(time.Duration(a.AssertionLifetime)).Unix(),
		"jti":                randomHex(16),
	})
}

// UnmarshalCaddyfile parses the block after `bifrost_guard oauth`.
func (c *OAuthChecker) UnmarshalCaddyfile(d *caddyfile.Dispenser) error {
	d.Next()
	for d.NextBlock(0) {
		switch d.Val() {
		case "host":
			if !d.AllArgs(&c.Host) {
				return d.ArgErr()
			}
		case "scopes":
			c.Scopes = append(c.Scopes, d.RemainingArgs()...)
		case "require":
			c.Require = append(c.Require, d.RemainingArgs()...)
		case "groups":
			args := d.RemainingArgs()
			if len(args) == 0 {
				return d.ArgErr()
			}
			c.Groups = append(c.Groups, args...)
		case "any_group":
			if d.NextArg() {
				return d.ArgErr()
			}
			c.AnyGroup = true
		default:
			return d.Errf("oauth: unknown option %q", d.Val())
		}
	}
	return nil
}

var (
	_ caddy.Provisioner     = (*OAuthChecker)(nil)
	_ Checker               = (*OAuthChecker)(nil)
	_ Interceptor           = (*OAuthChecker)(nil)
	_ caddyfile.Unmarshaler = (*OAuthChecker)(nil)
)
