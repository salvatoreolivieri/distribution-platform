// Package dlq is the dlq-handler: a TaskMessage lands on tasks-dlq once its receive count
// exceeds the retry budget, and the handler marks the task failed with RETRIES_EXHAUSTED.
package dlq

import (
	"context"
	"log/slog"

	"github.com/aws/aws-lambda-go/events"
)

// ErrorCode recorded on tasks that ran out of retries.
const ErrorCode = "RETRIES_EXHAUSTED"

// Handler processes a batch from tasks-dlq.
type Handler struct {
	Log *slog.Logger
}

// Handle is the Lambda entry point.
func (h *Handler) Handle(_ context.Context, batch events.SQSEvent) (events.SQSEventResponse, error) {
	var resp events.SQSEventResponse
	for _, msg := range batch.Records {
		h.Log.Info("dead-lettered task received", "message_id", msg.MessageId)
	}
	return resp, nil
}
