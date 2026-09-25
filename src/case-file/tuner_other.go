//go:build !linux

package main

import "errors"

func setMTU(string, int) error { return errors.New("setting the MTU is only supported on Linux") }
