package main

import "testing"

func TestParseAndFormatSize(t *testing.T) {
	for in, want := range map[string]int{"512": 512, "1K": 1024, "16k": 16 << 10, "4M": 4 << 20} {
		got, err := parseSize(in)
		if err != nil || got != want {
			t.Errorf("parseSize(%q) = %d, %v; want %d", in, got, err, want)
		}
	}
	for _, bad := range []string{"", "x", "-1", "1G"} {
		if _, err := parseSize(bad); err == nil {
			t.Errorf("parseSize(%q) should fail", bad)
		}
	}
	for n, want := range map[int]string{512: "512", 1024: "1K", 16 << 10: "16K", 4 << 20: "4M"} {
		if got := formatSize(n); got != want {
			t.Errorf("formatSize(%d) = %q; want %q", n, got, want)
		}
	}
}

func TestSizeBucket(t *testing.T) {
	for n, want := range map[int64]string{64: "small", 1 << 10: "small", 16 << 10: "medium", 1 << 20: "large"} {
		if got := sizeBucket(n); got != want {
			t.Errorf("sizeBucket(%d) = %q; want %q", n, got, want)
		}
	}
}
