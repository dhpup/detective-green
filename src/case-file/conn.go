package main

import (
	"context"
	"net"
	"net/http"
	"sync"
	"time"
)

// hop records what happened on the single TCP connection behind one request:
// which address it went to and how many segments TCP had to retransmit.
// Retransmits come from the kernel's TCP_INFO, read just before the
// connection closes, so they count this request only. If the transport retries
// on a second connection, retransmits from both are added up.
type hop struct {
	mu        sync.Mutex
	remoteIP  string
	retrans   uint32
	closed    chan struct{}
	closeOnce sync.Once
}

// newHopClient returns an HTTP client that opens exactly one fresh connection
// per request (no keep-alives) and records it in the returned hop.
func newHopClient(timeout time.Duration) (*http.Client, *hop) {
	h := &hop{closed: make(chan struct{})}
	dialer := &net.Dialer{Timeout: timeout}
	transport := &http.Transport{
		DisableKeepAlives: true,
		DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			c, err := dialer.DialContext(ctx, network, addr)
			if err != nil {
				return nil, err
			}
			ip, _, _ := net.SplitHostPort(c.RemoteAddr().String())
			h.mu.Lock()
			h.remoteIP = ip
			h.mu.Unlock()
			return &trackedConn{Conn: c, hop: h}, nil
		},
	}
	return &http.Client{Timeout: timeout, Transport: transport}, h
}

// stats waits briefly for the connection to close, then returns what was
// recorded. The transport closes the connection asynchronously once the
// response body is closed or the request fails.
func (h *hop) stats(client *http.Client) (remoteIP string, retrans uint32) {
	client.CloseIdleConnections()
	select {
	case <-h.closed:
	case <-time.After(time.Second):
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.remoteIP, h.retrans
}

type trackedConn struct {
	net.Conn
	hop  *hop
	once sync.Once
}

func (c *trackedConn) Close() error {
	c.once.Do(func() {
		r := tcpRetransmits(c.Conn)
		c.hop.mu.Lock()
		c.hop.retrans += r
		c.hop.mu.Unlock()
		c.hop.closeOnce.Do(func() { close(c.hop.closed) })
	})
	return c.Conn.Close()
}
