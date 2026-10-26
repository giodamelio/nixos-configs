package bifrost

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/caddyserver/caddy/v2"
	"github.com/caddyserver/caddy/v2/caddyconfig"
	"github.com/caddyserver/caddy/v2/caddyconfig/caddyfile"
	"github.com/caddyserver/caddy/v2/caddyconfig/httpcaddyfile"
	"github.com/caddyserver/certmagic"
	"github.com/nats-io/nats.go"
	"github.com/ory/fosite"
	"github.com/ory/fosite/compose"
	"github.com/ory/fosite/handler/oauth2"
	"github.com/ory/fosite/handler/pkce"
	"go.uber.org/zap"
)

const appName = "bifrost"

func init() {
	caddy.RegisterModule(App{})
	httpcaddyfile.RegisterGlobalOption("bifrost", parseGlobalOption)
}

// LoginConfig is the upstream OIDC provider (Pocket ID) that approves grants.
type LoginConfig struct {
	OIDCIssuer       string         `json:"oidc_issuer,omitempty"`
	ClientID         string         `json:"client_id,omitempty"`
	ClientSecretFile string         `json:"client_secret_file,omitempty"`
	MaxAuthAge       caddy.Duration `json:"max_auth_age,omitempty"`
	AllowedGroups    []string       `json:"allowed_groups,omitempty"`
}

// App is the bifrost authorization server: fosite, the Pocket ID login, the
// resource registry, and the state shared across config reloads.
type App struct {
	Issuer               string         `json:"issuer,omitempty"`
	Login                LoginConfig    `json:"login"`
	TokenKeyFile         string         `json:"token_key_file,omitempty"`
	AccessTokenLifetime  caddy.Duration `json:"access_token_lifetime,omitempty"`
	RefreshTokenLifetime caddy.Duration `json:"refresh_token_lifetime,omitempty"`
	AssertionLifetime    caddy.Duration `json:"assertion_lifetime,omitempty"`
	SigningKeyRotation   caddy.Duration `json:"signing_key_rotation,omitempty"`
	NATS                 *NATSConfig    `json:"nats,omitempty"`

	shared      *shared
	poolKey     string
	natsConn    *natsConn
	natsPoolKey string
	resources   *resourceRegistry
	clients     *clientRegistry
	provider    fosite.OAuth2Provider
	login       *login
	cookieKey   []byte
	logger      *zap.Logger
}

func (App) CaddyModule() caddy.ModuleInfo {
	return caddy.ModuleInfo{
		ID:  appName,
		New: func() caddy.Module { return new(App) },
	}
}

const (
	defaultAccessLifetime    = 30 * time.Minute
	defaultRefreshLifetime   = 30 * 24 * time.Hour
	defaultAssertionLifetime = 2 * time.Minute
	defaultKeyRotation       = 30 * 24 * time.Hour
	defaultMaxAuthAge        = 5 * time.Minute
	codeLifespan             = 5 * time.Minute
)

func (a *App) Provision(ctx caddy.Context) error {
	return a.setup(ctx, ctx.Storage(), ctx.Logger())
}

// setup is Provision without the Caddy context, so tests can drive the app.
func (a *App) setup(ctx context.Context, storage certmagic.Storage, logger *zap.Logger) error {
	a.logger = logger
	if a.Issuer == "" {
		return fmt.Errorf("bifrost: issuer is required")
	}
	a.Issuer = strings.TrimRight(a.Issuer, "/")
	if !strings.HasPrefix(a.Issuer, "https://") {
		return fmt.Errorf("bifrost: issuer must be an https URL")
	}
	if a.AccessTokenLifetime == 0 {
		a.AccessTokenLifetime = caddy.Duration(defaultAccessLifetime)
	}
	if a.RefreshTokenLifetime == 0 {
		a.RefreshTokenLifetime = caddy.Duration(defaultRefreshLifetime)
	}
	if a.AssertionLifetime == 0 {
		a.AssertionLifetime = caddy.Duration(defaultAssertionLifetime)
	}
	if a.SigningKeyRotation == 0 {
		a.SigningKeyRotation = caddy.Duration(defaultKeyRotation)
	}
	if a.Login.MaxAuthAge == 0 {
		a.Login.MaxAuthAge = caddy.Duration(defaultMaxAuthAge)
	}

	tokenKey, err := readSecretFile(a.TokenKeyFile)
	if err != nil {
		return fmt.Errorf("bifrost: token key: %w", err)
	}
	if len(tokenKey) < 32 {
		return fmt.Errorf("bifrost: token key must be at least 32 bytes, got %d", len(tokenKey))
	}
	a.cookieKey = deriveKey(tokenKey, "bifrost cookies")

	login, err := newLogin(a.Login, a.Issuer+"/callback")
	if err != nil {
		return fmt.Errorf("bifrost: %w", err)
	}
	a.login = login

	a.poolKey = "bifrost:" + a.Issuer
	val, _, err := sharedPool.LoadOrNew(a.poolKey, func() (caddy.Destructor, error) {
		return newShared(ctx, storage, logger, time.Duration(a.SigningKeyRotation), time.Duration(a.AssertionLifetime))
	})
	if err != nil {
		return fmt.Errorf("bifrost: %w", err)
	}
	a.shared = val.(*shared)

	if a.NATS != nil {
		if a.NATS.URL == "" {
			a.NATS.URL = nats.DefaultURL
		}
		a.natsPoolKey = a.NATS.poolKey()
		conn, _, err := natsPool.LoadOrNew(a.natsPoolKey, func() (caddy.Destructor, error) {
			return a.NATS.connect(logger)
		})
		if err != nil {
			return fmt.Errorf("bifrost: %w", err)
		}
		a.natsConn = conn.(*natsConn)
	}

	a.resources = newResourceRegistry()
	a.clients = &clientRegistry{store: a.shared.store, resources: a.resources, docs: a.shared.docs}

	cfg := &fosite.Config{
		AccessTokenLifespan:            time.Duration(a.AccessTokenLifetime),
		RefreshTokenLifespan:           time.Duration(a.RefreshTokenLifetime),
		AuthorizeCodeLifespan:          codeLifespan,
		GlobalSecret:                   tokenKey,
		EnforcePKCE:                    true,
		EnablePKCEPlainChallengeMethod: false,
		ScopeStrategy:                  fosite.ExactScopeStrategy,
		AudienceMatchingStrategy:       fosite.DefaultAudienceMatchingStrategy,
		RedirectSecureChecker:          fosite.IsRedirectURISecureStrict,
		RefreshTokenScopes:             []string{},
		TokenURL:                       a.Issuer + "/token",
		AccessTokenIssuer:              a.Issuer,
	}
	a.provider = compose.Compose(cfg, &fositeStorage{Store: a.shared.store, clientRegistry: a.clients},
		&compose.CommonStrategy{CoreStrategy: compose.NewOAuth2HMACStrategy(cfg)},
		compose.OAuth2AuthorizeExplicitFactory,
		compose.OAuth2RefreshTokenGrantFactory,
		compose.OAuth2PKCEFactory,
		compose.OAuth2TokenIntrospectionFactory,
		compose.OAuth2TokenRevocationFactory,
	)
	return nil
}

func (a *App) Start() error { return nil }

func (a *App) Stop() error { return nil }

func (a *App) Cleanup() error {
	if a.natsPoolKey != "" {
		if _, err := natsPool.Delete(a.natsPoolKey); err != nil {
			return err
		}
	}
	if a.poolKey == "" {
		return nil
	}
	_, err := sharedPool.Delete(a.poolKey)
	return err
}

func (a *App) registerResource(uri string, scopes []string) error {
	return a.resources.register(uri, scopes)
}

func deriveKey(secret []byte, purpose string) []byte {
	mac := hmac.New(sha256.New, secret)
	mac.Write([]byte(purpose))
	return mac.Sum(nil)
}

func errField(err error) zap.Field { return zap.Error(err) }

// fositeStorage is everything fosite needs: the shared token store plus the
// client lookups of the current config.
type fositeStorage struct {
	*Store
	*clientRegistry
}

// compose.Compose takes storage as interface{} and type-asserts it per
// factory at runtime; these catch a fosite interface change at build time.
var (
	_ fosite.ClientManager          = (*fositeStorage)(nil)
	_ oauth2.CoreStorage            = (*fositeStorage)(nil)
	_ oauth2.TokenRevocationStorage = (*fositeStorage)(nil)
	_ pkce.PKCERequestStorage       = (*fositeStorage)(nil)
)

var sharedPool = caddy.NewUsagePool()

// shared is the state that outlives a config reload: Caddy provisions the new
// config before stopping the old one, and both use the same store.
type shared struct {
	store  *Store
	keys   *KeyRing
	stats  *Stats
	docs   *docCache
	flows  *flowStore
	logger *zap.Logger

	cancel context.CancelFunc
	done   sync.WaitGroup
}

func newShared(ctx context.Context, storage certmagic.Storage, logger *zap.Logger, rotation, assertionLifetime time.Duration) (*shared, error) {
	s := &shared{
		store:  newStore(storage),
		stats:  newStats(),
		docs:   newDocCache(nil),
		flows:  newFlowStore(),
		logger: logger,
	}
	s.keys = newKeyRing(s.store)
	if err := s.store.load(ctx); err != nil {
		return nil, err
	}
	if err := s.keys.load(ctx); err != nil {
		return nil, fmt.Errorf("loading signing keys: %w", err)
	}
	if err := s.keys.maintain(ctx, time.Now(), rotation, assertionLifetime); err != nil {
		return nil, err
	}
	if err := s.stats.load(ctx, storage); err != nil {
		return nil, fmt.Errorf("loading stats: %w", err)
	}

	bg, cancel := context.WithCancel(context.Background())
	s.cancel = cancel
	s.done.Add(1)
	go s.loop(bg, rotation, assertionLifetime)
	return s, nil
}

func (s *shared) loop(ctx context.Context, rotation, assertionLifetime time.Duration) {
	defer s.done.Done()
	flush := time.NewTicker(time.Minute)
	sweep := time.NewTicker(time.Hour)
	defer flush.Stop()
	defer sweep.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-flush.C:
			s.flush(ctx)
			if err := s.keys.maintain(ctx, time.Now(), rotation, assertionLifetime); err != nil {
				s.logger.Error("maintaining signing keys", errField(err))
			}
			s.flows.sweep(time.Now())
		case <-sweep.C:
			if err := s.store.sweep(ctx, time.Now(), codeLifespan); err != nil {
				s.logger.Error("sweeping expired tokens", errField(err))
			}
		}
	}
}

func (s *shared) flush(ctx context.Context) {
	if err := s.store.flushGrants(ctx); err != nil {
		s.logger.Error("flushing grant usage", errField(err))
	}
	if err := s.stats.flush(ctx, s.store.storage); err != nil {
		s.logger.Error("flushing stats", errField(err))
	}
}

func (s *shared) Destruct() error {
	s.cancel()
	s.done.Wait()
	s.flush(context.Background())
	return nil
}

// parseGlobalOption parses the global `bifrost { ... }` block.
func parseGlobalOption(d *caddyfile.Dispenser, _ any) (any, error) {
	var a App
	d.Next()
	for d.NextBlock(0) {
		switch d.Val() {
		case "issuer":
			if !d.AllArgs(&a.Issuer) {
				return nil, d.ArgErr()
			}
		case "token_key_file":
			if !d.AllArgs(&a.TokenKeyFile) {
				return nil, d.ArgErr()
			}
		case "access_token_lifetime", "refresh_token_lifetime", "assertion_lifetime", "signing_key_rotation":
			name := d.Val()
			dur, err := durationArg(d)
			if err != nil {
				return nil, err
			}
			switch name {
			case "access_token_lifetime":
				a.AccessTokenLifetime = dur
			case "refresh_token_lifetime":
				a.RefreshTokenLifetime = dur
			case "assertion_lifetime":
				a.AssertionLifetime = dur
			case "signing_key_rotation":
				a.SigningKeyRotation = dur
			}
		case "nats":
			a.NATS = &NATSConfig{}
			for nesting := d.Nesting(); d.NextBlock(nesting); {
				var dst *string
				switch d.Val() {
				case "url":
					dst = &a.NATS.URL
				case "creds_file":
					dst = &a.NATS.CredsFile
				case "token_file":
					dst = &a.NATS.TokenFile
				default:
					return nil, d.Errf("bifrost nats: unknown option %q", d.Val())
				}
				if !d.AllArgs(dst) {
					return nil, d.ArgErr()
				}
			}
		case "login":
			for nesting := d.Nesting(); d.NextBlock(nesting); {
				switch d.Val() {
				case "oidc_issuer":
					if !d.AllArgs(&a.Login.OIDCIssuer) {
						return nil, d.ArgErr()
					}
				case "client_id":
					if !d.AllArgs(&a.Login.ClientID) {
						return nil, d.ArgErr()
					}
				case "client_secret_file":
					if !d.AllArgs(&a.Login.ClientSecretFile) {
						return nil, d.ArgErr()
					}
				case "max_auth_age":
					dur, err := durationArg(d)
					if err != nil {
						return nil, err
					}
					a.Login.MaxAuthAge = dur
				case "allowed_groups":
					a.Login.AllowedGroups = append(a.Login.AllowedGroups, d.RemainingArgs()...)
				default:
					return nil, d.Errf("bifrost login: unknown option %q", d.Val())
				}
			}
		default:
			return nil, d.Errf("bifrost: unknown option %q", d.Val())
		}
	}
	return httpcaddyfile.App{Name: appName, Value: caddyconfig.JSON(a, nil)}, nil
}

func durationArg(d *caddyfile.Dispenser) (caddy.Duration, error) {
	if !d.NextArg() {
		return 0, d.ArgErr()
	}
	dur, err := caddy.ParseDuration(d.Val())
	if err != nil {
		return 0, d.Errf("%s: %v", d.Val(), err)
	}
	return caddy.Duration(dur), nil
}

var (
	_ caddy.App          = (*App)(nil)
	_ caddy.Provisioner  = (*App)(nil)
	_ caddy.CleanerUpper = (*App)(nil)
)
