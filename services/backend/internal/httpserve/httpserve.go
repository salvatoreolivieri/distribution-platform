// Package httpserve runs an http.Handler behind API Gateway (HTTP API, payload v2) when
// running in Lambda, and as a plain HTTP server otherwise (docker-compose, go run).
package httpserve

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/akrylysov/algnhsa"
)

// Run blocks serving h. addr is used only outside Lambda.
func Run(h http.Handler, addr string) error {
	if os.Getenv("AWS_LAMBDA_RUNTIME_API") != "" {
		algnhsa.ListenAndServe(h, &algnhsa.Options{RequestType: algnhsa.RequestTypeAPIGatewayV2})
		return nil
	}

	srv := &http.Server{Addr: addr, Handler: h, ReadHeaderTimeout: 10 * time.Second}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	errc := make(chan error, 1)
	go func() {
		slog.Info("listening", "addr", addr)
		errc <- srv.ListenAndServe()
	}()
	select {
	case err := <-errc:
		return err
	case <-ctx.Done():
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := srv.Shutdown(shutdownCtx); err != nil && !errors.Is(err, http.ErrServerClosed) {
			return err
		}
		return nil
	}
}

// Health answers GET /healthz with 200. Every HTTP binary mounts it.
func Health(mux *http.ServeMux) {
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"data":{"status":"ok"}}`))
	})
}
