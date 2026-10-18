// Package httpapi wires the DocBridge routes in contracts/openapi/docbridge.yaml to the
// access, destinations, jobs and files packages.
package httpapi

import (
	"net/http"

	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/envelope"
	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/httpserve"
	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/jwtverify"
)

// Config is the DocBridge API configuration.
type Config struct {
	DatabaseURL   string
	StagingBucket string
}

// Handler serves the DocBridge API.
func Handler(_ Config, verifier *jwtverify.Verifier) http.Handler {
	mux := http.NewServeMux()
	httpserve.Health(mux)

	user := func(h http.HandlerFunc) http.Handler {
		return verifier.Middleware(jwtverify.RequireKind(jwtverify.User, h))
	}
	mux.Handle("GET /v1/destinations", user(envelope.NotImplementedHandler))
	mux.Handle("POST /v1/jobs", user(envelope.NotImplementedHandler))
	mux.Handle("GET /v1/jobs", user(envelope.NotImplementedHandler))
	mux.Handle("GET /v1/jobs/{jobId}", user(envelope.NotImplementedHandler))
	mux.Handle("POST /v1/jobs/{jobId}/files/{fileId}/upload-target", user(envelope.NotImplementedHandler))
	mux.Handle("POST /v1/jobs/{jobId}/files/{fileId}/upload-failed", user(envelope.NotImplementedHandler))
	mux.Handle("GET /v1/files/{fileId}/download-url", user(envelope.NotImplementedHandler))
	return mux
}
