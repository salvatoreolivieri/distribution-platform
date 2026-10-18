// Command upload-handler is the Lambda triggered by the upload-events queue.
package main

import (
	"github.com/aws/aws-lambda-go/lambda"

	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/platform/config"
	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/platform/logging"
	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/uploads"
)

func main() {
	var env config.Env
	h := &uploads.Handler{Log: logging.New(config.LoadCommon(&env, "upload-handler"))}
	lambda.Start(h.Handle)
}
