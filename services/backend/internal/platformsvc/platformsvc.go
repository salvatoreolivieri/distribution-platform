// Package platformsvc is the document platform: public browse and document routes, and the
// /internal/v1/* ingest API the task worker calls. One deployment per region.
package platformsvc

import (
	"net/http"

	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/envelope"
	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/httpserve"
	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/jwtverify"
)

// IngestScope is required on /internal/v1/* (also enforced by the API Gateway authorizer).
const IngestScope = "documents:ingest"

// Config is the platform service configuration.
type Config struct {
	Region          string
	DatabaseURL     string
	DocumentsBucket string
	StagingBucket   string
	Faults          Faults
}

// Handler serves the routes in contracts/openapi/platform.yaml.
func Handler(cfg Config, verifier *jwtverify.Verifier) http.Handler {
	mux := http.NewServeMux()
	httpserve.Health(mux)

	user := func(h http.HandlerFunc) http.Handler {
		return verifier.Middleware(jwtverify.RequireKind(jwtverify.User, h))
	}
	mux.Handle("GET /v1/binders", user(envelope.NotImplementedHandler))
	mux.Handle("GET /v1/binders/{binderId}/tree", user(envelope.NotImplementedHandler))
	mux.Handle("GET /v1/documents/{documentId}", user(envelope.NotImplementedHandler))
	mux.Handle("GET /v1/documents/{documentId}/download", user(envelope.NotImplementedHandler))

	ingest := func(h http.HandlerFunc) http.Handler {
		return verifier.Middleware(jwtverify.RequireScope(IngestScope, cfg.Faults.Middleware(h)))
	}
	mux.Handle("POST /internal/v1/binders/{binderId}/documents", ingest(envelope.NotImplementedHandler))
	return mux
}
