package jwtverify

import (
	"context"
	"net/http"
	"strings"

	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/envelope"
)

type ctxKey struct{}

// FromContext returns the Principal set by Middleware.
func FromContext(ctx context.Context) (Principal, bool) {
	p, ok := ctx.Value(ctxKey{}).(Principal)
	return p, ok
}

// WithPrincipal returns ctx carrying p. Useful in tests.
func WithPrincipal(ctx context.Context, p Principal) context.Context {
	return context.WithValue(ctx, ctxKey{}, p)
}

// Middleware rejects requests without a valid bearer token with a 401 envelope.
func (v *Verifier) Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		raw, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
		if !ok || raw == "" {
			envelope.Fail(w, http.StatusUnauthorized, envelope.Unauthenticated, "missing bearer token")
			return
		}
		p, err := v.Verify(r.Context(), raw)
		if err != nil {
			envelope.Fail(w, http.StatusUnauthorized, envelope.Unauthenticated, "invalid or expired token")
			return
		}
		next.ServeHTTP(w, r.WithContext(WithPrincipal(r.Context(), p)))
	})
}

// RequireKind rejects callers whose token is not of kind k with a 403 envelope.
func RequireKind(k Kind, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if p, ok := FromContext(r.Context()); !ok || p.Kind != k {
			envelope.Fail(w, http.StatusForbidden, envelope.Forbidden, "this route requires a "+string(k)+" token")
			return
		}
		next.ServeHTTP(w, r)
	})
}

// RequireScope rejects callers whose token lacks scope with a 403 envelope.
func RequireScope(scope string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if p, ok := FromContext(r.Context()); !ok || !p.HasScope(scope) {
			envelope.Fail(w, http.StatusForbidden, envelope.Forbidden, "missing scope "+scope)
			return
		}
		next.ServeHTTP(w, r)
	})
}
