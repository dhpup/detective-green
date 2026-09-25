package main

import (
	"bytes"
	"context"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/prometheus/client_golang/prometheus/testutil"
)

// do sends a request with the test's context.
func do(t *testing.T, method, url string, body io.Reader) *http.Response {
	t.Helper()
	req, err := http.NewRequestWithContext(t.Context(), method, url, body)
	if err != nil {
		t.Fatal(err)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	return resp
}

// newAPI starts a real evidence-locker on a test server.
func newAPI(t *testing.T, node string) *httptest.Server {
	t.Helper()
	e := &evidenceLocker{node: node, requests: newCounter("api_requests_total", "", "method", "size_bucket", "code")}
	srv := httptest.NewServer(e.routes())
	t.Cleanup(srv.Close)
	return srv
}

// newFrontdeskFor starts a frontdesk whose "headless Service" resolves to the given server.
func newFrontdeskFor(t *testing.T, upstream *httptest.Server, timeout time.Duration) (*frontdesk, *httptest.Server) {
	t.Helper()
	host, port, _ := net.SplitHostPort(upstream.Listener.Addr().String())
	f := newFrontdesk("evidence-locker-headless", port, timeout, func(context.Context, string) ([]string, error) {
		return []string{host}, nil
	})
	srv := httptest.NewServer(f.routes())
	t.Cleanup(srv.Close)
	return f, srv
}

func TestEvidenceLocker(t *testing.T) {
	api := newAPI(t, "node-a")

	resp := do(t, http.MethodGet, api.URL+"/api/evidence?size=16K", nil)
	body, _ := io.ReadAll(resp.Body)
	_ = resp.Body.Close()
	if len(body) != 16<<10 || resp.Header.Get("X-Node") != "node-a" {
		t.Fatalf("GET: got %d bytes, X-Node=%q", len(body), resp.Header.Get("X-Node"))
	}

	resp = do(t, http.MethodPost, api.URL+"/api/evidence", bytes.NewReader(make([]byte, 5000)))
	body, _ = io.ReadAll(resp.Body)
	_ = resp.Body.Close()
	if !strings.Contains(string(body), `"received":5000`) {
		t.Fatalf("POST: body %s", body)
	}

	resp = do(t, http.MethodGet, api.URL+"/api/evidence?size=17M", nil)
	_ = resp.Body.Close()
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("oversized GET: status %d, want 400", resp.StatusCode)
	}
}

func TestFrontdeskForwardsAndLearnsNodes(t *testing.T) {
	api := newAPI(t, "node-a")
	f, fd := newFrontdeskFor(t, api, 2*time.Second)

	r := probe(fd.URL, http.MethodPost, 256<<10, 2*time.Second)
	if r.err != nil || r.node != "node-a" {
		t.Fatalf("POST through frontdesk: node=%q err=%v", r.node, r.err)
	}
	r = probe(fd.URL, http.MethodGet, 1<<20, 2*time.Second)
	if r.err != nil || r.node != "node-a" {
		t.Fatalf("GET through frontdesk: node=%q err=%v", r.node, r.err)
	}
	if got := testutil.ToFloat64(f.requests.WithLabelValues("POST", "large", "node-a", "ok")); got != 1 {
		t.Fatalf("upstream_requests_total{POST,large,node-a,ok} = %v, want 1", got)
	}
}

func TestFrontdeskUpstreamTimeout(t *testing.T) {
	// An upstream that accepts connections but never answers, like the black
	// hole. It gives up when the caller does, so the test server can close.
	stuck := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Query().Get("size") == "64" { // small requests still work
			w.Header().Set("X-Node", "node-blue")
			_, _ = w.Write(make([]byte, 64))
			return
		}
		// Drain the upload first: the server only notices the caller hanging
		// up (and cancels the context) once the body has been read.
		_, _ = io.Copy(io.Discard, r.Body)
		<-r.Context().Done()
	}))
	t.Cleanup(stuck.Close)
	_, fd := newFrontdeskFor(t, stuck, 300*time.Millisecond)

	// A small request teaches frontdesk which node this pod is on...
	if r := probe(fd.URL, http.MethodGet, 64, time.Second); r.err != nil {
		t.Fatalf("small request: %v", r.err)
	}
	// ...so the timed-out upload is still attributed to it.
	r := probe(fd.URL, http.MethodPost, 64<<10, 2*time.Second)
	if r.err == nil {
		t.Fatal("upload to a hanging upstream should fail")
	}
	msg := r.err.Error()
	for _, want := range []string{"504", "node-blue", "TCP retransmits"} {
		if !strings.Contains(msg, want) {
			t.Errorf("error %q should mention %q", msg, want)
		}
	}
	if r.node != "node-blue" {
		t.Errorf("X-Node on failure = %q, want node-blue", r.node)
	}
}

func TestSweep(t *testing.T) {
	api := newAPI(t, "node-a")
	_, fd := newFrontdeskFor(t, api, 2*time.Second)

	var out bytes.Buffer
	if err := runSweep([]string{"-target", fd.URL, "-sizes", "1K,64K", "-attempts", "2"}, &out); err != nil {
		t.Fatalf("sweep against a healthy app failed: %v\n%s", err, &out)
	}
	if !strings.Contains(out.String(), "RESULT 8/8 requests passed") {
		t.Fatalf("unexpected output:\n%s", &out)
	}

	// Uploads fail, downloads work: the black hole's signature.
	broken := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodPost {
			http.Error(w, "upstream evidence-locker 10.42.1.7 on node blue failed (8 TCP retransmits)", http.StatusGatewayTimeout)
			return
		}
		_, _ = w.Write(make([]byte, 1<<10))
	}))
	t.Cleanup(broken.Close)
	out.Reset()
	if err := runSweep([]string{"-target", broken.URL, "-sizes", "1K", "-attempts", "1"}, &out); err == nil {
		t.Fatal("sweep should fail when uploads fail")
	}
	if !strings.Contains(out.String(), "FAIL POST") || !strings.Contains(out.String(), "8 TCP retransmits") {
		t.Fatalf("failure output should carry frontdesk's message:\n%s", &out)
	}
}
