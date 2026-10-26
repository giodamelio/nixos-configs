package bifrost

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"sort"
	"strings"
	"sync"
	"time"
)

const (
	keyPrefix = storePrefix + "/keys"

	keyCurrent = "current"
	keyNext    = "next"
	keyRetired = "retired"
)

type keyRecord struct {
	Version int    `json:"version"`
	KID     string `json:"kid"`
	Seed    []byte `json:"seed"`
	State   string `json:"state"`
	// PromotedAt is when the key became current; rotation counts from it.
	PromotedAt time.Time `json:"promoted_at,omitzero"`
	// PublishUntil keeps a retired key in the JWKS until every assertion it
	// signed has expired.
	PublishUntil time.Time `json:"publish_until,omitzero"`
	CreatedAt    time.Time `json:"created_at"`

	private ed25519.PrivateKey
}

func (k *keyRecord) version() int { return k.Version }

// KeyRing signs assertions with self-generated Ed25519 keys kept in Caddy's
// storage. The JWKS always carries the next key too, so verifiers have it
// cached before it signs anything.
type KeyRing struct {
	store *Store

	mu   sync.Mutex
	keys map[string]*keyRecord
}

func newKeyRing(store *Store) *KeyRing {
	return &KeyRing{store: store, keys: make(map[string]*keyRecord)}
}

func (kr *KeyRing) load(ctx context.Context) error {
	kr.mu.Lock()
	defer kr.mu.Unlock()
	return loadAll(ctx, kr.store.storage, keyPrefix, func(k *keyRecord) {
		k.private = ed25519.NewKeyFromSeed(k.Seed)
		kr.keys[k.KID] = k
	})
}

func (kr *KeyRing) newKey(state string, now time.Time) *keyRecord {
	seed := make([]byte, ed25519.SeedSize)
	if _, err := rand.Read(seed); err != nil {
		panic(err)
	}
	k := &keyRecord{
		Version:   recordVersion,
		KID:       randomHex(8),
		Seed:      seed,
		State:     state,
		CreatedAt: now,
		private:   ed25519.NewKeyFromSeed(seed),
	}
	if state == keyCurrent {
		k.PromotedAt = now
	}
	return k
}

func (kr *KeyRing) save(ctx context.Context, k *keyRecord) error {
	b, err := json.Marshal(k)
	if err != nil {
		return err
	}
	return kr.store.storage.Store(ctx, key(keyPrefix, k.KID), b)
}

func (kr *KeyRing) byState(state string) *keyRecord {
	for _, k := range kr.keys {
		if k.State == state {
			return k
		}
	}
	return nil
}

// maintain makes sure a current and a next key exist, rotates once the
// current key is older than rotation, and drops retired keys nobody can
// still be verifying against.
func (kr *KeyRing) maintain(ctx context.Context, now time.Time, rotation, assertionLifetime time.Duration) error {
	kr.mu.Lock()
	defer kr.mu.Unlock()

	cur := kr.byState(keyCurrent)
	next := kr.byState(keyNext)

	if cur != nil && now.Sub(cur.PromotedAt) >= rotation {
		cur.State = keyRetired
		cur.PublishUntil = now.Add(assertionLifetime + time.Minute)
		if err := kr.save(ctx, cur); err != nil {
			return fmt.Errorf("retiring signing key: %w", err)
		}
		cur = nil
	}
	if cur == nil {
		if next != nil {
			next.State = keyCurrent
			next.PromotedAt = now
			cur, next = next, nil
		} else {
			cur = kr.newKey(keyCurrent, now)
			kr.keys[cur.KID] = cur
		}
		if err := kr.save(ctx, cur); err != nil {
			return fmt.Errorf("saving current signing key: %w", err)
		}
	}
	if next == nil {
		next = kr.newKey(keyNext, now)
		kr.keys[next.KID] = next
		if err := kr.save(ctx, next); err != nil {
			return fmt.Errorf("saving next signing key: %w", err)
		}
	}
	for kid, k := range kr.keys {
		if k.State == keyRetired && now.After(k.PublishUntil) {
			if err := kr.store.remove(ctx, key(keyPrefix, kid)); err != nil {
				return fmt.Errorf("removing retired signing key: %w", err)
			}
			delete(kr.keys, kid)
		}
	}
	return nil
}

func b64(b []byte) string {
	return base64.RawURLEncoding.EncodeToString(b)
}

// sign produces a compact EdDSA JWT.
func (kr *KeyRing) sign(claims map[string]any) (string, error) {
	kr.mu.Lock()
	cur := kr.byState(keyCurrent)
	kr.mu.Unlock()
	if cur == nil {
		return "", fmt.Errorf("no current signing key")
	}
	header, err := json.Marshal(map[string]string{"alg": "EdDSA", "typ": "JWT", "kid": cur.KID})
	if err != nil {
		return "", err
	}
	payload, err := json.Marshal(claims)
	if err != nil {
		return "", err
	}
	signingInput := b64(header) + "." + b64(payload)
	sig := ed25519.Sign(cur.private, []byte(signingInput))
	return signingInput + "." + b64(sig), nil
}

type jwk struct {
	Kty string `json:"kty"`
	Crv string `json:"crv"`
	X   string `json:"x"`
	Kid string `json:"kid"`
	Use string `json:"use"`
	Alg string `json:"alg"`
}

func (kr *KeyRing) jwks() map[string][]jwk {
	kr.mu.Lock()
	defer kr.mu.Unlock()
	keys := make([]jwk, 0, len(kr.keys))
	for _, k := range kr.keys {
		keys = append(keys, jwk{
			Kty: "OKP",
			Crv: "Ed25519",
			X:   b64(k.private.Public().(ed25519.PublicKey)),
			Kid: k.KID,
			Use: "sig",
			Alg: "EdDSA",
		})
	}
	sort.Slice(keys, func(i, j int) bool { return keys[i].Kid < keys[j].Kid })
	return map[string][]jwk{"keys": keys}
}

// verify checks an assertion against the published keys. Targets do the same
// with any JOSE library; bifrost uses it in tests.
func (kr *KeyRing) verify(token string, now time.Time) (map[string]any, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return nil, fmt.Errorf("malformed JWT")
	}
	hb, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return nil, err
	}
	var header struct {
		Alg string `json:"alg"`
		Kid string `json:"kid"`
	}
	if err := json.Unmarshal(hb, &header); err != nil {
		return nil, err
	}
	if header.Alg != "EdDSA" {
		return nil, fmt.Errorf("unexpected alg %q", header.Alg)
	}
	kr.mu.Lock()
	k, ok := kr.keys[header.Kid]
	kr.mu.Unlock()
	if !ok {
		return nil, fmt.Errorf("unknown kid %q", header.Kid)
	}
	sig, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil {
		return nil, err
	}
	if !ed25519.Verify(k.private.Public().(ed25519.PublicKey), []byte(parts[0]+"."+parts[1]), sig) {
		return nil, fmt.Errorf("bad signature")
	}
	pb, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return nil, err
	}
	var claims map[string]any
	if err := json.Unmarshal(pb, &claims); err != nil {
		return nil, err
	}
	exp, _ := claims["exp"].(float64)
	if now.Unix() >= int64(exp) {
		return nil, fmt.Errorf("assertion expired")
	}
	return claims, nil
}
