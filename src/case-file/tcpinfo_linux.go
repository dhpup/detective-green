package main

import (
	"net"

	"golang.org/x/sys/unix"
)

// tcpRetransmits returns the kernel's total retransmitted-segment count for
// a TCP connection (TCP_INFO tcpi_total_retrans), or 0 if it can't be read.
func tcpRetransmits(c net.Conn) uint32 {
	tc, ok := c.(*net.TCPConn)
	if !ok {
		return 0
	}
	raw, err := tc.SyscallConn()
	if err != nil {
		return 0
	}
	var info *unix.TCPInfo
	if err := raw.Control(func(fd uintptr) {
		info, err = unix.GetsockoptTCPInfo(int(fd), unix.IPPROTO_TCP, unix.TCP_INFO)
	}); err != nil || info == nil {
		return 0
	}
	return info.Total_retrans
}
