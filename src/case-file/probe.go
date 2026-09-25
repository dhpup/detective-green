package main

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// probeResult is the outcome of one request through frontdesk.
type probeResult struct {
	method   string
	size     int
	node     string // X-Node from the response ("unknown" if none)
	duration time.Duration
	err      error // transport error or non-2xx status, with frontdesk's message
}

// probe sends one GET (download) or POST (upload) of size bytes to target on
// a fresh connection, and reads the whole response.
func probe(target, method string, size int, timeout time.Duration) probeResult {
	client, _ := newHopClient(timeout)
	res := probeResult{method: method, size: size, node: "unknown"}
	start := time.Now()

	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	var req *http.Request
	var err error
	if method == http.MethodPost {
		req, err = http.NewRequestWithContext(ctx, method, target+"/api/evidence", bytes.NewReader(bytes.Repeat([]byte{'x'}, size)))
	} else {
		req, err = http.NewRequestWithContext(ctx, method, fmt.Sprintf("%s/api/evidence?size=%d", target, size), nil)
	}
	if err != nil {
		res.err = err
		return res
	}
	req.Header.Set("Content-Type", "application/octet-stream")
	resp, err := client.Do(req)
	if err != nil {
		res.err = err
		res.duration = time.Since(start)
		return res
	}
	defer func() { _ = resp.Body.Close() }()
	if n := resp.Header.Get("X-Node"); n != "" {
		res.node = n
	}
	body, err := io.ReadAll(resp.Body)
	switch {
	case err != nil:
		res.err = err
	case resp.StatusCode >= 300:
		res.err = fmt.Errorf("%d %s", resp.StatusCode, strings.TrimSpace(string(body)))
	case method == http.MethodGet && len(body) != size:
		res.err = fmt.Errorf("short response: got %d of %d bytes", len(body), size)
	}
	res.duration = time.Since(start)
	return res
}
