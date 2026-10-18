// Package jwtverify verifies the ES256 tokens issued by the auth service against its JWKS.
//
// Keys are cached and refetched when a token carries an unknown kid (key rotation), at most
// once per refetchInterval. Tokens are either user tokens (sub = user id) or service tokens
// (sub = client id), told apart by the token_use claim.
package jwtverify

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"net/http"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// Kind tells user tokens from service tokens.
type Kind string

const (
	User    Kind = "user"
	Service Kind = "service"
)

// Principal is the verified caller.
type Principal struct {
	Subject string
	Kind    Kind
	Scopes  []string
}

// HasScope reports whether the token grants scope.
func (p Principal) HasScope(scope string) bool { return slices.Contains(p.Scopes, scope) }

// Config configures a Verifier.
type Config struct {
	JWKSURL  string
	Issuer   string
	Audience string
	// HTTPClient defaults to a client with a 5 s timeout.
	HTTPClient *http.Client
	// RefetchInterval limits JWKS refetches on unknown kids. Defaults to 30 s.
	RefetchInterval time.Duration
}

// Verifier verifies tokens. It is safe for concurrent use.
type Verifier struct {
	cfg Config

	mu        sync.Mutex
	keys      map[string]*ecdsa.PublicKey
	fetchedAt time.Time
}

var (
	ErrInvalidToken = errors.New("invalid token")
	errUnknownKid   = errors.New("unknown kid")
)

// New returns a Verifier. Keys are fetched lazily on the first Verify.
func New(cfg Config) *Verifier {
	if cfg.HTTPClient == nil {
		cfg.HTTPClient = &http.Client{Timeout: 5 * time.Second}
	}
	if cfg.RefetchInterval == 0 {
		cfg.RefetchInterval = 30 * time.Second
	}
	return &Verifier{cfg: cfg, keys: map[string]*ecdsa.PublicKey{}}
}

type claims struct {
	jwt.RegisteredClaims
	Scope    string `json:"scope"`
	TokenUse string `json:"token_use"`
}

// Verify checks the signature, issuer, audience and expiry and returns the caller.
func (v *Verifier) Verify(ctx context.Context, raw string) (Principal, error) {
	var c claims
	_, err := jwt.ParseWithClaims(raw, &c, func(t *jwt.Token) (any, error) {
		kid, _ := t.Header["kid"].(string)
		return v.key(ctx, kid)
	},
		jwt.WithValidMethods([]string{"ES256"}),
		jwt.WithIssuer(v.cfg.Issuer),
		jwt.WithAudience(v.cfg.Audience),
		jwt.WithExpirationRequired(),
		jwt.WithLeeway(30*time.Second),
	)
	if err != nil {
		return Principal{}, fmt.Errorf("%w: %v", ErrInvalidToken, err)
	}

	kind := Kind(c.TokenUse)
	if kind != User && kind != Service {
		return Principal{}, fmt.Errorf("%w: token_use %q", ErrInvalidToken, c.TokenUse)
	}
	if c.Subject == "" {
		return Principal{}, fmt.Errorf("%w: missing sub", ErrInvalidToken)
	}
	return Principal{Subject: c.Subject, Kind: kind, Scopes: strings.Fields(c.Scope)}, nil
}

func (v *Verifier) key(ctx context.Context, kid string) (*ecdsa.PublicKey, error) {
	v.mu.Lock()
	defer v.mu.Unlock()

	if k, ok := v.keys[kid]; ok {
		return k, nil
	}
	if !v.fetchedAt.IsZero() && time.Since(v.fetchedAt) < v.cfg.RefetchInterval {
		return nil, errUnknownKid
	}
	keys, err := v.fetch(ctx)
	v.fetchedAt = time.Now()
	if err != nil {
		return nil, err
	}
	v.keys = keys
	if k, ok := keys[kid]; ok {
		return k, nil
	}
	return nil, errUnknownKid
}

type jwk struct {
	Kty string `json:"kty"`
	Crv string `json:"crv"`
	X   string `json:"x"`
	Y   string `json:"y"`
	Kid string `json:"kid"`
}

func (v *Verifier) fetch(ctx context.Context) (map[string]*ecdsa.PublicKey, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, v.cfg.JWKSURL, nil)
	if err != nil {
		return nil, err
	}
	resp, err := v.cfg.HTTPClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("fetch jwks: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("fetch jwks: status %d", resp.StatusCode)
	}

	var set struct {
		Keys []jwk `json:"keys"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&set); err != nil {
		return nil, fmt.Errorf("decode jwks: %w", err)
	}
	keys := make(map[string]*ecdsa.PublicKey, len(set.Keys))
	for _, k := range set.Keys {
		if k.Kty != "EC" || k.Crv != "P-256" {
			continue
		}
		x, errX := base64.RawURLEncoding.DecodeString(k.X)
		y, errY := base64.RawURLEncoding.DecodeString(k.Y)
		if errX != nil || errY != nil {
			continue
		}
		keys[k.Kid] = &ecdsa.PublicKey{Curve: elliptic.P256(), X: new(big.Int).SetBytes(x), Y: new(big.Int).SetBytes(y)}
	}
	return keys, nil
}
