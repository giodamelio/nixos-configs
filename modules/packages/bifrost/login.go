package bifrost

import (
	"context"
	"fmt"
	"slices"
	"sync"
	"time"

	"github.com/coreos/go-oidc/v3/oidc"
	"github.com/ory/fosite"
	"golang.org/x/oauth2"
)

// login is bifrost's own OIDC client to Pocket ID. Discovery is lazy so a
// Pocket ID outage only affects logins, never webhook routes.
type login struct {
	cfg         LoginConfig
	secret      string
	redirectURL string

	mu       sync.Mutex
	verifier *oidc.IDTokenVerifier
	oauth    *oauth2.Config
}

func newLogin(cfg LoginConfig, redirectURL string) (*login, error) {
	if cfg.OIDCIssuer == "" || cfg.ClientID == "" {
		return nil, fmt.Errorf("login: oidc_issuer and client_id are required")
	}
	secret, err := readSecretFile(cfg.ClientSecretFile)
	if err != nil {
		return nil, fmt.Errorf("login: client secret: %w", err)
	}
	return &login{cfg: cfg, secret: string(secret), redirectURL: redirectURL}, nil
}

func (l *login) init(ctx context.Context) (*oauth2.Config, *oidc.IDTokenVerifier, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.oauth != nil {
		return l.oauth, l.verifier, nil
	}
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	provider, err := oidc.NewProvider(ctx, l.cfg.OIDCIssuer)
	if err != nil {
		return nil, nil, fmt.Errorf("discovering %s: %w", l.cfg.OIDCIssuer, err)
	}
	// groups is always requested: services can restrict by group even when
	// login itself is open to every account.
	scopes := []string{oidc.ScopeOpenID, "profile", "email", "groups"}
	l.oauth = &oauth2.Config{
		ClientID:     l.cfg.ClientID,
		ClientSecret: l.secret,
		Endpoint:     provider.Endpoint(),
		RedirectURL:  l.redirectURL,
		Scopes:       scopes,
	}
	l.verifier = provider.Verifier(&oidc.Config{ClientID: l.cfg.ClientID})
	return l.oauth, l.verifier, nil
}

// authURL always asks for a fresh login; bifrost enforces it again on the
// way back through auth_time.
func (l *login) authURL(ctx context.Context, f *flow) (string, error) {
	cfg, _, err := l.init(ctx)
	if err != nil {
		return "", err
	}
	return cfg.AuthCodeURL(f.id,
		oidc.Nonce(f.nonce),
		oauth2.S256ChallengeOption(f.verifier),
		oauth2.SetAuthURLParam("prompt", "login"),
		oauth2.SetAuthURLParam("max_age", fmt.Sprint(int(time.Duration(l.cfg.MaxAuthAge).Seconds()))),
	), nil
}

type user struct {
	Subject  string
	Username string
	Email    string
	Name     string
	Groups   []string
	AuthTime time.Time
}

func (l *login) exchange(ctx context.Context, f *flow, code string, now time.Time) (*user, error) {
	cfg, verifier, err := l.init(ctx)
	if err != nil {
		return nil, err
	}
	tok, err := cfg.Exchange(ctx, code, oauth2.VerifierOption(f.verifier))
	if err != nil {
		return nil, fmt.Errorf("exchanging the login code: %w", err)
	}
	rawID, ok := tok.Extra("id_token").(string)
	if !ok {
		return nil, fmt.Errorf("the login response has no id_token")
	}
	idt, err := verifier.Verify(ctx, rawID)
	if err != nil {
		return nil, fmt.Errorf("verifying the id_token: %w", err)
	}
	if idt.Nonce != f.nonce {
		return nil, fmt.Errorf("the id_token nonce does not match")
	}
	var claims struct {
		AuthTime          int64    `json:"auth_time"`
		Email             string   `json:"email"`
		Name              string   `json:"name"`
		PreferredUsername string   `json:"preferred_username"`
		Groups            []string `json:"groups"`
	}
	if err := idt.Claims(&claims); err != nil {
		return nil, fmt.Errorf("reading id_token claims: %w", err)
	}
	if claims.AuthTime == 0 {
		return nil, fmt.Errorf("the id_token has no auth_time, so a fresh login can't be confirmed")
	}
	authTime := time.Unix(claims.AuthTime, 0)
	if age := now.Sub(authTime); age > time.Duration(l.cfg.MaxAuthAge) {
		return nil, fmt.Errorf("the login is %s old; a fresh login is required", age.Round(time.Second))
	}
	if len(l.cfg.AllowedGroups) > 0 && !slices.ContainsFunc(claims.Groups, func(g string) bool {
		return slices.Contains(l.cfg.AllowedGroups, g)
	}) {
		return nil, fmt.Errorf("%s is not in an allowed group", idt.Subject)
	}
	username := claims.PreferredUsername
	if username == "" {
		username = idt.Subject
	}
	return &user{
		Subject:  idt.Subject,
		Username: username,
		Email:    claims.Email,
		Name:     claims.Name,
		Groups:   claims.Groups,
		AuthTime: authTime,
	}, nil
}

type flowKind int

const (
	flowAuthorize flowKind = iota
	flowAdmin
)

// flow is one browser round trip through Pocket ID: an authorization waiting
// for consent, or an admin login.
type flow struct {
	id       string
	kind     flowKind
	nonce    string
	verifier string
	csrf     string
	created  time.Time

	ar        fosite.AuthorizeRequester
	resources []string
	user      *user
}

const flowLifetime = 10 * time.Minute

type flowStore struct {
	mu    sync.Mutex
	flows map[string]*flow
}

func newFlowStore() *flowStore {
	return &flowStore{flows: make(map[string]*flow)}
}

func (fs *flowStore) start(kind flowKind) *flow {
	f := &flow{
		id:       randomHex(32),
		kind:     kind,
		nonce:    randomHex(16),
		verifier: oauth2.GenerateVerifier(),
		csrf:     randomHex(32),
		created:  time.Now(),
	}
	fs.mu.Lock()
	fs.flows[f.id] = f
	fs.mu.Unlock()
	return f
}

func (fs *flowStore) get(id string) (*flow, bool) {
	fs.mu.Lock()
	defer fs.mu.Unlock()
	f, ok := fs.flows[id]
	if !ok || time.Since(f.created) > flowLifetime {
		return nil, false
	}
	return f, true
}

func (fs *flowStore) finish(id string) {
	fs.mu.Lock()
	defer fs.mu.Unlock()
	delete(fs.flows, id)
}

func (fs *flowStore) sweep(now time.Time) {
	fs.mu.Lock()
	defer fs.mu.Unlock()
	for id, f := range fs.flows {
		if now.Sub(f.created) > flowLifetime {
			delete(fs.flows, id)
		}
	}
}
