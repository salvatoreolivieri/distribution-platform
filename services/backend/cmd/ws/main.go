// Command ws is the Lambda behind every WebSocket API route.
package main

import (
	"github.com/aws/aws-lambda-go/lambda"

	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/platform/config"
	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/platform/logging"
	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/ws"
)

func main() {
	var env config.Env
	h := &ws.Handler{Log: logging.New(config.LoadCommon(&env, "ws"))}
	lambda.Start(h.Handle)
}
