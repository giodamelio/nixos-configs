package bifrost

import (
	"fmt"
	"net/url"
	"slices"
	"sort"
	"strings"
	"sync"
)

// resourceRegistry holds the protected resources the oauth guards registered
// while the current config was provisioned. A config reload builds a new one.
type resourceRegistry struct {
	mu        sync.RWMutex
	resources map[string][]string
}

func newResourceRegistry() *resourceRegistry {
	return &resourceRegistry{resources: make(map[string][]string)}
}

func (rr *resourceRegistry) register(uri string, scopes []string) error {
	rr.mu.Lock()
	defer rr.mu.Unlock()
	if existing, ok := rr.resources[uri]; ok && !slices.Equal(existing, scopes) {
		return fmt.Errorf("resource %s is registered twice with different scopes", uri)
	}
	rr.resources[uri] = slices.Clone(scopes)
	return nil
}

func (rr *resourceRegistry) scopes(uri string) ([]string, bool) {
	rr.mu.RLock()
	defer rr.mu.RUnlock()
	s, ok := rr.resources[uri]
	return s, ok
}

// resolve maps a requested resource indicator to the registered resource
// that serves it. Clients may name a path under the subdomain, such as
// https://notes.external.gio.ninja/mcp; the grant is for the subdomain.
func (rr *resourceRegistry) resolve(raw string) (string, error) {
	c, err := canonicalResource(raw)
	if err != nil {
		return "", err
	}
	rr.mu.RLock()
	defer rr.mu.RUnlock()
	if _, ok := rr.resources[c]; ok {
		return c, nil
	}
	for uri := range rr.resources {
		if strings.HasPrefix(c, uri+"/") {
			return uri, nil
		}
	}
	return "", fmt.Errorf("resource %s is not served here", c)
}

func (rr *resourceRegistry) uris() []string {
	rr.mu.RLock()
	defer rr.mu.RUnlock()
	out := make([]string, 0, len(rr.resources))
	for uri := range rr.resources {
		out = append(out, uri)
	}
	sort.Strings(out)
	return out
}

func (rr *resourceRegistry) allScopes() []string {
	rr.mu.RLock()
	defer rr.mu.RUnlock()
	seen := map[string]bool{}
	var out []string
	for _, scopes := range rr.resources {
		for _, s := range scopes {
			if !seen[s] {
				seen[s] = true
				out = append(out, s)
			}
		}
	}
	sort.Strings(out)
	return out
}

// canonicalResource normalises an RFC 8707 resource indicator: lowercase
// scheme and host, no trailing slash, no query or fragment.
func canonicalResource(raw string) (string, error) {
	u, err := url.Parse(raw)
	if err != nil {
		return "", fmt.Errorf("resource %q: %w", raw, err)
	}
	if !u.IsAbs() || u.Host == "" {
		return "", fmt.Errorf("resource %q must be an absolute URI", raw)
	}
	if u.Fragment != "" || u.RawQuery != "" {
		return "", fmt.Errorf("resource %q must not have a query or fragment", raw)
	}
	u.Scheme = strings.ToLower(u.Scheme)
	u.Host = strings.ToLower(u.Host)
	u.Path = strings.TrimRight(u.Path, "/")
	u.RawPath = ""
	return u.String(), nil
}

func resourceForHost(host string) string {
	return "https://" + strings.ToLower(host)
}
