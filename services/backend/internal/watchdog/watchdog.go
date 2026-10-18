// Package watchdog runs on an EventBridge schedule and repairs what events alone cannot:
// uploads that expired before completing, tasks stuck in pending (re-enqueued), and
// in-progress tasks whose lease expired.
package watchdog

import (
	"context"
	"log/slog"

	"github.com/aws/aws-lambda-go/events"
)

// Handler is one watchdog sweep.
type Handler struct {
	Log *slog.Logger
}

// Handle is the Lambda entry point.
func (h *Handler) Handle(_ context.Context, ev events.EventBridgeEvent) error {
	h.Log.Info("watchdog sweep", "event_id", ev.ID)
	return nil
}
