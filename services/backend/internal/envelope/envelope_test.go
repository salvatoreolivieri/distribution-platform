package envelope

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestFail(t *testing.T) {
	rec := httptest.NewRecorder()
	Fail(rec, http.StatusForbidden, Forbidden, "no")

	if rec.Code != http.StatusForbidden {
		t.Fatalf("status = %d", rec.Code)
	}
	var body struct {
		Error Error `json:"error"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.Error.Code != Forbidden || body.Error.Message != "no" {
		t.Fatalf("body = %+v", body)
	}
}

func TestDataOmitsEmptyMeta(t *testing.T) {
	rec := httptest.NewRecorder()
	Data(rec, http.StatusOK, map[string]string{"a": "b"}, nil)

	if got, want := rec.Body.String(), `{"data":{"a":"b"}}`+"\n"; got != want {
		t.Fatalf("body = %q, want %q", got, want)
	}
}
