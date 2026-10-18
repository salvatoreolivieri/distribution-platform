package platformsvc

import (
	"encoding/json"
	"math/rand/v2"
	"net/http"
	"os"
	"time"

	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/envelope"
)

// Rule injects failures into the ingest API, so the worker's retry and error mapping can be
// exercised against the real platform. The zero Rule injects nothing.
type Rule struct {
	// ErrorRate is the probability, 0..1, of answering ForcedStatus (503 when unset).
	ErrorRate float64 `json:"error_rate"`
	// ForcedStatus, when set and ErrorRate is 0, is returned on every request.
	ForcedStatus int `json:"forced_status"`
	// LatencyMs is added before the request is handled or failed.
	LatencyMs int `json:"latency_ms"`
}

// Faults is the failure-injection configuration: a default rule plus per-binder overrides.
type Faults struct {
	Default Rule            `json:"default"`
	Binders map[string]Rule `json:"binders"`

	rand func() float64
}

// LoadFaults reads the JSON file at path. An empty path disables injection.
func LoadFaults(path string) (Faults, error) {
	if path == "" {
		return Faults{}, nil
	}
	b, err := os.ReadFile(path)
	if err != nil {
		return Faults{}, err
	}
	var f Faults
	err = json.Unmarshal(b, &f)
	return f, err
}

func (f Faults) rule(binderID string) Rule {
	if r, ok := f.Binders[binderID]; ok {
		return r
	}
	return f.Default
}

// Middleware applies the rule for the request's {binderId} path value.
func (f Faults) Middleware(next http.Handler) http.Handler {
	random := f.rand
	if random == nil {
		random = rand.Float64
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		rule := f.rule(r.PathValue("binderId"))
		if rule.LatencyMs > 0 {
			select {
			case <-time.After(time.Duration(rule.LatencyMs) * time.Millisecond):
			case <-r.Context().Done():
				return
			}
		}
		status := rule.ForcedStatus
		fail := status != 0 && rule.ErrorRate == 0
		if rule.ErrorRate > 0 && random() < rule.ErrorRate {
			fail = true
			if status == 0 {
				status = http.StatusServiceUnavailable
			}
		}
		if fail {
			w.Header().Set("X-Fault-Injected", "true")
			envelope.Fail(w, status, codeFor(status), "injected failure")
			return
		}
		next.ServeHTTP(w, r)
	})
}

func codeFor(status int) envelope.Code {
	switch {
	case status == http.StatusTooManyRequests:
		return envelope.RateLimited
	case status == http.StatusConflict:
		return envelope.Conflict
	case status == http.StatusNotFound:
		return envelope.NotFound
	case status == http.StatusForbidden:
		return envelope.Forbidden
	case status == http.StatusUnprocessableEntity || status == http.StatusBadRequest:
		return envelope.ValidationFailed
	case status >= 500:
		return envelope.UpstreamUnavailable
	default:
		return envelope.Internal
	}
}
