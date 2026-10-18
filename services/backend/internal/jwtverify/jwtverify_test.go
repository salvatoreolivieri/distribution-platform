package jwtverify

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const (
	issuer   = "https://auth.test"
	audience = "docbridge"
)

type issuerFixture struct {
	key     *ecdsa.PrivateKey
	kid     string
	fetches atomic.Int32
	server  *httptest.Server
}

func newIssuer(t *testing.T, kid string) *issuerFixture {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	f := &issuerFixture{key: key, kid: kid}
	f.server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		f.fetches.Add(1)
		_ = json.NewEncoder(w).Encode(map[string]any{"keys": []map[string]string{{
			"kty": "EC", "crv": "P-256", "kid": f.kid, "alg": "ES256", "use": "sig",
			"x": base64.RawURLEncoding.EncodeToString(f.key.X.FillBytes(make([]byte, 32))),
			"y": base64.RawURLEncoding.EncodeToString(f.key.Y.FillBytes(make([]byte, 32))),
		}}})
	}))
	t.Cleanup(f.server.Close)
	return f
}

func (f *issuerFixture) sign(t *testing.T, kid string, c jwt.MapClaims) string {
	t.Helper()
	tok := jwt.NewWithClaims(jwt.SigningMethodES256, c)
	tok.Header["kid"] = kid
	s, err := tok.SignedString(f.key)
	if err != nil {
		t.Fatal(err)
	}
	return s
}

func baseClaims(use string) jwt.MapClaims {
	return jwt.MapClaims{
		"iss": issuer, "aud": audience, "sub": "subject-1", "token_use": use,
		"exp": time.Now().Add(time.Minute).Unix(),
	}
}

func TestVerify(t *testing.T) {
	f := newIssuer(t, "v1")
	v := New(Config{JWKSURL: f.server.URL, Issuer: issuer, Audience: audience})

	t.Run("user token", func(t *testing.T) {
		p, err := v.Verify(context.Background(), f.sign(t, "v1", baseClaims("user")))
		if err != nil {
			t.Fatal(err)
		}
		if p.Kind != User || p.Subject != "subject-1" {
			t.Fatalf("principal = %+v", p)
		}
	})

	t.Run("service token with scopes", func(t *testing.T) {
		c := baseClaims("service")
		c["scope"] = "documents:ingest other"
		p, err := v.Verify(context.Background(), f.sign(t, "v1", c))
		if err != nil {
			t.Fatal(err)
		}
		if p.Kind != Service || !p.HasScope("documents:ingest") || p.HasScope("admin") {
			t.Fatalf("principal = %+v", p)
		}
	})

	cases := map[string]func(jwt.MapClaims){
		"expired":        func(c jwt.MapClaims) { c["exp"] = time.Now().Add(-time.Hour).Unix() },
		"wrong issuer":   func(c jwt.MapClaims) { c["iss"] = "https://evil.test" },
		"wrong audience": func(c jwt.MapClaims) { c["aud"] = "other" },
		"no token_use":   func(c jwt.MapClaims) { delete(c, "token_use") },
		"no exp":         func(c jwt.MapClaims) { delete(c, "exp") },
	}
	for name, mutate := range cases {
		t.Run(name, func(t *testing.T) {
			c := baseClaims("user")
			mutate(c)
			if _, err := v.Verify(context.Background(), f.sign(t, "v1", c)); !errors.Is(err, ErrInvalidToken) {
				t.Fatalf("err = %v, want ErrInvalidToken", err)
			}
		})
	}
}

func TestUnknownKidRefetchIsRateLimited(t *testing.T) {
	f := newIssuer(t, "v1")
	v := New(Config{JWKSURL: f.server.URL, Issuer: issuer, Audience: audience, RefetchInterval: time.Hour})

	if _, err := v.Verify(context.Background(), f.sign(t, "v1", baseClaims("user"))); err != nil {
		t.Fatal(err)
	}
	for range 3 {
		if _, err := v.Verify(context.Background(), f.sign(t, "v2", baseClaims("user"))); err == nil {
			t.Fatal("unknown kid accepted")
		}
	}
	if got := f.fetches.Load(); got != 1 {
		t.Fatalf("jwks fetched %d times, want 1", got)
	}
}

func TestRotationPicksUpNewKid(t *testing.T) {
	f := newIssuer(t, "v1")
	v := New(Config{JWKSURL: f.server.URL, Issuer: issuer, Audience: audience, RefetchInterval: time.Nanosecond})

	if _, err := v.Verify(context.Background(), f.sign(t, "v1", baseClaims("user"))); err != nil {
		t.Fatal(err)
	}
	f.kid = "v2"
	time.Sleep(time.Millisecond)
	if _, err := v.Verify(context.Background(), f.sign(t, "v2", baseClaims("user"))); err != nil {
		t.Fatalf("rotated key rejected: %v", err)
	}
}

func TestMiddleware(t *testing.T) {
	f := newIssuer(t, "v1")
	v := New(Config{JWKSURL: f.server.URL, Issuer: issuer, Audience: audience})
	ok := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusNoContent) })
	h := v.Middleware(RequireScope("documents:ingest", ok))

	svc := baseClaims("service")
	svc["scope"] = "documents:ingest"

	cases := []struct {
		name   string
		header string
		want   int
	}{
		{"no header", "", http.StatusUnauthorized},
		{"garbage", "Bearer nope", http.StatusUnauthorized},
		{"missing scope", "Bearer " + f.sign(t, "v1", baseClaims("user")), http.StatusForbidden},
		{"scoped service token", "Bearer " + f.sign(t, "v1", svc), http.StatusNoContent},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodPost, "/internal/v1/x", nil)
			if tc.header != "" {
				req.Header.Set("Authorization", tc.header)
			}
			rec := httptest.NewRecorder()
			h.ServeHTTP(rec, req)
			if rec.Code != tc.want {
				t.Fatalf("status = %d, want %d (%s)", rec.Code, tc.want, rec.Body)
			}
		})
	}
}
