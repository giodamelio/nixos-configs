package bifrost

import (
	"maps"
	"slices"
	"time"

	"github.com/ory/fosite"
)

// Session is what bifrost stores with every token: the Pocket ID identity
// that approved the grant, plus fosite's expiry bookkeeping. Groups are a
// snapshot from consent; they aren't refreshed.
type Session struct {
	Subject    string                         `json:"subject"`
	Username   string                         `json:"username"`
	Email      string                         `json:"email"`
	Name       string                         `json:"name"`
	ClientName string                         `json:"client_name"`
	Groups     []string                       `json:"groups,omitempty"`
	ExpiresAt  map[fosite.TokenType]time.Time `json:"expires_at"`
}

func (s *Session) SetExpiresAt(key fosite.TokenType, exp time.Time) {
	if s.ExpiresAt == nil {
		s.ExpiresAt = make(map[fosite.TokenType]time.Time)
	}
	s.ExpiresAt[key] = exp
}

func (s *Session) GetExpiresAt(key fosite.TokenType) time.Time {
	return s.ExpiresAt[key]
}

func (s *Session) GetUsername() string { return s.Username }

func (s *Session) GetSubject() string { return s.Subject }

func (s *Session) Clone() fosite.Session {
	if s == nil {
		return nil
	}
	cp := *s
	cp.Groups = slices.Clone(s.Groups)
	cp.ExpiresAt = maps.Clone(s.ExpiresAt)
	return &cp
}

var _ fosite.Session = (*Session)(nil)
