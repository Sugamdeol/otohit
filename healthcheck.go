// The OtoHits client is not an HTTP server. This tiny companion process lets
// hosting platforms that require a port (such as Render Web Services) verify
// that the container is alive without exposing account information.
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"time"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "10000"
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/", status)
	mux.HandleFunc("/healthz", status)

	server := &http.Server{
		Addr:              ":" + port,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}
	log.Printf("health listener is running on port %s", port)
	log.Fatal(server.ListenAndServe())
}

func status(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	_ = json.NewEncoder(w).Encode(map[string]string{
		"status": "ok",
		"service": "otohits-client",
	})
}
