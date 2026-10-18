// Package config reads service configuration from environment variables.
package config

import (
	"fmt"
	"os"
	"strconv"
	"time"
)

// Env reads environment variables and collects missing required ones, so a service
// reports every missing setting at once instead of one per restart.
type Env struct {
	missing []string
}

// String returns the variable or def when unset.
func (e *Env) String(key, def string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return def
}

// Required returns the variable and records it as missing when unset.
func (e *Env) Required(key string) string {
	v := os.Getenv(key)
	if v == "" {
		e.missing = append(e.missing, key)
	}
	return v
}

// Int returns the variable parsed as an int, or def when unset or invalid.
func (e *Env) Int(key string, def int) int {
	if n, err := strconv.Atoi(os.Getenv(key)); err == nil {
		return n
	}
	return def
}

// Duration returns the variable parsed with time.ParseDuration, or def.
func (e *Env) Duration(key string, def time.Duration) time.Duration {
	if d, err := time.ParseDuration(os.Getenv(key)); err == nil {
		return d
	}
	return def
}

// Err reports every missing required variable.
func (e *Env) Err() error {
	if len(e.missing) == 0 {
		return nil
	}
	return fmt.Errorf("missing required environment variables: %v", e.missing)
}

// Common is the configuration every binary shares.
type Common struct {
	Service  string // set by the binary
	Env      string // dev, prod, local
	LogLevel string
}

// LoadCommon reads the shared settings.
func LoadCommon(e *Env, service string) Common {
	return Common{
		Service:  service,
		Env:      e.String("APP_ENV", "local"),
		LogLevel: e.String("LOG_LEVEL", "info"),
	}
}
