package bifrost

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"embed"
	"encoding/base64"
	"encoding/json"
	"html/template"
	"net/http"
	"strings"
	"time"

	"go.uber.org/zap"
)

//go:embed templates/*.html
var templateFS embed.FS

var templates = template.Must(template.New("").Funcs(template.FuncMap{
	"ago":  ago,
	"join": strings.Join,
	"when": func(t time.Time) string {
		if t.IsZero() {
			return "never"
		}
		return t.UTC().Format("2006-01-02 15:04 UTC")
	},
}).ParseFS(templateFS, "templates/*.html"))

func ago(t time.Time) string {
	if t.IsZero() {
		return "never"
	}
	d := time.Since(t).Round(time.Second)
	switch {
	case d < time.Minute:
		return d.String() + " ago"
	case d < time.Hour:
		return d.Round(time.Minute).String() + " ago"
	case d < 48*time.Hour:
		return d.Round(time.Hour).String() + " ago"
	default:
		return t.UTC().Format("2006-01-02")
	}
}

func render(w http.ResponseWriter, status int, name string, data any) {
	var buf bytes.Buffer
	if err := templates.ExecuteTemplate(&buf, name, data); err != nil {
		http.Error(w, "template error: "+err.Error(), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Frame-Options", "DENY")
	w.Header().Set("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'")
	w.WriteHeader(status)
	_, _ = buf.WriteTo(w)
}

func renderError(w http.ResponseWriter, status int, title, detail string) {
	render(w, status, "error.html", map[string]string{"Title": title, "Detail": detail})
}

type consentView struct {
	FlowID       string
	CSRF         string
	RedirectHost string
	RedirectURI  string
	ClientName   string
	ClientID     string
	MetadataHost string
	Loopback     bool
	Resources    []string
	Scopes       []string
	User         *user
}

func (a *App) renderConsent(w http.ResponseWriter, f *flow) {
	client := f.ar.GetClient()
	v := consentView{
		FlowID:     f.id,
		CSRF:       f.csrf,
		ClientName: clientName(client),
		ClientID:   client.GetID(),
		Loopback:   allLoopback(client.GetRedirectURIs()),
		Resources:  f.resources,
		Scopes:     f.ar.GetRequestedScopes(),
		User:       f.user,
	}
	if u := f.ar.GetRedirectURI(); u != nil {
		v.RedirectHost = u.Host
		v.RedirectURI = u.String()
	}
	if bc, ok := client.(*bifrostClient); ok {
		v.MetadataHost = bc.MetadataHost()
	}
	render(w, http.StatusOK, "consent.html", v)
}

const adminCookie = "bifrost_admin"

type adminSession struct {
	Subject  string `json:"sub"`
	Username string `json:"user"`
	Expires  int64  `json:"exp"`
}

func (a *App) sign(purpose, payload string) string {
	mac := hmac.New(sha256.New, a.cookieKey)
	mac.Write([]byte(purpose + ":" + payload))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

func (a *App) setAdminSession(w http.ResponseWriter, u *user) {
	exp := time.Now().Add(8 * time.Hour)
	b, _ := json.Marshal(adminSession{Subject: u.Subject, Username: u.Username, Expires: exp.Unix()})
	payload := base64.RawURLEncoding.EncodeToString(b)
	http.SetCookie(w, &http.Cookie{
		Name:     adminCookie,
		Value:    payload + "." + a.sign("admin", payload),
		Path:     "/admin",
		Expires:  exp,
		HttpOnly: true,
		Secure:   true,
		SameSite: http.SameSiteStrictMode,
	})
}

// adminSession returns the session and its CSRF token, if the cookie is valid.
func (a *App) adminSession(r *http.Request) (*adminSession, string, bool) {
	c, err := r.Cookie(adminCookie)
	if err != nil {
		return nil, "", false
	}
	payload, sig, ok := strings.Cut(c.Value, ".")
	if !ok || !hmac.Equal([]byte(sig), []byte(a.sign("admin", payload))) {
		return nil, "", false
	}
	b, err := base64.RawURLEncoding.DecodeString(payload)
	if err != nil {
		return nil, "", false
	}
	var s adminSession
	if err := json.Unmarshal(b, &s); err != nil || time.Now().Unix() >= s.Expires {
		return nil, "", false
	}
	return &s, a.sign("csrf", payload), true
}

type clientView struct {
	ID           string
	Name         string
	Kind         string
	RedirectURIs []string
	AuthMethod   string
	CreatedAt    time.Time
	Deletable    bool
}

type adminView struct {
	User      string
	CSRF      string
	Grants    []Grant
	Clients   []clientView
	Services  []ServiceStats
	Failures  []FailureEvent
	Resources []string
}

func (a *App) handleAdmin(w http.ResponseWriter, r *http.Request) {
	sess, csrf, ok := a.adminSession(r)
	if !ok {
		if r.Method != http.MethodGet {
			http.Error(w, "not logged in", http.StatusUnauthorized)
			return
		}
		a.redirectToLogin(w, r, a.shared.flows.start(flowAdmin))
		return
	}

	if r.Method == http.MethodPost {
		if err := r.ParseForm(); err != nil || !hmac.Equal([]byte(r.PostForm.Get("csrf")), []byte(csrf)) {
			http.Error(w, "bad CSRF token", http.StatusForbidden)
			return
		}
		ctx := r.Context()
		switch r.URL.Path {
		case "/admin/revoke":
			id := r.PostForm.Get("grant")
			if err := a.shared.store.revokeGrant(ctx, id); err != nil {
				a.logger.Error("revoking grant", errField(err))
				renderError(w, http.StatusInternalServerError, "Revoking the grant failed", err.Error())
				return
			}
			a.logger.Info("grant revoked", zap.String("grant_id", id), zap.String("by", sess.Username))
		case "/admin/delete-client":
			id := r.PostForm.Get("client")
			if err := a.shared.store.deleteClient(ctx, id); err != nil {
				a.logger.Error("deleting client", errField(err))
				renderError(w, http.StatusInternalServerError, "Deleting the client failed", err.Error())
				return
			}
			a.logger.Info("client deleted", zap.String("client_id", id), zap.String("by", sess.Username))
		case "/admin/logout":
			http.SetCookie(w, &http.Cookie{Name: adminCookie, Value: "", Path: "/admin", MaxAge: -1, HttpOnly: true, Secure: true})
			renderError(w, http.StatusOK, "Logged out", "You can close this tab.")
			return
		default:
			http.NotFound(w, r)
			return
		}
		http.Redirect(w, r, "/admin", http.StatusSeeOther)
		return
	}

	if r.URL.Path != "/admin" {
		http.NotFound(w, r)
		return
	}
	services, failures := a.shared.stats.snapshot()
	view := adminView{
		User:      sess.Username,
		CSRF:      csrf,
		Grants:    a.shared.store.listGrants(),
		Services:  services,
		Failures:  failures,
		Resources: a.resources.uris(),
	}
	for _, c := range a.shared.store.listClients() {
		view.Clients = append(view.Clients, clientView{
			ID: c.ID, Name: c.Name, Kind: "registered", RedirectURIs: c.RedirectURIs,
			AuthMethod: c.TokenEndpointAuthMethod, CreatedAt: c.CreatedAt, Deletable: true,
		})
	}
	for _, d := range a.shared.docs.cached() {
		view.Clients = append(view.Clients, clientView{
			ID: d.ClientID, Name: d.ClientName, Kind: "metadata document", RedirectURIs: d.RedirectURIs,
			AuthMethod: authMethodNone,
		})
	}
	render(w, http.StatusOK, "admin.html", view)
}
