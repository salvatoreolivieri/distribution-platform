// Command api is the DocBridge HTTP API.
package main

import (
	"log/slog"
	"os"

	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/httpapi"
	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/httpserve"
	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/jwtverify"
	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/platform/config"
	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/platform/logging"
)

func main() {
	var env config.Env
	logging.New(config.LoadCommon(&env, "api"))
	cfg := httpapi.Config{
		DatabaseURL:   env.Required("DATABASE_URL"),
		StagingBucket: env.Required("STAGING_BUCKET"),
	}
	verifier := jwtverify.New(jwtverify.Config{
		JWKSURL:  env.Required("JWKS_URL"),
		Issuer:   env.Required("JWT_ISSUER"),
		Audience: env.Required("JWT_AUDIENCE"),
	})
	if err := env.Err(); err != nil {
		slog.Error("config", "err", err)
		os.Exit(1)
	}
	if err := httpserve.Run(httpapi.Handler(cfg, verifier), env.String("HTTP_ADDR", ":8080")); err != nil {
		slog.Error("serve", "err", err)
		os.Exit(1)
	}
}
