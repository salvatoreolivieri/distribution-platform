// Package logging builds the JSON slog logger every binary uses.
package logging

import (
	"log/slog"
	"os"
	"strings"

	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/platform/config"
)

// New returns a JSON logger tagged with the service and environment, and sets it as default.
func New(c config.Common) *slog.Logger {
	var level slog.Level
	switch strings.ToLower(c.LogLevel) {
	case "debug":
		level = slog.LevelDebug
	case "warn":
		level = slog.LevelWarn
	case "error":
		level = slog.LevelError
	default:
		level = slog.LevelInfo
	}
	l := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: level})).
		With("service", c.Service, "env", c.Env)
	slog.SetDefault(l)
	return l
}
