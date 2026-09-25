package main

import (
	"golang.org/x/sys/unix"
)

// setMTU sets an interface's MTU with the SIOCSIFMTU ioctl (needs CAP_NET_ADMIN).
// runTuner validates mtu to 576-9216 first, so the uint32 conversion is safe.
func setMTU(iface string, mtu int) error {
	fd, err := unix.Socket(unix.AF_INET, unix.SOCK_DGRAM, 0)
	if err != nil {
		return err
	}
	defer func() { _ = unix.Close(fd) }()
	ifr, err := unix.NewIfreq(iface)
	if err != nil {
		return err
	}
	ifr.SetUint32(uint32(mtu)) //nolint:gosec // G115: range-checked by runTuner
	return unix.IoctlIfreq(fd, unix.SIOCSIFMTU, ifr)
}
