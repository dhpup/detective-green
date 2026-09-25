package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"io"
	"net/http"
	"os"
	"strconv"

	"github.com/prometheus/client_golang/prometheus"
)

// maxPayload caps request and response sizes so the API can't be used to
// exhaust memory.
const maxPayload = 16 << 20

// evidenceLocker is the API. It stamps every response with the node it runs
// on (X-Node), which is how callers learn where a request landed.
type evidenceLocker struct {
	node     string
	requests *prometheus.CounterVec
}

func runEvidenceLocker(args []string) error {
	fs := flag.NewFlagSet("evidence-locker", flag.ExitOnError)
	listen := fs.String("listen", ":8080", "listen address")
	_ = fs.Parse(args)

	reg := prometheus.NewRegistry()
	e := &evidenceLocker{
		node:     os.Getenv("NODE_NAME"),
		requests: newCounter("api_requests_total", "Requests served by evidence-locker.", "method", "size_bucket", "code"),
	}
	reg.MustRegister(e.requests)
	return serve(*listen, e.routes(), reg)
}

func (e *evidenceLocker) routes() *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/evidence", e.get)
	mux.HandleFunc("POST /api/evidence", e.post)
	return mux
}

// get returns ?size= bytes.
func (e *evidenceLocker) get(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("X-Node", e.node)
	n, err := parseSize(r.URL.Query().Get("size"))
	if err != nil || n > maxPayload {
		e.requests.WithLabelValues("GET", "small", "400").Inc()
		http.Error(w, "size must be between 0 and 16M", http.StatusBadRequest)
		return
	}
	w.Header().Set("Content-Type", "application/octet-stream")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Content-Length", strconv.Itoa(n))
	// The body is n constant 'x' bytes served as octet-stream; no request data is echoed.
	_, _ = w.Write(bytes.Repeat([]byte{'x'}, n)) //nolint:gosec // G705 false positive, see above
	e.requests.WithLabelValues("GET", sizeBucket(int64(n)), "200").Inc()
}

// post accepts an upload and reports how many bytes arrived.
func (e *evidenceLocker) post(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("X-Node", e.node)
	n, err := io.Copy(io.Discard, http.MaxBytesReader(w, r.Body, maxPayload))
	if err != nil {
		e.requests.WithLabelValues("POST", sizeBucket(n), "400").Inc()
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"received": n, "node": e.node})
	e.requests.WithLabelValues("POST", sizeBucket(n), "200").Inc()
}
