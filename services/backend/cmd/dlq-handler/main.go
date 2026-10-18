// Command dlq-handler is the Lambda triggered by tasks-dlq.
package main

import (
	"github.com/aws/aws-lambda-go/lambda"

	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/dlq"
	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/platform/config"
	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/platform/logging"
)

func main() {
	var env config.Env
	h := &dlq.Handler{Log: logging.New(config.LoadCommon(&env, "dlq-handler"))}
	lambda.Start(h.Handle)
}
