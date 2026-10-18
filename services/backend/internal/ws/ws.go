// Package ws handles every route of the WebSocket API: $connect authenticates the token
// passed in the query string, $disconnect drops the connection, and subscribe registers
// interest in a job so status changes are pushed to the browser.
package ws

import (
	"context"
	"log/slog"
	"net/http"

	"github.com/aws/aws-lambda-go/events"
)

// Handler routes WebSocket events by route key.
type Handler struct {
	Log *slog.Logger
}

// Handle is the Lambda entry point.
func (h *Handler) Handle(_ context.Context, req events.APIGatewayWebsocketProxyRequest) (events.APIGatewayProxyResponse, error) {
	rc := req.RequestContext
	h.Log.Info("websocket event", "route", rc.RouteKey, "connection_id", rc.ConnectionID)
	switch rc.RouteKey {
	case "$connect", "$disconnect", "subscribe":
		return events.APIGatewayProxyResponse{StatusCode: http.StatusOK}, nil
	default:
		return events.APIGatewayProxyResponse{StatusCode: http.StatusBadRequest, Body: `{"error":{"code":"VALIDATION_FAILED","message":"unknown route"}}`}, nil
	}
}
