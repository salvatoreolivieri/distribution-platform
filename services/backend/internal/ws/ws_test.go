package ws

import (
	"context"
	"io"
	"log/slog"
	"testing"

	"github.com/aws/aws-lambda-go/events"
)

func TestRoutes(t *testing.T) {
	h := &Handler{Log: slog.New(slog.NewTextHandler(io.Discard, nil))}
	for route, want := range map[string]int{"$connect": 200, "$disconnect": 200, "subscribe": 200, "$default": 400} {
		req := events.APIGatewayWebsocketProxyRequest{RequestContext: events.APIGatewayWebsocketProxyRequestContext{RouteKey: route}}
		resp, err := h.Handle(context.Background(), req)
		if err != nil || resp.StatusCode != want {
			t.Errorf("%s: status = %d, err = %v, want %d", route, resp.StatusCode, err, want)
		}
	}
}
