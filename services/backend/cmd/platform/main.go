// Command platform is the document platform service, one deployment per region.
package main

import (
	"log/slog"
	"os"

	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/httpserve"
	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/jwtverify"
	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/platform/config"
	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/platform/logging"
	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/platformsvc"
)

func main() {
	var env config.Env
	log := logging.New(config.LoadCommon(&env, "platform"))
	faults, err := platformsvc.LoadFaults(env.String("FAULTS_FILE", ""))
	if err != nil {
		slog.Error("faults config", "err", err)
		os.Exit(1)
	}
	cfg := platformsvc.Config{
		Region:          env.Required("PLATFORM_REGION"),
		DatabaseURL:     env.Required("DATABASE_URL"),
		DocumentsBucket: env.Required("DOCUMENTS_BUCKET"),
		StagingBucket:   env.Required("STAGING_BUCKET"),
		Faults:          faults,
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
	log.Info("starting", "region", cfg.Region)
	if err := httpserve.Run(platformsvc.Handler(cfg, verifier), env.String("HTTP_ADDR", ":8080")); err != nil {
		slog.Error("serve", "err", err)
		os.Exit(1)
	}
}
