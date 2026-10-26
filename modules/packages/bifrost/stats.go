package bifrost

import (
	"context"
	"encoding/json"
	"errors"
	"io/fs"
	"net/http"
	"sort"
	"sync"
	"time"

	"github.com/caddyserver/certmagic"
)

const (
	statsKey       = "bifrost/stats.json"
	recentFailures = 100
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
}

func newStats() *Stats {
	return &Stats{services: make(map[string]*ServiceStats)}
}

func (s *Stats) service(host string) *ServiceStats {
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
