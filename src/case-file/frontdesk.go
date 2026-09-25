package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"log/slog"
	"math/rand/v2"
	"net"
	"net/http"
	"net/url"
	"sync"
	"time"

	"github.com/prometheus/client_golang/prometheus"
)

// frontdesk is the frontend. It forwards /api/evidence to an evidence-locker pod,
// picked per request from the headless Service's DNS records (client-side
// load balancing). Talking to pods directly, rather than a Service VIP, means
// each upstream connection's peer is a real pod IP: frontdesk can say which
// node a request went to, and read TCP_INFO for exactly that hop.
type frontdesk struct {
	apiHost string
	apiPort string
	timeout time.Duration
	lookup  func(ctx context.Context, host string) ([]string, error)

	// nodeByIP remembers which node each API pod IP is on, learned from the
	// X-Node header of successful responses. It lets failed requests (which
	// never get a response) still be attributed to a node.
	mu       sync.Mutex
	nodeByIP map[string]string

	requests *prometheus.CounterVec
	retrans  *prometheus.CounterVec
	duration *prometheus.HistogramVec
}

func runFrontdesk(args []string) error {
	fs := flag.NewFlagSet("frontdesk", flag.ExitOnError)
	listen := fs.String("listen", ":8080", "listen address")
	apiHost := fs.String("api-host", "evidence-locker-headless", "headless Service name of the API")
	apiPort := fs.String("api-port", "8080", "API port")
	timeout := fs.Duration("upstream-timeout", 4*time.Second, "timeout for each upstream request")
	_ = fs.Parse(args)

	reg := prometheus.NewRegistry()
	f := newFrontdesk(*apiHost, *apiPort, *timeout, net.DefaultResolver.LookupHost)
	reg.MustRegister(f.requests, f.retrans, f.duration)
	return serve(*listen, f.routes(), reg)
}

func newFrontdesk(host, port string, timeout time.Duration, lookup func(context.Context, string) ([]string, error)) *frontdesk {
	return &frontdesk{
		apiHost: host, apiPort: port, timeout: timeout, lookup: lookup,
		nodeByIP: map[string]string{},
		requests: newCounter("upstream_requests_total", "Requests frontdesk forwarded to evidence-locker.",
			"method", "size_bucket", "dst_node", "result"),
		retrans: newCounter("upstream_tcp_retransmits_total",
			"TCP segments retransmitted on frontdesk's connections to evidence-locker (from TCP_INFO).", "dst_node"),
		duration: newHistogram("upstream_duration_seconds", "Upstream request duration.",
			"method", "size_bucket", "result"),
	}
}

func (f *frontdesk) routes() *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("/api/evidence", f.forward)
	return mux
}

func (f *frontdesk) forward(w http.ResponseWriter, r *http.Request) {
	start := time.Now()
	size := requestSize(r)
	bucket := sizeBucket(size)

	ips, err := f.lookup(r.Context(), f.apiHost)
	if err != nil || len(ips) == 0 {
		http.Error(w, fmt.Sprintf("no evidence-locker endpoints for %s: %v", f.apiHost, err), http.StatusServiceUnavailable)
		f.requests.WithLabelValues(r.Method, bucket, "none", "no_endpoints").Inc()
		return
	}
	target := net.JoinHostPort(ips[rand.IntN(len(ips))], f.apiPort)

	client, h := newHopClient(f.timeout)
	ctx, cancel := context.WithTimeout(r.Context(), f.timeout)
	defer cancel()
	// Only the method, the fixed path and the query are taken from the caller.
	// The host is one of our own API pods, resolved from the configured Service.
	upURL := url.URL{Scheme: "http", Host: target, Path: "/api/evidence", RawQuery: r.URL.RawQuery}
	up, err := http.NewRequestWithContext(ctx, r.Method, upURL.String(), r.Body) //nolint:gosec // G704: host is not caller-controlled
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	up.ContentLength = r.ContentLength
	up.Header.Set("Content-Type", r.Header.Get("Content-Type"))

	resp, err := client.Do(up) //nolint:gosec // G704: see above
	if err == nil {
		// Copy while the upstream connection is still open, then close it so
		// its TCP_INFO can be read.
		for _, k := range []string{"Content-Type", "Content-Length", "X-Node"} {
			if v := resp.Header.Get(k); v != "" {
				w.Header().Set(k, v)
			}
		}
		w.WriteHeader(resp.StatusCode)
		_, err = io.Copy(w, resp.Body)
		_ = resp.Body.Close()
	}
	ip, retrans := h.stats(client)
	node := f.node(ip, resp)
	f.retrans.WithLabelValues(node).Add(float64(retrans))

	result := "ok"
	if err != nil {
		result = "error"
		if resp == nil { // nothing written to the client yet
			w.Header().Set("X-Node", node)
			http.Error(w, fmt.Sprintf("upload handler timed out: evidence-locker %s on node %s did not finish after %s: %v (%d TCP retransmits)",
				ip, node, time.Since(start).Round(time.Millisecond), err, retrans), http.StatusGatewayTimeout)
		}
		slog.Warn("upstream request failed", "method", r.Method, "size", size, "dst_ip", ip, "dst_node", node,
			"tcp_retransmits", retrans, "err", err)
	}
	f.requests.WithLabelValues(r.Method, bucket, node, result).Inc()
	f.duration.WithLabelValues(r.Method, bucket, result).Observe(time.Since(start).Seconds())
}

// node returns the node for an upstream IP: from the response if there was
// one (and remembers it), otherwise from what earlier responses taught us.
func (f *frontdesk) node(ip string, resp *http.Response) string {
	f.mu.Lock()
	defer f.mu.Unlock()
	if resp != nil {
		if n := resp.Header.Get("X-Node"); n != "" && ip != "" {
			f.nodeByIP[ip] = n
			return n
		}
	}
	if n, ok := f.nodeByIP[ip]; ok {
		return n
	}
	return "unknown"
}

// requestSize is the payload size of a request: the body for uploads, the
// ?size= parameter for downloads.
func requestSize(r *http.Request) int64 {
	if r.Method == http.MethodPost {
		return r.ContentLength
	}
	if n, err := parseSize(r.URL.Query().Get("size")); err == nil {
		return int64(n)
	}
	return 0
}
