//go:build !linux

package main

import "net"

// tcpRetransmits is Linux-only; elsewhere (local builds on macOS) it reports 0.
func tcpRetransmits(net.Conn) uint32 { return 0 }
