package bifrost

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/ory/fosite"
	"golang.org/x/crypto/bcrypt"
)

const (
	authMethodNone   = "none"
	authMethodBasic  = "client_secret_basic"
	authMethodPost   = "client_secret_post"
	maxClientDocSize = 64 << 10
)

// StoredClient is a client registered through RFC 7591 dynamic registration.
type StoredClient struct {
	Version                 int       `json:"version"`
	ID                      string    `json:"id"`
	SecretHash              []byte    `json:"secret_hash,omitempty"`
	Name                    string    `json:"name"`
	RedirectURIs            []string  `json:"redirect_uris"`
	TokenEndpointAuthMethod string    `json:"token_endpoint_auth_method"`
	ClientURI               string    `json:"client_uri,omitempty"`
	LogoURI                 string    `json:"logo_uri,omitempty"`
	CreatedAt               time.Time `json:"created_at"`
}

// bifrostClient adds a display name to fosite's client so consent and the
// admin page can show it.
type bifrostClient struct {
	fosite.DefaultOpenIDConnectClient
	name     string
	metadata string
}

func (c *bifrostClient) ClientName() string { return c.name }

// MetadataHost is the host serving a client ID metadata document, or empty
// for registered clients.
func (c *bifrostClient) MetadataHost() string { return c.metadata }

// clientRegistry builds fosite clients from registrations and client ID
// metadata documents. Every client may request every registered resource;
// what a grant actually gets is decided per authorization.
type clientRegistry struct {
	store     *Store
	resources *resourceRegistry
	docs      *docCache
}

func (cr *clientRegistry) GetClient(ctx context.Context, id string) (fosite.Client, error) {
	if isMetadataDocumentID(id) {
		doc, err := cr.docs.get(ctx, id)
		if err != nil {
			return nil, fosite.ErrInvalidClient.WithHintf("Fetching the client ID metadata document failed: %v", err).WithWrap(err)
		}
		u, _ := url.Parse(id)
		return cr.build(id, doc.ClientName, withLocalhostPort(ctx, doc.RedirectURIs), authMethodNone, nil, u.Hostname()), nil
	}
	c, ok := cr.store.storedClient(id)
	if !ok {
		return nil, fosite.ErrNotFound
	}
	return cr.build(c.ID, c.Name, withLocalhostPort(ctx, c.RedirectURIs), c.TokenEndpointAuthMethod, c.SecretHash, ""), nil
}

type requestedRedirectKey struct{}

func withRequestedRedirect(ctx context.Context, redirectURI string) context.Context {
	return context.WithValue(ctx, requestedRedirectKey{}, redirectURI)
}

// fosite applies RFC 8252's any-port rule only to loopback IP literals, but
// Claude Code registers http://localhost/callback and listens on a random
// port. This admits the authorize request's own redirect_uri when it differs
// from a registered http://localhost URI only by port.
func withLocalhostPort(ctx context.Context, registered []string) []string {
	raw, _ := ctx.Value(requestedRedirectKey{}).(string)
	requested, err := url.Parse(raw)
	if err != nil || requested.Scheme != "http" || requested.Hostname() != "localhost" {
		return registered
	}
	for _, r := range registered {
		u, err := url.Parse(r)
		if err == nil && u.Scheme == "http" && u.Hostname() == "localhost" &&
			u.Path == requested.Path && u.RawQuery == requested.RawQuery {
			return append(append([]string{}, registered...), raw)
		}
	}
	return registered
}

func (cr *clientRegistry) build(id, name string, redirects []string, method string, secretHash []byte, metadataHost string) *bifrostClient {
	return &bifrostClient{
		DefaultOpenIDConnectClient: fosite.DefaultOpenIDConnectClient{
			DefaultClient: &fosite.DefaultClient{
				ID:            id,
				Secret:        secretHash,
				RedirectURIs:  redirects,
				GrantTypes:    []string{"authorization_code", "refresh_token"},
				ResponseTypes: []string{"code"},
				Scopes:        cr.resources.allScopes(),
				Audience:      cr.resources.uris(),
				Public:        method == authMethodNone,
			},
			TokenEndpointAuthMethod: method,
		},
		name:     name,
		metadata: metadataHost,
	}
}

func (cr *clientRegistry) ClientAssertionJWTValid(context.Context, string) error {
	return nil
}

func (cr *clientRegistry) SetClientAssertionJWT(context.Context, string, time.Time) error {
	return nil
}

func isMetadataDocumentID(id string) bool {
	return strings.HasPrefix(id, "https://")
}

// secureRedirect is the MCP rule: HTTPS, or plain HTTP on loopback only.
func secureRedirect(raw string) error {
	u, err := url.Parse(raw)
	if err != nil {
		return fmt.Errorf("redirect URI %q: %w", raw, err)
	}
	if u.Fragment != "" {
		return fmt.Errorf("redirect URI %q has a fragment", raw)
	}
	if !fosite.IsRedirectURISecureStrict(context.Background(), u) {
		return fmt.Errorf("redirect URI %q must be https or loopback http", raw)
	}
	return nil
}

func allLoopback(uris []string) bool {
	if len(uris) == 0 {
		return false
	}
	for _, raw := range uris {
		u, err := url.Parse(raw)
		if err != nil || !fosite.IsLocalhost(u) {
			return false
		}
	}
	return true
}

func randomHex(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return hex.EncodeToString(b)
}

type registrationRequest struct {
	RedirectURIs            []string `json:"redirect_uris"`
	ClientName              string   `json:"client_name"`
	TokenEndpointAuthMethod string   `json:"token_endpoint_auth_method"`
	GrantTypes              []string `json:"grant_types"`
	ResponseTypes           []string `json:"response_types"`
	ClientURI               string   `json:"client_uri"`
	LogoURI                 string   `json:"logo_uri"`
	Scope                   string   `json:"scope"`
}

func registrationError(w http.ResponseWriter, code, desc string) {
	writeJSON(w, http.StatusBadRequest, map[string]string{"error": code, "error_description": desc})
}

// handleRegister implements RFC 7591 dynamic client registration.
func (a *App) handleRegister(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method_not_allowed"})
		return
	}
	mt, _, _ := mime.ParseMediaType(r.Header.Get("Content-Type"))
	if mt != "application/json" {
		registrationError(w, "invalid_client_metadata", "Content-Type must be application/json")
		return
	}
	var req registrationRequest
	if err := json.NewDecoder(io.LimitReader(r.Body, maxClientDocSize)).Decode(&req); err != nil {
		registrationError(w, "invalid_client_metadata", "body is not valid JSON")
		return
	}
	if len(req.RedirectURIs) == 0 {
		registrationError(w, "invalid_redirect_uri", "redirect_uris is required")
		return
	}
	for _, u := range req.RedirectURIs {
		if err := secureRedirect(u); err != nil {
			registrationError(w, "invalid_redirect_uri", err.Error())
			return
		}
	}
	method := req.TokenEndpointAuthMethod
	if method == "" {
		method = authMethodBasic
	}
	switch method {
	case authMethodNone, authMethodBasic, authMethodPost:
	default:
		registrationError(w, "invalid_client_metadata", "unsupported token_endpoint_auth_method "+method)
		return
	}
	for _, gt := range req.GrantTypes {
		if gt != "authorization_code" && gt != "refresh_token" {
			registrationError(w, "invalid_client_metadata", "unsupported grant type "+gt)
			return
		}
	}
	for _, rt := range req.ResponseTypes {
		if rt != "code" {
			registrationError(w, "invalid_client_metadata", "unsupported response type "+rt)
			return
		}
	}

	c := &StoredClient{
		ID:                      randomHex(16),
		Name:                    req.ClientName,
		RedirectURIs:            req.RedirectURIs,
		TokenEndpointAuthMethod: method,
		ClientURI:               req.ClientURI,
		LogoURI:                 req.LogoURI,
		CreatedAt:               time.Now().UTC(),
	}
	var secret string
	if method != authMethodNone {
		secret = randomHex(32)
		hash, err := bcrypt.GenerateFromPassword([]byte(secret), bcrypt.DefaultCost)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "server_error"})
			return
		}
		c.SecretHash = hash
	}
	if err := a.shared.store.saveClient(r.Context(), c); err != nil {
		a.logger.Error("saving registered client", errField(err))
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "server_error"})
		return
	}

	resp := map[string]any{
		"client_id":                  c.ID,
		"client_id_issued_at":        c.CreatedAt.Unix(),
		"client_name":                c.Name,
		"redirect_uris":              c.RedirectURIs,
		"token_endpoint_auth_method": c.TokenEndpointAuthMethod,
		"grant_types":                []string{"authorization_code", "refresh_token"},
		"response_types":             []string{"code"},
	}
	if c.ClientURI != "" {
		resp["client_uri"] = c.ClientURI
	}
	if c.LogoURI != "" {
		resp["logo_uri"] = c.LogoURI
	}
	if secret != "" {
		resp["client_secret"] = secret
		resp["client_secret_expires_at"] = 0
	}
	writeJSON(w, http.StatusCreated, resp)
}

// clientDocument is an OAuth client ID metadata document.
type clientDocument struct {
	ClientID                string   `json:"client_id"`
	ClientName              string   `json:"client_name"`
	ClientURI               string   `json:"client_uri"`
	LogoURI                 string   `json:"logo_uri"`
	RedirectURIs            []string `json:"redirect_uris"`
	TokenEndpointAuthMethod string   `json:"token_endpoint_auth_method"`
}

type cachedDoc struct {
	doc     *clientDocument
	expires time.Time
}

// docCache fetches client ID metadata documents and keeps them in memory for
// as long as their Cache-Control allows, within bounds.
type docCache struct {
	client *http.Client

	mu   sync.Mutex
	docs map[string]cachedDoc
}

func newDocCache(client *http.Client) *docCache {
	if client == nil {
		client = ssrfSafeClient()
	}
	return &docCache{client: client, docs: make(map[string]cachedDoc)}
}

func (dc *docCache) get(ctx context.Context, id string) (*clientDocument, error) {
	dc.mu.Lock()
	cached, ok := dc.docs[id]
	dc.mu.Unlock()
	if ok && time.Now().Before(cached.expires) {
		return cached.doc, nil
	}

	doc, ttl, err := dc.fetch(ctx, id)
	if err != nil {
		return nil, err
	}
	dc.mu.Lock()
	dc.docs[id] = cachedDoc{doc: doc, expires: time.Now().Add(ttl)}
	dc.mu.Unlock()
	return doc, nil
}

func (dc *docCache) cached() []clientDocument {
	dc.mu.Lock()
	defer dc.mu.Unlock()
	out := make([]clientDocument, 0, len(dc.docs))
	for _, c := range dc.docs {
		out = append(out, *c.doc)
	}
	return out
}

func (dc *docCache) fetch(ctx context.Context, id string) (*clientDocument, time.Duration, error) {
	u, err := url.Parse(id)
	if err != nil {
		return nil, 0, err
	}
	if u.Scheme != "https" || u.Path == "" || u.Path == "/" || u.Fragment != "" || u.User != nil {
		return nil, 0, fmt.Errorf("client_id must be an https URL with a path")
	}
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, id, nil)
	if err != nil {
		return nil, 0, err
	}
	req.Header.Set("Accept", "application/json")
	resp, err := dc.client.Do(req)
	if err != nil {
		return nil, 0, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, 0, fmt.Errorf("metadata document returned %s", resp.Status)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxClientDocSize+1))
	if err != nil {
		return nil, 0, err
	}
	if len(body) > maxClientDocSize {
		return nil, 0, fmt.Errorf("metadata document exceeds %d bytes", maxClientDocSize)
	}
	var doc clientDocument
	if err := json.Unmarshal(body, &doc); err != nil {
		return nil, 0, fmt.Errorf("metadata document is not valid JSON: %w", err)
	}
	if doc.ClientID != id {
		return nil, 0, fmt.Errorf("metadata document client_id %q does not match its URL", doc.ClientID)
	}
	if doc.ClientName == "" {
		return nil, 0, fmt.Errorf("metadata document has no client_name")
	}
	if len(doc.RedirectURIs) == 0 {
		return nil, 0, fmt.Errorf("metadata document has no redirect_uris")
	}
	for _, ru := range doc.RedirectURIs {
		if err := secureRedirect(ru); err != nil {
			return nil, 0, err
		}
	}
	if doc.TokenEndpointAuthMethod != "" && doc.TokenEndpointAuthMethod != authMethodNone {
		return nil, 0, fmt.Errorf("token_endpoint_auth_method %q is not supported for metadata document clients", doc.TokenEndpointAuthMethod)
	}
	return &doc, cacheTTL(resp.Header.Get("Cache-Control")), nil
}

func cacheTTL(cacheControl string) time.Duration {
	const (
		minTTL     = time.Minute
		maxTTL     = 24 * time.Hour
		defaultTTL = 5 * time.Minute
	)
	ttl := defaultTTL
	for _, part := range strings.Split(cacheControl, ",") {
		part = strings.TrimSpace(strings.ToLower(part))
		if part == "no-store" || part == "no-cache" {
			return minTTL
		}
		if v, ok := strings.CutPrefix(part, "max-age="); ok {
			if n, err := strconv.Atoi(v); err == nil {
				ttl = time.Duration(n) * time.Second
			}
		}
	}
	return min(max(ttl, minTTL), maxTTL)
}

// ssrfSafeClient refuses to connect anywhere but public addresses, and never
// follows redirects: a client ID URL is an untrusted input bifrost fetches.
func ssrfSafeClient() *http.Client {
	dialer := &net.Dialer{
		Timeout: 5 * time.Second,
		Control: func(_, address string, _ syscall.RawConn) error {
			host, _, err := net.SplitHostPort(address)
			if err != nil {
				return err
			}
			ip := net.ParseIP(host)
			if ip == nil || !publicIP(ip) {
				return fmt.Errorf("refusing to fetch from non-public address %s", host)
			}
			return nil
		},
	}
	transport := &http.Transport{
		DialContext:            dialer.DialContext,
		TLSHandshakeTimeout:    5 * time.Second,
		ResponseHeaderTimeout:  5 * time.Second,
		MaxResponseHeaderBytes: 16 << 10,
	}
	return &http.Client{
		Transport: transport,
		Timeout:   5 * time.Second,
		CheckRedirect: func(*http.Request, []*http.Request) error {
			return errors.New("metadata document redirects are not followed")
		},
	}
}

var cgnat = &net.IPNet{IP: net.IPv4(100, 64, 0, 0), Mask: net.CIDRMask(10, 32)}

func publicIP(ip net.IP) bool {
	return !(ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() || ip.IsLinkLocalMulticast() ||
		ip.IsInterfaceLocalMulticast() || ip.IsMulticast() || ip.IsUnspecified() || cgnat.Contains(ip))
}
