// Package envelope writes the response bodies defined in contracts/openapi/common.yaml:
// { "data": ..., "meta": ... } on success and { "error": { code, message, details } } on failure.
package envelope

import (
	"encoding/json"
	"net/http"
)

// Code is one of the ErrorCode values in common.yaml.
type Code string

const (
	Unauthenticated     Code = "UNAUTHENTICATED"
	Forbidden           Code = "FORBIDDEN"
	NotFound            Code = "NOT_FOUND"
	ValidationFailed    Code = "VALIDATION_FAILED"
	Conflict            Code = "CONFLICT"
	RateLimited         Code = "RATE_LIMITED"
	UpstreamUnavailable Code = "UPSTREAM_UNAVAILABLE"
	NotImplemented      Code = "NOT_IMPLEMENTED"
	Internal            Code = "INTERNAL"
)

// Error is the ApiError schema.
type Error struct {
	Code    Code           `json:"code"`
	Message string         `json:"message"`
	Details map[string]any `json:"details,omitempty"`
}

func (e *Error) Error() string { return string(e.Code) + ": " + e.Message }

type errorBody struct {
	Error *Error `json:"error"`
}

type dataBody struct {
	Data any `json:"data"`
	Meta any `json:"meta,omitempty"`
}

// Data writes a success envelope. meta may be nil.
func Data(w http.ResponseWriter, status int, data, meta any) {
	write(w, status, dataBody{Data: data, Meta: meta})
}

// Fail writes an error envelope.
func Fail(w http.ResponseWriter, status int, code Code, message string) {
	write(w, status, errorBody{Error: &Error{Code: code, Message: message}})
}

// FailWith writes an error envelope from an Error value.
func FailWith(w http.ResponseWriter, status int, err *Error) {
	write(w, status, errorBody{Error: err})
}

// NotImplementedHandler answers 501 for routes declared in the contract but not built yet.
func NotImplementedHandler(w http.ResponseWriter, r *http.Request) {
	Fail(w, http.StatusNotImplemented, NotImplemented, r.Method+" "+r.URL.Path+" is not implemented yet")
}

func write(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}
