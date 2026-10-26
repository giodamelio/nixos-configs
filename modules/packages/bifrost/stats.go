package bifrost

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"net/http"
	"sort"
	"sync"
	"time"

	"github.com/caddyserver/caddy/v2"
	"github.com/caddyserver/caddy/v2/caddyconfig/caddyfile"
	"github.com/caddyserver/caddy/v2/caddyconfig/httpcaddyfile"
	"github.com/caddyserver/caddy/v2/modules/caddyhttp"
	"github.com/caddyserver/certmagic"
)

const (
	statsKey       = "bifrost/stats.json"
	recentFailures = 100
	// otherHosts counts every host no service serves, so a scanner trying
	// random names under the wildcard can't grow the stats without bound.
	otherHosts = "(other)"
)

func init() {
	caddy.RegisterModule(Counter{})
	httpcaddyfile.RegisterHandlerDirective("bifrost_stats", parseCounter)
	httpcaddyfile.RegisterDirectiveOrder("bifrost_stats", httpcaddyfile.Before, "tracing")
}

// Counter counts every request into the site for the admin page, guarded or
// not. Hosts names every host the site serves; the rest count as otherHosts.
type Counter struct {
	Hosts []string `json:"hosts,omitempty"`

	stats *Stats
}

func (Counter) CaddyModule() caddy.ModuleInfo {
	return caddy.ModuleInfo{
		ID:  "http.handlers.bifrost_stats",
		New: func() caddy.Module { return new(Counter) },
	}
}

func (c *Counter) Provision(ctx caddy.Context) error {
	app, err := ctx.AppIfConfigured(appName)
	if err != nil {
		return fmt.Errorf("bifrost_stats needs the global bifrost block: %w", err)
	}
	c.stats = app.(*App).shared.stats
	c.stats.setHosts(c.Hosts)
	return nil
}

func (c *Counter) ServeHTTP(w http.ResponseWriter, r *http.Request, next caddyhttp.Handler) error {
	c.stats.recordRequest(requestHost(r))
	return next.ServeHTTP(w, r)
}

// UnmarshalCaddyfile parses `bifrost_stats { hosts <host...> }`.
func (c *Counter) UnmarshalCaddyfile(d *caddyfile.Dispenser) error {
	d.Next()
	for d.NextBlock(0) {
		switch d.Val() {
		case "hosts":
			c.Hosts = append(c.Hosts, d.RemainingArgs()...)
		default:
			return d.Errf("bifrost_stats: unknown option %q", d.Val())
		}
	}
	if len(c.Hosts) == 0 {
		return d.Err("bifrost_stats: hosts is required")
	}
	return nil
}

func parseCounter(h httpcaddyfile.Helper) (caddyhttp.MiddlewareHandler, error) {
	var c Counter
	err := c.UnmarshalCaddyfile(h.Dispenser)
	return &c, err
}

var (
	_ caddy.Provisioner           = (*Counter)(nil)
	_ caddyhttp.MiddlewareHandler = (*Counter)(nil)
	_ caddyfile.Unmarshaler       = (*Counter)(nil)
)

// ServiceStats counts traffic per public host. Persisted, so restarts don't
// reset the admin page.
type ServiceStats struct {
	Host        string    `json:"host"`
	Requests    int64     `json:"requests"`
	Failures    int64     `json:"failures"`
	LastRequest time.Time `json:"last_request"`
	LastFailure time.Time `json:"last_failure"`
}

// FailureEvent is one rejected request, kept in memory for the admin page.
type FailureEvent struct {
	Time     time.Time
	RemoteIP string
	Host     string
	Method   string
	Path     string
	Checker  string
	Reason   string
	Status   int
}

type statsFile struct {
	Version  int                      `json:"version"`
	Services map[string]*ServiceStats `json:"services"`
}

// Stats is shared across config reloads through the app's usage pool entry.
type Stats struct {
	mu       sync.Mutex
	services map[string]*ServiceStats
	failures []FailureEvent
	dirty    bool
	// hosts, once a Counter sets it, is the current config's hosts. Unset,
	// every host is counted under its own name.
	hosts map[string]bool
}

func newStats() *Stats {
	return &Stats{services: make(map[string]*ServiceStats)}
}

func (s *Stats) setHosts(hosts []string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.hosts = make(map[string]bool, len(hosts))
	for _, h := range hosts {
		s.hosts[h] = true
	}
	// Drops hosts no longer served, including any a scanner left in stats
	// persisted before hosts were bucketed.
	for h := range s.services {
		if !s.hosts[h] && h != otherHosts {
			delete(s.services, h)
			s.dirty = true
		}
	}
}

func (s *Stats) service(host string) *ServiceStats {
	if s.hosts != nil && !s.hosts[host] {
		host = otherHosts
	}
	svc, ok := s.services[host]
	if !ok {
		svc = &ServiceStats{Host: host}
		s.services[host] = svc
	}
	return svc
}

func (s *Stats) recordRequest(host string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	svc := s.service(host)
	svc.Requests++
	svc.LastRequest = time.Now()
	s.dirty = true
}

func (s *Stats) recordFailure(r *http.Request, checker string, f *Failure) {
	if f.Quiet {
		return
	}
	now := time.Now()
	host := requestHost(r)
	s.mu.Lock()
	defer s.mu.Unlock()
	svc := s.service(host)
	svc.Failures++
	svc.LastFailure = now
	s.dirty = true
	s.failures = append(s.failures, FailureEvent{
		Time:     now,
		RemoteIP: clientIP(r),
		Host:     host,
		Method:   r.Method,
		Path:     r.URL.Path,
		Checker:  checker,
		Reason:   f.Reason,
		Status:   f.Status,
	})
	if len(s.failures) > recentFailures {
		s.failures = s.failures[len(s.failures)-recentFailures:]
	}
}

func (s *Stats) snapshot() ([]ServiceStats, []FailureEvent) {
	s.mu.Lock()
	defer s.mu.Unlock()
	services := make([]ServiceStats, 0, len(s.services))
	for _, svc := range s.services {
		services = append(services, *svc)
	}
	for h := range s.hosts {
		if _, ok := s.services[h]; !ok {
			services = append(services, ServiceStats{Host: h})
		}
	}
	sort.Slice(services, func(i, j int) bool { return services[i].Host < services[j].Host })
	failures := make([]FailureEvent, len(s.failures))
	for i, f := range s.failures {
		failures[len(s.failures)-1-i] = f
	}
	return services, failures
}

func (s *Stats) load(ctx context.Context, storage certmagic.Storage) error {
	b, err := storage.Load(ctx, statsKey)
	if errors.Is(err, fs.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	var f statsFile
	if err := json.Unmarshal(b, &f); err != nil {
		return err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	for host, svc := range f.Services {
		s.services[host] = svc
	}
	return nil
}

func (s *Stats) flush(ctx context.Context, storage certmagic.Storage) error {
	s.mu.Lock()
	if !s.dirty {
		s.mu.Unlock()
		return nil
	}
	f := statsFile{Version: 1, Services: make(map[string]*ServiceStats, len(s.services))}
	for host, svc := range s.services {
		cp := *svc
		f.Services[host] = &cp
	}
	s.dirty = false
	s.mu.Unlock()

	b, err := json.Marshal(f)
	if err != nil {
		return err
	}
	return storage.Store(ctx, statsKey, b)
}
