package main

import (
	"fmt"
	"strconv"
	"strings"
)

// parseSize parses a byte count with an optional binary suffix: "512", "16K", "4M".
func parseSize(s string) (int, error) {
	s = strings.TrimSpace(strings.ToUpper(s))
	mult := 1
	switch {
	case strings.HasSuffix(s, "K"):
		mult, s = 1<<10, strings.TrimSuffix(s, "K")
	case strings.HasSuffix(s, "M"):
		mult, s = 1<<20, strings.TrimSuffix(s, "M")
	}
	n, err := strconv.Atoi(s)
	if err != nil || n < 0 {
		return 0, fmt.Errorf("invalid size %q", s)
	}
	return n * mult, nil
}

// parseSizes parses a comma-separated list of sizes.
func parseSizes(list string) ([]int, error) {
	var sizes []int
	for _, s := range strings.Split(list, ",") {
		n, err := parseSize(s)
		if err != nil {
			return nil, err
		}
		sizes = append(sizes, n)
	}
	return sizes, nil
}

// formatSize is the inverse of parseSize for whole K and M values.
func formatSize(n int) string {
	switch {
	case n >= 1<<20 && n%(1<<20) == 0:
		return fmt.Sprintf("%dM", n>>20)
	case n >= 1<<10 && n%(1<<10) == 0:
		return fmt.Sprintf("%dK", n>>10)
	}
	return strconv.Itoa(n)
}

// sizeBucket groups payload sizes for metrics. Anything above one full-size
// TCP segment can hit the MTU black hole, so "small" means health-check sized.
func sizeBucket(n int64) string {
	switch {
	case n <= 1<<10:
		return "small"
	case n <= 64<<10:
		return "medium"
	}
	return "large"
}
