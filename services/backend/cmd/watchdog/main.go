// Command watchdog is the Lambda run on the EventBridge schedule.
package main

import (
	"github.com/aws/aws-lambda-go/lambda"

	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/platform/config"
	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/platform/logging"
	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/watchdog"
)

func main() {
	var env config.Env
	h := &watchdog.Handler{Log: logging.New(config.LoadCommon(&env, "watchdog"))}
	lambda.Start(h.Handle)
}
