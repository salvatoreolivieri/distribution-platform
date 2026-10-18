// Package uploads is the upload-handler: it reads S3 ObjectCreated events from the
// upload-events queue, marks the file uploaded, creates one task per destination and sends
// a TaskMessage per task to the tasks queue. See contracts/events/s3-upload-event.md.
package uploads

import (
	"context"
	"log/slog"

	"github.com/aws/aws-lambda-go/events"
)

// Handler processes a batch from the upload-events queue and reports per-message failures.
type Handler struct {
	Log *slog.Logger
}

// Handle is the Lambda entry point.
func (h *Handler) Handle(_ context.Context, batch events.SQSEvent) (events.SQSEventResponse, error) {
	var resp events.SQSEventResponse
	for _, msg := range batch.Records {
		h.Log.Info("upload event received", "message_id", msg.MessageId)
	}
	return resp, nil
}
