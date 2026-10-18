// Package auth is the auth service: login, refresh and logout for users, the
// client-credentials grant for services, and the JWKS endpoint. Tokens are ES256 JWTs
// signed with an asymmetric KMS key; kid is the key version.
package auth

import (
	"net/http"

	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/envelope"
	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/httpserve"
)

// Config is the auth service configuration.
type Config struct {
	Issuer      string
	KMSKeyID    string
	DatabaseURL string
}

// Handler serves the routes in contracts/openapi/auth.yaml.
func Handler(_ Config) http.Handler {
	mux := http.NewServeMux()
	httpserve.Health(mux)
	mux.HandleFunc("POST /v1/auth/login", envelope.NotImplementedHandler)
	mux.HandleFunc("POST /v1/auth/refresh", envelope.NotImplementedHandler)
	mux.HandleFunc("POST /v1/auth/logout", envelope.NotImplementedHandler)
	mux.HandleFunc("POST /v1/auth/token", envelope.NotImplementedHandler)
	mux.HandleFunc("GET /v1/auth/me", envelope.NotImplementedHandler)
	mux.HandleFunc("GET /.well-known/openid-configuration", envelope.NotImplementedHandler)
	mux.HandleFunc("GET /.well-known/jwks.json", envelope.NotImplementedHandler)
	return mux
}
