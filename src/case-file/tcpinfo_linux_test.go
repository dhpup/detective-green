package main

import (
	"net"
	"testing"
)

// TCP_INFO can be read from a live connection. Loopback never retransmits,
// so the count is 0; the point is that the syscall works.
func TestTCPRetransmitsReadable(t *testing.T) {
	var lc net.ListenConfig
	ln, err := lc.Listen(t.Context(), "tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = ln.Close() }()
	go func() {
		if c, err := ln.Accept(); err == nil {
			_ = c.Close()
		}
	}()
	var d net.Dialer
	c, err := d.DialContext(t.Context(), "tcp", ln.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = c.Close() }()
	if got := tcpRetransmits(c); got != 0 {
		t.Fatalf("loopback retransmits = %d, want 0", got)
	}
}
