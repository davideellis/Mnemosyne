package main

import (
	"log"
	"net/http"
	"os"
	"time"

	"github.com/davideellis/Mnemosyne/services/sync_api/internal/api"
	"github.com/davideellis/Mnemosyne/services/sync_api/internal/runtime"
)

func main() {
	addr := envOrDefault("MNEMOSYNE_HTTP_ADDR", ":8080")
	store, err := runtime.BuildStore()
	if err != nil {
		log.Fatal(err)
	}
	handler := api.NewServer(store)

	srv := &http.Server{
		Addr:              addr,
		Handler:           handler.Routes(),
		ReadHeaderTimeout: 5 * time.Second,
	}

	log.Printf("mnemosyne sync api listening on %s", addr)
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatal(err)
	}
}

func envOrDefault(key string, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
