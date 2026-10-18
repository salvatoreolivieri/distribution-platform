// Command auth is the auth service (Lambda behind API Gateway, or HTTP locally).
package main

import (
	"log/slog"
	"os"

	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/auth"
	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/httpserve"
	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/platform/config"
	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/platform/logging"
)

func main() {
	var env config.Env
	logging.New(config.LoadCommon(&env, "auth"))
	cfg := auth.Config{
		Issuer:      env.Required("JWT_ISSUER"),
		KMSKeyID:    env.Required("JWT_KMS_KEY_ID"),
		DatabaseURL: env.Required("DATABASE_URL"),
	}
	if err := env.Err(); err != nil {
		slog.Error("config", "err", err)
		os.Exit(1)
	}
	if err := httpserve.Run(auth.Handler(cfg), env.String("HTTP_ADDR", ":8080")); err != nil {
		slog.Error("serve", "err", err)
		os.Exit(1)
	}
}
