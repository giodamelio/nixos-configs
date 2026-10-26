package bifrost

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"net/url"
	"path"
	"sort"
	"sync"
	"time"

	"github.com/caddyserver/certmagic"
	"github.com/ory/fosite"
)

const (
	storePrefix   = "bifrost"
	accessPrefix  = storePrefix + "/access"
	refreshPrefix = storePrefix + "/refresh"
	grantPrefix   = storePrefix + "/grants"
	clientPrefix  = storePrefix + "/clients"
	recordVersion = 1
)

// clientSnapshot is the part of a client a stored token needs. Tokens carry
// it so introspection never has to re-fetch a client metadata document.
type clientSnapshot struct {
	ID            string   `json:"id"`
	Name          string   `json:"name"`
	Public        bool     `json:"public"`
	RedirectURIs  []string `json:"redirect_uris"`
	GrantTypes    []string `json:"grant_types"`
	ResponseTypes []string `json:"response_types"`
	Scopes        []string `json:"scopes"`
	Audience      []string `json:"audience"`
}

type namedClient interface {
	ClientName() string
}

func snapshotClient(c fosite.Client) clientSnapshot {
	s := clientSnapshot{
		ID:            c.GetID(),
		Public:        c.IsPublic(),
		RedirectURIs:  c.GetRedirectURIs(),
		GrantTypes:    c.GetGrantTypes(),
		ResponseTypes: c.GetResponseTypes(),
		Scopes:        c.GetScopes(),
		Audience:      c.GetAudience(),
	}
	if n, ok := c.(namedClient); ok {
		s.Name = n.ClientName()
	}
	return s
}

func (s clientSnapshot) client() fosite.Client {
	return &bifrostClient{
		DefaultOpenIDConnectClient: fosite.DefaultOpenIDConnectClient{
			DefaultClient: &fosite.DefaultClient{
				ID:            s.ID,
				RedirectURIs:  s.RedirectURIs,
				GrantTypes:    s.GrantTypes,
				ResponseTypes: s.ResponseTypes,
				Scopes:        s.Scopes,
				Audience:      s.Audience,
				Public:        s.Public,
			},
		},
		name: s.Name,
	}
}

type storedRequest struct {
	ID                string         `json:"id"`
	RequestedAt       time.Time      `json:"requested_at"`
	Client            clientSnapshot `json:"client"`
	RequestedScope    []string       `json:"requested_scope"`
	GrantedScope      []string       `json:"granted_scope"`
	RequestedAudience []string       `json:"requested_audience"`
	GrantedAudience   []string       `json:"granted_audience"`
	Form              url.Values     `json:"form"`
	Session           *Session       `json:"session"`
}

func toStored(req fosite.Requester) (storedRequest, error) {
	sess, ok := req.GetSession().(*Session)
	if !ok {
		return storedRequest{}, fmt.Errorf("unexpected session type %T", req.GetSession())
	}
	return storedRequest{
		ID:                req.GetID(),
		RequestedAt:       req.GetRequestedAt(),
		Client:            snapshotClient(req.GetClient()),
		RequestedScope:    req.GetRequestedScopes(),
		GrantedScope:      req.GetGrantedScopes(),
		RequestedAudience: req.GetRequestedAudience(),
		GrantedAudience:   req.GetGrantedAudience(),
		Form:              req.GetRequestForm(),
		Session:           sess.Clone().(*Session),
	}, nil
}

func (s storedRequest) requester() fosite.Requester {
	form := url.Values{}
	for k, v := range s.Form {
		form[k] = append([]string(nil), v...)
	}
	return &fosite.Request{
		ID:                s.ID,
		RequestedAt:       s.RequestedAt,
		Client:            s.Client.client(),
		RequestedScope:    fosite.Arguments(s.RequestedScope),
		GrantedScope:      fosite.Arguments(s.GrantedScope),
		RequestedAudience: fosite.Arguments(s.RequestedAudience),
		GrantedAudience:   fosite.Arguments(s.GrantedAudience),
		Form:              form,
		Session:           s.Session.Clone(),
	}
}

type tokenRecord struct {
	Version   int           `json:"version"`
	Signature string        `json:"signature"`
	Active    bool          `json:"active"`
	ExpiresAt time.Time     `json:"expires_at"`
	Request   storedRequest `json:"request"`
}

// Grant is one approved authorization: one client, one user, its resources.
// Its ID is the fosite request ID that every token from it carries.
type Grant struct {
	Version      int       `json:"version"`
	ID           string    `json:"id"`
	Subject      string    `json:"subject"`
	Username     string    `json:"username"`
	Email        string    `json:"email"`
	ClientID     string    `json:"client_id"`
	ClientName   string    `json:"client_name"`
	RedirectHost string    `json:"redirect_host"`
	Audience     []string  `json:"audience"`
	Scopes       []string  `json:"scopes"`
	Groups       []string  `json:"groups,omitempty"`
	CreatedAt    time.Time `json:"created_at"`
	LastUsed     time.Time `json:"last_used"`
	LastIP       string    `json:"last_ip"`
	Requests     int64     `json:"requests"`
}

type codeEntry struct {
	req     fosite.Requester
	active  bool
	expires time.Time
}

// Store keeps tokens, grants and registered clients in Caddy's storage, with
// everything mirrored in memory so lookups never touch disk. Authorization
// codes and PKCE state are memory-only: they live minutes.
type Store struct {
	storage certmagic.Storage

	mu          sync.Mutex
	codes       map[string]*codeEntry
	pkce        map[string]fosite.Requester
	access      map[string]*tokenRecord
	refresh     map[string]*tokenRecord
	grants      map[string]*Grant
	clients     map[string]*StoredClient
	dirtyGrants map[string]bool
}

func newStore(storage certmagic.Storage) *Store {
	return &Store{
		storage:     storage,
		codes:       make(map[string]*codeEntry),
		pkce:        make(map[string]fosite.Requester),
		access:      make(map[string]*tokenRecord),
		refresh:     make(map[string]*tokenRecord),
		grants:      make(map[string]*Grant),
		clients:     make(map[string]*StoredClient),
		dirtyGrants: make(map[string]bool),
	}
}

func (s *Store) load(ctx context.Context) error {
	if err := loadAll(ctx, s.storage, accessPrefix, func(r *tokenRecord) { s.access[r.Signature] = r }); err != nil {
		return fmt.Errorf("loading access tokens: %w", err)
	}
	if err := loadAll(ctx, s.storage, refreshPrefix, func(r *tokenRecord) { s.refresh[r.Signature] = r }); err != nil {
		return fmt.Errorf("loading refresh tokens: %w", err)
	}
	if err := loadAll(ctx, s.storage, grantPrefix, func(g *Grant) { s.grants[g.ID] = g }); err != nil {
		return fmt.Errorf("loading grants: %w", err)
	}
	if err := loadAll(ctx, s.storage, clientPrefix, func(c *StoredClient) { s.clients[c.ID] = c }); err != nil {
		return fmt.Errorf("loading clients: %w", err)
	}
	return nil
}

type versioned interface {
	version() int
}

func (r *tokenRecord) version() int  { return r.Version }
func (g *Grant) version() int        { return g.Version }
func (c *StoredClient) version() int { return c.Version }

func loadAll[T any, P interface {
	*T
	versioned
}](ctx context.Context, storage certmagic.Storage, prefix string, add func(P)) error {
	keys, err := storage.List(ctx, prefix, false)
	if errors.Is(err, fs.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	for _, key := range keys {
		b, err := storage.Load(ctx, key)
		if err != nil {
			return fmt.Errorf("%s: %w", key, err)
		}
		v := P(new(T))
		if err := json.Unmarshal(b, v); err != nil {
			return fmt.Errorf("%s: %w", key, err)
		}
		if v.version() != recordVersion {
			return fmt.Errorf("%s: unsupported record version %d", key, v.version())
		}
		add(v)
	}
	return nil
}

func (s *Store) put(ctx context.Context, key string, v any) error {
	b, err := json.Marshal(v)
	if err != nil {
		return err
	}
	return s.storage.Store(ctx, key, b)
}

func (s *Store) remove(ctx context.Context, key string) error {
	err := s.storage.Delete(ctx, key)
	if errors.Is(err, fs.ErrNotExist) {
		return nil
	}
	return err
}

func key(prefix, id string) string {
	return path.Join(prefix, url.PathEscape(id))
}

func (s *Store) CreateAuthorizeCodeSession(_ context.Context, code string, req fosite.Requester) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.codes[code] = &codeEntry{req: req, active: true, expires: time.Now().Add(time.Hour)}
	return nil
}

func (s *Store) GetAuthorizeCodeSession(_ context.Context, code string, _ fosite.Session) (fosite.Requester, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	e, ok := s.codes[code]
	if !ok {
		return nil, fosite.ErrNotFound
	}
	if !e.active {
		return e.req, fosite.ErrInvalidatedAuthorizeCode
	}
	return e.req, nil
}

func (s *Store) InvalidateAuthorizeCodeSession(_ context.Context, code string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	e, ok := s.codes[code]
	if !ok {
		return fosite.ErrNotFound
	}
	e.active = false
	return nil
}

func (s *Store) CreatePKCERequestSession(_ context.Context, sig string, req fosite.Requester) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.pkce[sig] = req
	return nil
}

func (s *Store) GetPKCERequestSession(_ context.Context, sig string, _ fosite.Session) (fosite.Requester, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	req, ok := s.pkce[sig]
	if !ok {
		return nil, fosite.ErrNotFound
	}
	return req, nil
}

func (s *Store) DeletePKCERequestSession(_ context.Context, sig string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.pkce, sig)
	return nil
}

func (s *Store) CreateAccessTokenSession(ctx context.Context, sig string, req fosite.Requester) error {
	sr, err := toStored(req)
	if err != nil {
		return err
	}
	rec := &tokenRecord{
		Version:   recordVersion,
		Signature: sig,
		Active:    true,
		ExpiresAt: sr.Session.GetExpiresAt(fosite.AccessToken),
		Request:   sr,
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.put(ctx, key(accessPrefix, sig), rec); err != nil {
		return err
	}
	s.access[sig] = rec
	return nil
}

func (s *Store) GetAccessTokenSession(_ context.Context, sig string, _ fosite.Session) (fosite.Requester, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	rec, ok := s.access[sig]
	if !ok {
		return nil, fosite.ErrNotFound
	}
	return rec.Request.requester(), nil
}

func (s *Store) DeleteAccessTokenSession(ctx context.Context, sig string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.deleteAccessLocked(ctx, sig)
}

func (s *Store) deleteAccessLocked(ctx context.Context, sig string) error {
	if err := s.remove(ctx, key(accessPrefix, sig)); err != nil {
		return err
	}
	delete(s.access, sig)
	return nil
}

func (s *Store) CreateRefreshTokenSession(ctx context.Context, sig string, req fosite.Requester) error {
	sr, err := toStored(req)
	if err != nil {
		return err
	}
	rec := &tokenRecord{
		Version:   recordVersion,
		Signature: sig,
		Active:    true,
		ExpiresAt: sr.Session.GetExpiresAt(fosite.RefreshToken),
		Request:   sr,
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.put(ctx, key(refreshPrefix, sig), rec); err != nil {
		return err
	}
	s.refresh[sig] = rec
	return nil
}

func (s *Store) GetRefreshTokenSession(_ context.Context, sig string, _ fosite.Session) (fosite.Requester, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	rec, ok := s.refresh[sig]
	if !ok {
		return nil, fosite.ErrNotFound
	}
	if !rec.Active {
		return rec.Request.requester(), fosite.ErrInactiveToken
	}
	return rec.Request.requester(), nil
}

func (s *Store) DeleteRefreshTokenSession(ctx context.Context, sig string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.deleteRefreshLocked(ctx, sig)
}

func (s *Store) deleteRefreshLocked(ctx context.Context, sig string) error {
	if err := s.remove(ctx, key(refreshPrefix, sig)); err != nil {
		return err
	}
	delete(s.refresh, sig)
	return nil
}

// RevokeRefreshTokenMaybeGracePeriod is fosite's rotation hook. There is no
// grace period: the old token stays, inactive, so reusing it is detected.
func (s *Store) RevokeRefreshTokenMaybeGracePeriod(ctx context.Context, requestID, _ string) error {
	return s.RevokeRefreshToken(ctx, requestID)
}

func (s *Store) RevokeRefreshToken(ctx context.Context, requestID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.deactivateRefreshLocked(ctx, requestID)
}

func (s *Store) RevokeAccessToken(ctx context.Context, requestID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.deleteAccessForLocked(ctx, requestID)
}

func (s *Store) deactivateRefreshLocked(ctx context.Context, requestID string) error {
	for sig, rec := range s.refresh {
		if rec.Request.ID != requestID || !rec.Active {
			continue
		}
		cp := *rec
		cp.Active = false
		if err := s.put(ctx, key(refreshPrefix, sig), &cp); err != nil {
			return err
		}
		s.refresh[sig] = &cp
	}
	return nil
}

func (s *Store) deleteAccessForLocked(ctx context.Context, requestID string) error {
	for sig, rec := range s.access {
		if rec.Request.ID == requestID {
			if err := s.deleteAccessLocked(ctx, sig); err != nil {
				return err
			}
		}
	}
	return nil
}

func (s *Store) createGrant(ctx context.Context, g *Grant) error {
	g.Version = recordVersion
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.put(ctx, key(grantPrefix, g.ID), g); err != nil {
		return err
	}
	s.grants[g.ID] = g
	return nil
}

// revokeGrant deletes the grant and every token issued under it.
func (s *Store) revokeGrant(ctx context.Context, id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.revokeGrantLocked(ctx, id)
}

func (s *Store) revokeGrantLocked(ctx context.Context, id string) error {
	if err := s.deleteAccessForLocked(ctx, id); err != nil {
		return err
	}
	for sig, rec := range s.refresh {
		if rec.Request.ID == id {
			if err := s.deleteRefreshLocked(ctx, sig); err != nil {
				return err
			}
		}
	}
	if err := s.remove(ctx, key(grantPrefix, id)); err != nil {
		return err
	}
	delete(s.grants, id)
	delete(s.dirtyGrants, id)
	return nil
}

func (s *Store) grantExists(id string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	_, ok := s.grants[id]
	return ok
}

func (s *Store) recordUse(id, ip string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	g, ok := s.grants[id]
	if !ok {
		return
	}
	g.LastUsed = time.Now()
	g.LastIP = ip
	g.Requests++
	s.dirtyGrants[id] = true
}

func (s *Store) listGrants() []Grant {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([]Grant, 0, len(s.grants))
	for _, g := range s.grants {
		out = append(out, *g)
	}
	sort.Slice(out, func(i, j int) bool {
		a, b := out[i], out[j]
		if !a.LastUsed.Equal(b.LastUsed) {
			return a.LastUsed.After(b.LastUsed)
		}
		return a.CreatedAt.After(b.CreatedAt)
	})
	return out
}

func (s *Store) flushGrants(ctx context.Context) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	for id := range s.dirtyGrants {
		if g, ok := s.grants[id]; ok {
			if err := s.put(ctx, key(grantPrefix, id), g); err != nil {
				return err
			}
		}
		delete(s.dirtyGrants, id)
	}
	return nil
}

// sweep drops expired tokens, and grants with nothing left under them once
// their authorization code could no longer be redeemed.
func (s *Store) sweep(ctx context.Context, now time.Time, codeLifespan time.Duration) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	for code, e := range s.codes {
		if now.After(e.expires) {
			delete(s.codes, code)
		}
	}
	for sig, req := range s.pkce {
		if now.Sub(req.GetRequestedAt()) > time.Hour {
			delete(s.pkce, sig)
		}
	}
	for sig, rec := range s.access {
		if now.After(rec.ExpiresAt) {
			if err := s.deleteAccessLocked(ctx, sig); err != nil {
				return err
			}
		}
	}
	for sig, rec := range s.refresh {
		if !rec.ExpiresAt.IsZero() && now.After(rec.ExpiresAt) {
			if err := s.deleteRefreshLocked(ctx, sig); err != nil {
				return err
			}
		}
	}
	live := make(map[string]bool)
	for _, rec := range s.access {
		live[rec.Request.ID] = true
	}
	for _, rec := range s.refresh {
		if rec.Active {
			live[rec.Request.ID] = true
		}
	}
	for id, g := range s.grants {
		if !live[id] && now.Sub(g.CreatedAt) > codeLifespan {
			if err := s.revokeGrantLocked(ctx, id); err != nil {
				return err
			}
		}
	}
	return nil
}

func (s *Store) saveClient(ctx context.Context, c *StoredClient) error {
	c.Version = recordVersion
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.put(ctx, key(clientPrefix, c.ID), c); err != nil {
		return err
	}
	s.clients[c.ID] = c
	return nil
}

func (s *Store) storedClient(id string) (*StoredClient, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	c, ok := s.clients[id]
	return c, ok
}

func (s *Store) listClients() []StoredClient {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([]StoredClient, 0, len(s.clients))
	for _, c := range s.clients {
		out = append(out, *c)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].CreatedAt.After(out[j].CreatedAt) })
	return out
}

// deleteClient removes a registered client and revokes every grant it holds.
func (s *Store) deleteClient(ctx context.Context, id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	for gid, g := range s.grants {
		if g.ClientID == id {
			if err := s.revokeGrantLocked(ctx, gid); err != nil {
				return err
			}
		}
	}
	if err := s.remove(ctx, key(clientPrefix, id)); err != nil {
		return err
	}
	delete(s.clients, id)
	return nil
}
