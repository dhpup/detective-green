package main

import (
	"flag"
	"log/slog"
	"net/http"
	"time"

	"github.com/prometheus/client_golang/prometheus"
)

// informant plays the city: users sending a steady mix of small and large
// downloads and uploads through frontdesk, each on a fresh connection.
// Its metrics show which sizes fail and on which node.
func runInformant(args []string) error {
	fs := flag.NewFlagSet("informant", flag.ExitOnError)
	listen := fs.String("listen", ":9090", "metrics listen address")
	target := fs.String("target", "http://frontdesk:8080", "frontdesk base URL")
	interval := fs.Duration("interval", time.Second, "time between requests")
	sizeList := fs.String("sizes", "1K,16K,256K,1M", "payload sizes to cycle through")
	timeout := fs.Duration("timeout", 6*time.Second, "per-request timeout")
	_ = fs.Parse(args)

	sizes, err := parseSizes(*sizeList)
	if err != nil {
		return err
	}
	reg := prometheus.NewRegistry()
	requests := newCounter("probe_requests_total", "Requests sent by the informant.", "method", "size_bucket", "dst_node", "result")
	duration := newHistogram("probe_duration_seconds", "Informant request duration.", "method", "size_bucket", "result")
	reg.MustRegister(requests, duration)

	go func() {
		methods := []string{http.MethodGet, http.MethodPost}
		for i := 0; ; i++ {
			method, size := methods[i%2], sizes[(i/2)%len(sizes)]
			r := probe(*target, method, size, *timeout)
			result := "ok"
			if r.err != nil {
				result = "error"
				slog.Warn("probe failed", "method", method, "size", formatSize(size), "dst_node", r.node, "err", r.err)
			}
			bucket := sizeBucket(int64(size))
			requests.WithLabelValues(method, bucket, r.node, result).Inc()
			duration.WithLabelValues(method, bucket, result).Observe(r.duration.Seconds())
			time.Sleep(*interval)
		}
	}()
	return serve(*listen, http.NewServeMux(), reg)
}
