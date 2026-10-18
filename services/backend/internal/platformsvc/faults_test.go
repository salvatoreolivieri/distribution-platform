package platformsvc

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func serve(f Faults, binder string) *httptest.ResponseRecorder {
	mux := http.NewServeMux()
	mux.Handle("POST /internal/v1/binders/{binderId}/documents", f.Middleware(http.HandlerFunc(
		func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusCreated) })))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/internal/v1/binders/"+binder+"/documents", nil))
	return rec
}

func TestFaults(t *testing.T) {
	cases := []struct {
		name   string
		faults Faults
		binder string
		want   int
	}{
		{"no faults", Faults{}, "b1", http.StatusCreated},
		{"forced status", Faults{Default: Rule{ForcedStatus: 429}}, "b1", http.StatusTooManyRequests},
		{"error rate hit", Faults{Default: Rule{ErrorRate: 0.5}, rand: func() float64 { return 0.1 }}, "b1", http.StatusServiceUnavailable},
		{"error rate miss", Faults{Default: Rule{ErrorRate: 0.5}, rand: func() float64 { return 0.9 }}, "b1", http.StatusCreated},
		{"per-binder override", Faults{Default: Rule{ForcedStatus: 500}, Binders: map[string]Rule{"b2": {}}}, "b2", http.StatusCreated},
		{"per-binder failure", Faults{Binders: map[string]Rule{"b2": {ForcedStatus: 422}}}, "b2", http.StatusUnprocessableEntity},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := serve(tc.faults, tc.binder).Code; got != tc.want {
				t.Fatalf("status = %d, want %d", got, tc.want)
			}
		})
	}
}
