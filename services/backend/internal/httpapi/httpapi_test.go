package httpapi

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/jwtverify"
)

func TestRoutesRequireAToken(t *testing.T) {
	h := Handler(Config{}, jwtverify.New(jwtverify.Config{JWKSURL: "http://127.0.0.1:1"}))

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/v1/jobs", nil))
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}

	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("healthz status = %d", rec.Code)
	}
}
